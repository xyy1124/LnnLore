import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_inn/models/thinking_chain_preset.dart';
import 'package:pocket_inn/services/storage_service.dart';
import 'package:pocket_inn/services/thinking_chain_guard.dart';
import 'package:pocket_inn/services/thinking_chain_preset_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const MethodChannel _pathProviderChannel = MethodChannel(
  'plugins.flutter.io/path_provider',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('pocket_inn_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, (methodCall) async {
          return tempDir.path;
        });
    SharedPreferences.setMockInitialValues({});
    await StorageService.instance.initialize();
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, null);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  setUp(() async {
    await StorageService.instance.clearAllData();
  });

  group('ThinkingChainPresetService', () {
    test('首次使用返回内置默认模板方案', () async {
      final presets = await ThinkingChainPresetService.instance.loadAll();
      expect(presets.length, 1);
      expect(presets.first.template, ThinkingChainGuard.systemTemplate);
    });

    test('添加方案并激活后 resolveActiveTemplate 返回新模板', () async {
      final service = ThinkingChainPresetService.instance;
      final id = service.generateId();
      const customTemplate = '【强制思维模式】\n自定义模板内容';
      await service.add(
        ThinkingChainPreset(
          id: id,
          name: '自定义方案',
          template: customTemplate,
          updatedAt: DateTime.now(),
        ),
        activate: true,
      );
      final template = await service.resolveActiveTemplate();
      expect(template, customTemplate);
    });

    test('删除生效方案后自动回退到剩余第一个', () async {
      final service = ThinkingChainPresetService.instance;
      final presets = await service.loadAll();
      final defaultId = presets.first.id;
      final customId = service.generateId();
      await service.add(
        ThinkingChainPreset(
          id: customId,
          name: '自定义',
          template: '自定义模板',
          updatedAt: DateTime.now(),
        ),
        activate: true,
      );
      await service.delete(customId);
      final activeId = await service.getActiveId();
      expect(activeId, defaultId);
      final template = await service.resolveActiveTemplate();
      expect(template, ThinkingChainGuard.systemTemplate);
    });

    test('更新方案模板后生效', () async {
      final service = ThinkingChainPresetService.instance;
      final presets = await service.loadAll();
      final defaultPreset = presets.first;
      const newTemplate = '【强制思维模式】\n修改后的模板';
      await service.update(
        defaultPreset.copyWith(
          template: newTemplate,
          updatedAt: DateTime.now(),
        ),
      );
      final template = await service.resolveActiveTemplate();
      expect(template, newTemplate);
    });

    test('失效的生效 id 自动回退到第一个方案', () async {
      final service = ThinkingChainPresetService.instance;
      // 直接写入一个不存在的 id
      await service.setActiveId('non-existent-id');
      final activeId = await service.getActiveId();
      final presets = await service.loadAll();
      expect(activeId, presets.first.id);
      final template = await service.resolveActiveTemplate();
      expect(template, ThinkingChainGuard.systemTemplate);
    });

    test('损坏的方案文件回退默认模板不崩溃', () async {
      await StorageService.instance.writeJsonMap(
        'thinking_chain_presets.json',
        {'version': 1, 'presets': ['not-a-map']},
      );
      final presets = await ThinkingChainPresetService.instance.loadAll();
      expect(presets.length, 1);
      expect(presets.first.template, ThinkingChainGuard.systemTemplate);
    });
  });
}
