package com.adoretes.pocketinn

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread

/// 特别版：文件夹直接导入（Android SAF）。
///
/// 通过 ACTION_OPEN_DOCUMENT_TREE 选择文件夹，在后台线程递归读取
/// json/png/zip 文件，以 base64 返回给 Dart 层做自动分辨导入。
/// 防护：单文件 30MB、总量 50MB，隐藏文件与无关类型跳过。
class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "pocket_inn/folder_import"
        private const val REQUEST_OPEN_TREE = 7401
        private const val MAX_FILE_BYTES = 30L * 1024 * 1024
        // 总量上限 50MB：base64 传输会膨胀约 3-4 倍峰值内存，
        // 角色导入场景足够，避免低内存设备 OOM。
        private const val MAX_TOTAL_BYTES = 50L * 1024 * 1024
    }

    private var pendingResult: MethodChannel.Result? = null
    private val picking = AtomicBoolean(false)
    private val destroyed = AtomicBoolean(false)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickFolderAndReadFiles" -> pickFolderAndReadFiles(result)
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
        super.onDestroy()
    }

    private fun pickFolderAndReadFiles(result: MethodChannel.Result) {
        if (picking.getAndSet(true)) {
            result.error("busy", "folder picker already active", null)
            return
        }
        pendingResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
            )
        }
        try {
            startActivityForResult(intent, REQUEST_OPEN_TREE)
        } catch (e: Exception) {
            picking.set(false)
            pendingResult = null
            result.error("intent", "cannot open folder picker: ${e.message}", null)
        }
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
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
