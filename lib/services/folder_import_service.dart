import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'archive_import_service.dart';

/// 文件夹直接导入服务（特别版，Android）。
///
/// 通过原生通道（ACTION_OPEN_DOCUMENT_TREE + SAF 递归遍历）读取
/// 所选文件夹中的 json/png/zip 文件，返回文件列表供自动分辨导入。
class FolderImportService {
  FolderImportService._();

  static final FolderImportService instance = FolderImportService._();

  static const MethodChannel _channel = MethodChannel(
    'pocket_inn/folder_import',
  );

  /// 选择文件夹并读取其中的 json/png/zip 文件。
  ///
  /// 用户取消返回 null；平台不支持或失败抛出异常（调用方捕获提示）。
  /// 原生侧防护：单文件 30MB、总量 50MB；返回 truncated 标志表示截断。
  Future<FolderImportResult?> pickFolderAndReadFiles() async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'pickFolderAndReadFiles',
    );
    if (result == null) {
      return null;
    }
    final rawFiles = result['files'] as List<dynamic>? ?? const [];
    final files = <ImportFileEntry>[];
    for (final raw in rawFiles) {
      final map = raw as Map;
      final name = map['name'] as String;
      final encoded = map['bytes'] as String;
      final bytes = Uint8List.fromList(base64Decode(encoded));
      files.add((name: name, bytes: bytes));
    }
    return FolderImportResult(
      files: files,
      truncated: result['truncated'] == true,
    );
  }
}

/// 文件夹导入结果。
class FolderImportResult {
  const FolderImportResult({required this.files, required this.truncated});

  final List<ImportFileEntry> files;

  /// 是否因超过总量上限而截断。
  final bool truncated;
}
