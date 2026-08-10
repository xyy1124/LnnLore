import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/app_update_info.dart';
import '../services/app_installer_service.dart';
import '../services/update_download_service.dart';

/// v81：应用内自更新对话框——展示新版本信息 → 下载（进度条）→
/// 安装（PackageInstaller，系统弹确认）→ 结果。
///
/// 用法：
/// ```dart
/// await UpdateDialog.show(
///   context,
///   update: updateInfo,
///   currentVersion: packageInfo.version,
/// );
/// ```
class UpdateDialog extends StatefulWidget {
  const UpdateDialog({
    super.key,
    required this.update,
    required this.currentVersion,
  });

  final AppUpdateInfo update;
  final String currentVersion;

  static Future<void> show(
    BuildContext context, {
    required AppUpdateInfo update,
    required String currentVersion,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => UpdateDialog(
        update: update,
        currentVersion: currentVersion,
      ),
    );
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

enum _UpdatePhase { prompt, downloading, installing, done, error }

class _UpdateDialogState extends State<UpdateDialog> {
  _UpdatePhase _phase = _UpdatePhase.prompt;
  double _progress = 0;
  String _statusText = '';
  bool _cancelled = false;

  String get _sizeText {
    final size = widget.update.sizeText;
    return size.isEmpty ? '' : '（$size）';
  }

  Future<void> _startUpdate() async {
    setState(() {
      _phase = _UpdatePhase.downloading;
      _progress = 0;
      _statusText = '正在连接下载源…';
    });
    try {
      final apkPath = await UpdateDownloadService.instance.downloadApk(
        url: widget.update.downloadUrl,
        onProgress: (received, total) {
          if (!mounted) {
            return;
          }
          setState(() {
            if (total > 0) {
              _progress = received / total;
              _statusText =
                  '下载中 ${(received / 1024 / 1024).toStringAsFixed(1)} / '
                  '${(total / 1024 / 1024).toStringAsFixed(1)} MB';
            } else {
              _statusText = '下载中…';
            }
          });
        },
        isCancelled: () async => _cancelled,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _phase = _UpdatePhase.installing;
        _statusText = '正在安装…（请在系统弹窗中确认）';
      });
      await AppInstallerService.instance.installApk(apkPath);
      if (!mounted) {
        return;
      }
      setState(() {
        _phase = _UpdatePhase.done;
        _statusText = '新版本已安装完成，重启应用后生效';
      });
    } on UpdateDownloadCancelledException {
      if (mounted) {
        Navigator.of(context).pop();
      }
    } on PlatformException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _phase = _UpdatePhase.error;
        _statusText = _installErrorText(e.code, e.message);
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _phase = _UpdatePhase.error;
        _statusText = '更新失败：$e';
      });
    }
  }

  String _installErrorText(String code, String? message) {
    switch (code) {
      case 'not_authorized':
        return '未授权安装未知应用，请在系统设置中允许后重试';
      case 'busy':
        return '已有安装在进行中，请稍后重试';
      case 'cancelled':
        return '安装已取消';
      default:
        return '安装失败：${message ?? '未知错误'}'
            '（常见原因：签名不一致或包损坏）';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.system_update_alt, color: colorScheme.primary),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('发现新版本', style: TextStyle(fontSize: 18)),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.update.tagName}'
              '${_sizeText.isEmpty ? '' : '  $_sizeText'}'
              '（当前 ${widget.currentVersion}）',
              style: TextStyle(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            if (_phase == _UpdatePhase.prompt) ...[
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: SingleChildScrollView(
                    child: Text(
                      widget.update.body.trim().isEmpty
                          ? '（该版本没有更新说明）'
                          : widget.update.body,
                      style: const TextStyle(fontSize: 13, height: 1.5),
                    ),
                  ),
                ),
              ),
            ] else ...[
              LinearProgressIndicator(
                value: _phase == _UpdatePhase.downloading ? _progress : null,
              ),
              const SizedBox(height: 8),
              Text(
                _statusText,
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (_phase == _UpdatePhase.prompt)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('稍后'),
          ),
        if (_phase == _UpdatePhase.prompt)
          FilledButton(
            onPressed: _startUpdate,
            child: const Text('立即更新'),
          ),
        if (_phase == _UpdatePhase.downloading)
          TextButton(
            onPressed: () {
              _cancelled = true;
            },
            child: const Text('取消下载'),
          ),
        if (_phase == _UpdatePhase.installing)
          const TextButton(
            onPressed: null,
            child: Text('安装中…'),
          ),
        if (_phase == _UpdatePhase.done)
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('完成'),
          ),
        if (_phase == _UpdatePhase.error)
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
      ],
    );
  }
}
