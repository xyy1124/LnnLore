package com.adoretes.pocketinn

import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
import android.provider.Settings
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.InputStream
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread

/// 特别版：文件夹直接导入（Android SAF）。
///
/// 通过 ACTION_OPEN_DOCUMENT_TREE 选择文件夹，在后台线程递归读取
/// json/png/zip 文件，以 base64 返回给 Dart 层做自动分辨导入。
/// 防护：单文件 30MB、总量 50MB，隐藏文件与无关类型跳过。
///
/// v81：应用内自更新安装（PackageInstaller）——接收 Dart 侧下载好的
/// APK 路径，创建安装会话写入并提交，SessionCallback 回调结果；
/// Android 8+ 未授权"安装未知应用"时引导去设置页。
class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "pocket_inn/folder_import"
        private const val INSTALL_CHANNEL = "pocket_inn/app_installer"
        private const val REQUEST_OPEN_TREE = 7401
        private const val REQUEST_INSTALL_PERMISSION = 7402
        private const val MAX_FILE_BYTES = 30L * 1024 * 1024
        // 总量上限 50MB：base64 传输会膨胀约 3-4 倍峰值内存，
        // 角色导入场景足够，避免低内存设备 OOM。
        private const val MAX_TOTAL_BYTES = 50L * 1024 * 1024
    }

    private var pendingResult: MethodChannel.Result? = null
    private val picking = AtomicBoolean(false)
    private val destroyed = AtomicBoolean(false)

    // v81：安装状态（与文件夹选择共用 destroyed 标记）
    private var pendingInstallResult: MethodChannel.Result? = null
    private val installing = AtomicBoolean(false)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickFolderAndReadFiles" -> pickFolderAndReadFiles(result)
                    else -> result.notImplemented()
                }
            }
        // v81：应用内自更新安装通道
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, INSTALL_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("bad_args", "missing apk path", null)
                        } else {
                            installApk(path, result)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        destroyed.set(true)
        // 选择器/遍历期间 Activity 被销毁：清理挂起的回调，避免 Dart 侧永久等待；
        // 后台遍历线程回复前会检查 destroyed，避免双重回复。
        val result = pendingResult
        if (result != null) {
            pendingResult = null
            picking.set(false)
            result.error("cancelled", "folder picker cancelled", null)
        }
        // v81：安装期间 Activity 被销毁：回复 cancelled
        val installResult = pendingInstallResult
        if (installResult != null) {
            pendingInstallResult = null
            installing.set(false)
            installResult.error("cancelled", "install cancelled", null)
        }
        super.onDestroy()
    }

    private fun pickFolderAndReadFiles(result: MethodChannel.Result) {
        if (picking.getAndSet(true)) {
            result.error("busy", "folder picker already active", null)
            return
        }
        pendingResult = result
        try {
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
            }
            startActivityForResult(intent, REQUEST_OPEN_TREE)
        } catch (e: Exception) {
            pendingResult = null
            picking.set(false)
            result.error("pick", "cannot open folder picker: ${e.message}", null)
        }
    }

    // ---- v81：应用内自更新安装 ----

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQUEST_INSTALL_PERMISSION) {
            // 从"安装未知应用"设置页返回：重新检查授权
            val result = pendingInstallResult
            pendingInstallResult = null
            installing.set(false)
            if (result == null) {
                return
            }
            val authorized = Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
                packageManager.canRequestPackageInstalls()
            if (authorized) {
                // 重新触发安装（授权后返回的 intent 不带 apk 路径，用挂起字段）
                installApkPath?.let { installApk(it, result) }
                    ?: result.error("install_failed", "missing apk path", null)
            } else {
                result.error("not_authorized", "unknown app sources not authorized", null)
            }
            return
        }
        if (requestCode != REQUEST_OPEN_TREE) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        // picking 保持 true 直到遍历线程结束，避免期间重复发起选择
        // 导致首个 Dart 调用永久悬挂；onDestroy 中会复位并回复 cancelled。
        val result = pendingResult ?: run {
            picking.set(false)
            return
        }
        pendingResult = null
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            picking.set(false)
            result.success(null) // user cancelled
            return
        }
        val treeUri = data.data!!
        // 遍历与编码放到后台线程，避免主线程 ANR
        thread {
            try {
                try {
                    contentResolver.takePersistableUriPermission(
                        treeUri,
                        Intent.FLAG_GRANT_READ_URI_PERMISSION
                    )
                } catch (_: SecurityException) {
                    // persisting permission is best-effort only
                }
                val files = mutableListOf<Map<String, Any?>>()
                var total = 0L
                val maxed = AtomicBoolean(false)
                walkTree(treeUri, DocumentsContract.getTreeDocumentId(treeUri), "", files, maxed) { size ->
                    total += size
                    total > MAX_TOTAL_BYTES
                }
                if (destroyed.get()) {
                    picking.set(false)
                    return@thread // onDestroy 已回复 cancelled，避免双重回复
                }
                picking.set(false)
                result.success(
                    mapOf(
                        "files" to files,
                        "truncated" to maxed.get(),
                    )
                )
            } catch (e: Exception) {
                picking.set(false)
                if (!destroyed.get()) {
                    result.error("read", "failed to read folder: ${e.message}", null)
                }
            }
        }
    }

    /// 授权流程中挂起的 apk 路径（从设置页返回后重新发起安装用）。
    private var installApkPath: String? = null

    private fun installApk(path: String, result: MethodChannel.Result) {
        if (installing.getAndSet(true)) {
            result.error("busy", "install already active", null)
            return
        }
        // Android 8.0+ 需要"安装未知应用"授权
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()
        ) {
            installing.set(false)
            pendingInstallResult = result
            installApkPath = path
            try {
                startActivityForResult(
                    Intent(
                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:$packageName")
                    ),
                    REQUEST_INSTALL_PERMISSION
                )
            } catch (e: Exception) {
                pendingInstallResult = null
                installApkPath = null
                result.error("not_authorized", "cannot open install settings: ${e.message}", null)
            }
            return
        }
        startInstallSession(path, result)
    }

    private fun startInstallSession(path: String, result: MethodChannel.Result) {
        pendingInstallResult = result
        installApkPath = path
        val apkFile = File(path)
        if (!apkFile.exists()) {
            pendingInstallResult = null
            installApkPath = null
            installing.set(false)
            result.error("install_failed", "apk not found: $path", null)
            return
        }
        thread {
            var session: PackageInstaller.Session? = null
            var receiver: BroadcastReceiver? = null
            try {
                val packageInstaller = packageManager.packageInstaller
                val params = PackageInstaller.SessionParams(
                    PackageInstaller.SessionParams.MODE_FULL_INSTALL
                )
                val sessionId = packageInstaller.createSession(params)
                session = packageInstaller.openSession(sessionId)
                val input = FileInputStream(apkFile)
                val output = session.openWrite("lnnlore_update", 0, apkFile.length())
                try {
                    input.use { inputStream ->
                        output.use { out ->
                            val buffer = ByteArray(256 * 1024)
                            while (true) {
                                val read = inputStream.read(buffer)
                                if (read < 0) break
                                out.write(buffer, 0, read)
                            }
                        }
                    }
                } catch (e: Exception) {
                    session.abandon()
                    throw e
                }

                val action = "com.adoretes.pocketinn.PACKAGE_INSTALL_$sessionId"
                receiver = object : BroadcastReceiver() {
                    override fun onReceive(context: Context, intent: Intent) {
                        if (intent.getIntExtra(PackageInstaller.EXTRA_SESSION_ID, -1) != sessionId) {
                            return
                        }
                        val status = intent.getIntExtra(
                            PackageInstaller.EXTRA_STATUS,
                            PackageInstaller.STATUS_FAILURE,
                        )
                        if (status == PackageInstaller.STATUS_PENDING_USER_ACTION) {
                            val confirmation = intent.getParcelableExtra<Intent>(
                                Intent.EXTRA_INTENT,
                            )
                            if (confirmation != null) {
                                confirmation.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                startActivity(confirmation)
                            }
                            return
                        }
                        try {
                            unregisterReceiver(this)
                        } catch (_: Exception) {}
                        runOnUiThread {
                            val r = pendingInstallResult
                            pendingInstallResult = null
                            installApkPath = null
                            installing.set(false)
                            if (status == PackageInstaller.STATUS_SUCCESS) {
                                r?.success(true)
                            } else {
                                val message = intent.getStringExtra(
                                    PackageInstaller.EXTRA_STATUS_MESSAGE,
                                ) ?: "package installer status $status"
                                r?.error(
                                    installErrorCode(status),
                                    message,
                                    status,
                                )
                            }
                        }
                    }
                }
                val filter = IntentFilter(action)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
                } else {
                    @Suppress("DEPRECATION")
                    registerReceiver(receiver, filter)
                }
                val callbackIntent = Intent(action).setPackage(packageName)
                val pendingFlags = PendingIntent.FLAG_UPDATE_CURRENT or
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        PendingIntent.FLAG_IMMUTABLE
                    } else {
                        0
                    }
                val pendingIntent = PendingIntent.getBroadcast(
                    this,
                    sessionId,
                    callbackIntent,
                    pendingFlags,
                )
                // PackageInstaller requires a non-null IntentSender. Passing null
                // made every downloaded APK fail at the commit stage.
                session.commit(pendingIntent.intentSender)
            } catch (e: Exception) {
                try {
                    receiver?.let { unregisterReceiver(it) }
                } catch (_: Exception) {}
                session?.abandon()
                runOnUiThread {
                    val r = pendingInstallResult
                    pendingInstallResult = null
                    installApkPath = null
                    installing.set(false)
                    r?.error("install_failed", "install failed: ${e.message}", null)
                }
            }
        }
    }

    private fun installErrorCode(status: Int): String = when (status) {
        PackageInstaller.STATUS_FAILURE_INCOMPATIBLE -> "install_failed_update_incompatible"
        PackageInstaller.STATUS_FAILURE_INVALID -> "install_failed_invalid_apk"
        PackageInstaller.STATUS_FAILURE_CONFLICT -> "install_failed_conflict"
        PackageInstaller.STATUS_FAILURE_STORAGE -> "install_failed_storage"
        else -> "install_failed"
    }

    /// 递归遍历目录树。
    /// [treeUri] 恒为根 tree URI；[docId] 为当前目录的 document id，
    /// 子目录递归时以根 treeUri + 子目录 docId 构建，避免
    /// getTreeDocumentId(documentUri) 返回根 id 导致的无限递归。
    private fun walkTree(
        treeUri: Uri,
        docId: String,
        prefix: String,
        out: MutableList<Map<String, Any?>>,
        maxed: AtomicBoolean,
        accumulate: (Long) -> Boolean,
    ) {
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, docId)
        val resolver = contentResolver
        resolver.query(
            childrenUri,
            arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_MIME_TYPE,
            ),
            null,
            null,
            null,
        )?.use { cursor ->
            while (cursor.moveToNext() && !maxed.get()) {
                val childId = cursor.getString(0) ?: continue
                val name = cursor.getString(1) ?: childId
                if (name.startsWith(".")) continue
                val mime = cursor.getString(2) ?: ""
                if (DocumentsContract.Document.MIME_TYPE_DIR == mime) {
                    walkTree(treeUri, childId, "$prefix$name/", out, maxed, accumulate)
                    continue
                }
                val lower = name.lowercase()
                if (!lower.endsWith(".json") &&
                    !lower.endsWith(".png") &&
                    !lower.endsWith(".zip")
                ) {
                    continue
                }
                val bytes = readAllBytes(
                    DocumentsContract.buildDocumentUriUsingTree(treeUri, childId)
                ) ?: continue
                if (bytes.size > MAX_FILE_BYTES) continue
                if (accumulate(bytes.size.toLong())) {
                    maxed.set(true)
                    break
                }
                out.add(
                    mapOf(
                        "name" to "$prefix$name",
                        "bytes" to Base64.encodeToString(bytes, Base64.NO_WRAP),
                    )
                )
            }
        }
    }

    private fun readAllBytes(uri: Uri): ByteArray? {
        return try {
            val stream: InputStream? = contentResolver.openInputStream(uri)
            if (stream == null) {
                null
            } else {
                stream.use { input ->
                    val buffer = ByteArrayOutputStream()
                    val chunk = ByteArray(64 * 1024)
                    while (true) {
                        val read = input.read(chunk)
                        if (read < 0) break
                        buffer.write(chunk, 0, read)
                        if (buffer.size() > MAX_FILE_BYTES) return@use null
                    }
                    buffer.toByteArray()
                }
            }
        } catch (_: Exception) {
            null
        }
    }
}
