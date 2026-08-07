import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';

/// 导入文件条目（文件名 + 字节）。
typedef ImportFileEntry = ({String name, Uint8List bytes});

/// 压缩包导入服务（特别版）。
///
/// 负责展开 zip 压缩包为文件列表，供批量导入使用。
class ArchiveImportService {
  ArchiveImportService._();

  static final ArchiveImportService instance = ArchiveImportService._();

  /// 支持的压缩包扩展名。
  static const List<String> archiveExtensions = ['zip'];

  /// 解压防护：单文件大小上限（50MB）与解压总量上限（200MB），
  /// 防止压缩炸弹导致内存耗尽。
  static const int maxEntryBytes = 50 * 1024 * 1024;
  static const int maxTotalBytes = 200 * 1024 * 1024;

  /// 压缩包文件本身大小上限（100MB）。
  static const int maxZipBytes = 100 * 1024 * 1024;

  /// PNG 解码安全预算：宽高均 ≤ 8192 且像素总数 ≤ 3355 万
  /// （约 8192×4096），超限的图片不参与解码，防止恶意 png 触发 OOM。
  static const int maxPngDimension = 8192;
  static const int maxPngPixels = 33 * 1024 * 1024;

  /// 特别版：编辑页立绘的放宽预算（用户自选本地文件，非导入攻击面）。
  static const int maxPngDimensionPortrait = 16384;
  static const int maxPngPixelsPortrait = 256 * 1024 * 1024;

  /// 检查 png 头部的 IHDR 宽高是否在安全预算内。
  /// 返回 false 表示无法读取 IHDR 或尺寸超限（不参与解码）。
  /// [maxDimension]/[maxPixels] 可放宽（编辑页立绘场景）。
  static bool hasSafePngDimensions(
    Uint8List bytes, {
    int maxDimension = maxPngDimension,
    int maxPixels = maxPngPixels,
  }) {
    if (bytes.length < 24) {
      return false;
    }
    // PNG 签名(8) + 长度(4) + 'IHDR'(4)，宽高为大端 4 字节
    if (bytes[12] != 0x49 || bytes[13] != 0x48 || bytes[14] != 0x44 ||
        bytes[15] != 0x52) {
      return false;
    }
    final width =
        (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
    final height =
        (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23];
    return width > 0 &&
        height > 0 &&
        width <= maxDimension &&
        height <= maxDimension &&
        (width * height) <= maxPixels;
  }

  /// 展开压缩包：把 [entries] 中的 zip 文件解压为内部文件，
  /// 普通文件原样保留。
  Future<List<ImportFileEntry>> expandArchives(
    List<ImportFileEntry> entries,
  ) async {
    final result = <ImportFileEntry>[];
    var totalBytes = 0;
    for (final entry in entries) {
      final lower = entry.name.toLowerCase();
      final isArchive = archiveExtensions.any(lower.endsWith);
      if (!isArchive) {
        totalBytes += entry.bytes.length;
        result.add(entry);
        continue;
      }
      try {
        if (entry.bytes.length > maxZipBytes) {
          continue; // 压缩包本身过大，跳过
        }
        // 解码前先做 header 预检（file.size 为条目声明大小），
        // 解码后仍对实际解压大小做二次检查（最后防线）。
        // 注：archive 3.x 无流式解压 API，恶意伪造 header 的极端
        // 压缩炸弹场景仍可能瞬时分配较大内存；本地自选文件导入的
        // 威胁模型下可接受（zip 总大小已限 100MB）。
        final archive = ZipDecoder().decodeBytes(entry.bytes);
        for (final file in archive.files) {
          if (file.isFile) {
            final name = file.name;
            // 跳过隐藏文件与路径穿越风险项（按路径段检查，避免误伤
            // 包含 '..' 的普通文件名）
            if (name.isEmpty ||
                name.startsWith('.') ||
                _hasUnsafePathSegment(name) ||
                file.size > maxEntryBytes) {
              continue;
            }
            final bytes = Uint8List.fromList(file.content as List<int>);
            if (bytes.length > maxEntryBytes ||
                totalBytes + bytes.length > maxTotalBytes) {
              continue; // 超出解压防护上限：跳过该文件
            }
            totalBytes += bytes.length;
            result.add((name: name, bytes: bytes));
          }
        }
      } on Object {
        // 损坏的压缩包：跳过，不计入失败（由导入层按文件缺失处理）
        continue;
      }
    }
    return result;
  }

  /// 检查文件名是否含不安全路径段（.. 或 . 作为目录段）。
  static bool _hasUnsafePathSegment(String name) {
    for (final segment in name.split(RegExp(r'[/\\]'))) {
      if (segment == '..' || segment == '.') {
        return true;
      }
    }
    return false;
  }

  /// 提取文件名扩展名（小写，不含点）。
  static String extensionOf(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0) {
      return '';
    }
    return name.substring(dot + 1).toLowerCase();
  }

  /// 提取去扩展名的 basename。
  static String basenameWithoutExtension(String name) {
    final slash = name.lastIndexOf('/');
    final base = slash >= 0 ? name.substring(slash + 1) : name;
    final dot = base.lastIndexOf('.');
    return dot > 0 ? base.substring(0, dot) : base;
  }

  /// 尝试把文本解析为 JSON Map（失败返回 null）。
  static Map<String, dynamic>? tryDecodeJson(String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } on Object {
      return null;
    }
    return null;
  }
}
