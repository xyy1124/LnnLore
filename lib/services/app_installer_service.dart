import 'package:flutter/services.dart';

/// v81：应用内自更新安装——调用原生 PackageInstaller 安装下载好的 APK。
///
/// 错误码（来自 MainActivity）：
/// - `busy`：已有安装在进行中
/// - `not_authorized`：Android 8+ 未授权"安装未知应用"（原生已引导去设置页）
/// - `install_failed`：安装失败（签名不一致/包损坏/被拒绝等）
/// - `cancelled`：页面销毁或用户取消
class AppInstallerService {
  AppInstallerService._();

  static final AppInstallerService instance = AppInstallerService._();

  static const MethodChannel _channel = MethodChannel('pocket_inn/app_installer');

  /// 安装 APK 文件。成功返回 true；失败抛 [PlatformException]（code 见上）。
  /// 安装过程中系统会弹出确认界面（Android 平台限制，无法静默安装）。
  Future<bool> installApk(String apkPath) async {
    final result = await _channel.invokeMethod<bool>('installApk', {
      'path': apkPath,
    });
    return result ?? false;
  }
}
