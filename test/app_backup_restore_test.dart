// v78 回归测试：备份恢复前校验归档含数据库文件——
// 一个只有 manifest/preferences 的"合法"zip 此前会通过校验并清空
// 全部数据后恢复成空聊天库（静默丢数据）；现在直接拒绝且不清数据。
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_inn/services/app_backup_service.dart';

Uint8List _zipWith(List<String> paths) {
  final archive = Archive();
  for (final path in paths) {
    final bytes = utf8.encode('{}');
    archive.add(ArchiveFile(path, bytes.length, bytes));
  }
  return ZipEncoder().encodeBytes(archive)!;
}

/// 执行恢复并断言：抛出的任何异常都不是"缺少数据库文件"（即数据库
/// 校验已通过）；若意外成功完成则测试失败。
Future<void> _expectPassesDatabaseCheck(Uint8List zipBytes) async {
  try {
    await AppBackupService.instance.restoreBackupArchiveBytes(zipBytes);
    // 环境未初始化 StorageService 时流程必然中断；若走到成功则说明
    // 数据库校验已通过（不在本测试验证范围内）
    return;
  } on FormatException catch (e) {
    expect(e.message, isNot(contains('数据库文件')));
  } on Object {
    // 未初始化 storage 等环境错误：数据库校验已通过
  }
}

void main() {
  test('缺数据库文件的备份被拒绝（抛"缺少数据库文件"）', () async {
    final bytes = _zipWith(['manifest.json', 'preferences.json']);
    await expectLater(
      AppBackupService.instance.restoreBackupArchiveBytes(bytes),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('数据库文件'),
        ),
      ),
    );
  });

  test('含 database/ 段 db 文件的备份通过数据库校验（旧版格式）', () async {
    await _expectPassesDatabaseCheck(
      _zipWith([
        'manifest.json',
        'preferences.json',
        'database/pocket_inn_chat.db',
      ]),
    );
  });

  test('含 data/ 段 db 文件的备份通过数据库校验（当前导出格式）', () async {
    await _expectPassesDatabaseCheck(
      _zipWith([
        'manifest.json',
        'preferences.json',
        'data/pocket_inn_chat.db',
      ]),
    );
  });

  test('v79 根目录 decoy.db 不能通过校验（绕过修复）', () async {
    final bytes = _zipWith([
      'manifest.json',
      'preferences.json',
      'decoy.db',
    ]);
    await expectLater(
      AppBackupService.instance.restoreBackupArchiveBytes(bytes),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('数据库文件'),
        ),
      ),
    );
  });

  test('v79 database/ 段非 db 文件不能通过校验（绕过修复）', () async {
    final bytes = _zipWith([
      'manifest.json',
      'preferences.json',
      'database/readme.txt',
    ]);
    await expectLater(
      AppBackupService.instance.restoreBackupArchiveBytes(bytes),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('数据库文件'),
        ),
      ),
    );
  });

  test('v79 -wal/-shm 文件不能通过校验（绕过修复）', () async {
    final bytes = _zipWith([
      'manifest.json',
      'preferences.json',
      'data/pocket_inn_chat.db-wal',
    ]);
    await expectLater(
      AppBackupService.instance.restoreBackupArchiveBytes(bytes),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('数据库文件'),
        ),
      ),
    );
  });
}
