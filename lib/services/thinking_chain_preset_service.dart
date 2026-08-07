import 'dart:math';

import '../models/thinking_chain_preset.dart';
import 'storage_service.dart';
import 'thinking_chain_guard.dart';

/// 思维链约束方案服务（特别版）。
///
/// 管理多套【强制思维模式】模板：数据存于 `thinking_chain_presets.json`
/// （结构 `{version, presets[]}`），当前生效方案的 id 存 SharedPreferences。
/// 首次使用内置当前默认模板作为唯一方案。
class ThinkingChainPresetService {
  ThinkingChainPresetService._();

  static final ThinkingChainPresetService instance =
      ThinkingChainPresetService._();

  // JSON 文件名
  static const String _filename = 'thinking_chain_presets.json';

  // SharedPreferences 键名（当前生效方案 id）
  static const String _keyActiveId = 'active_thinking_chain_preset_id';

  // 数据版本
  static const int _dataVersion = 1;

  /// 内置默认方案（id 固定，可被删除/覆盖）。
  static const String builtinPresetId = 'thinking-chain-default';

  /// 首次使用时的默认方案（即当前内置模板）。
  static ThinkingChainPreset defaultPreset() => ThinkingChainPreset(
    id: builtinPresetId,
    name: '默认模板',
    template: ThinkingChainGuard.systemTemplate,
    updatedAt: DateTime.now(),
  );

  /// 加载全部方案（首次使用返回默认方案）。
  Future<List<ThinkingChainPreset>> loadAll() async {
    final storage = StorageService.instance;

    final data = await storage.readJsonMap(_filename);
    if (data == null) {
      return [defaultPreset()];
    }

    try {
      final version = data['version'] as int? ?? 1;
      if (version != _dataVersion) {
        return [defaultPreset()];
      }

      final presetsList = data['presets'] as List<dynamic>?;
      if (presetsList == null || presetsList.isEmpty) {
        return [defaultPreset()];
      }

      return presetsList
          .map(
            (json) => ThinkingChainPreset.fromJson(
              json as Map<String, dynamic>,
            ),
          )
          .toList();
    } on Object {
      // 文件损坏（写入中断等）：回退默认方案
      return [defaultPreset()];
    }
  }

  /// 保存全部方案。
  Future<void> saveAll(List<ThinkingChainPreset> presets) async {
    final storage = StorageService.instance;
    final data = {
      'version': _dataVersion,
      'presets': presets.map((p) => p.toJson()).toList(),
    };
    await storage.writeJsonMap(_filename, data);
  }

  /// 添加方案（并可选设为生效）。
  Future<void> add(ThinkingChainPreset preset, {bool activate = false}) async {
    final presets = await loadAll();
    presets.add(preset);
    await saveAll(presets);
    if (activate) {
      await setActiveId(preset.id);
    }
  }

  /// 更新方案。
  Future<void> update(ThinkingChainPreset preset) async {
    final presets = await loadAll();
    final index = presets.indexWhere((p) => p.id == preset.id);
    if (index != -1) {
      presets[index] = preset;
      await saveAll(presets);
    }
  }

  /// 删除方案。若删除的是当前生效方案，自动回退到剩余第一个。
  Future<List<ThinkingChainPreset>> delete(String id) async {
    final presets = await loadAll();
    presets.removeWhere((p) => p.id == id);
    await saveAll(presets);

    if (await getActiveId() == id) {
      if (presets.isNotEmpty) {
        await setActiveId(presets.first.id);
      } else {
        await StorageService.instance.remove(_keyActiveId);
      }
    }
    return presets;
  }

  /// 获取当前生效方案 id（无或已失效则回退到第一个方案 id）。
  Future<String?> getActiveId() async {
    final presets = await loadAll();
    if (presets.isEmpty) {
      return null;
    }
    final saved = StorageService.instance.getString(_keyActiveId);
    if (saved != null && saved.isNotEmpty) {
      for (final preset in presets) {
        if (preset.id == saved) {
          return saved;
        }
      }
    }
    // 保存的 id 不存在（文件被恢复/替换等）：回退到第一个方案
    return presets.first.id;
  }

  /// 设置当前生效方案 id。
  Future<void> setActiveId(String id) async {
    await StorageService.instance.setString(_keyActiveId, id);
  }

  /// 解析当前生效的模板文本（供 chat_service 注入）。
  Future<String> resolveActiveTemplate() async {
    final presets = await loadAll();
    if (presets.isEmpty) {
      return ThinkingChainGuard.systemTemplate;
    }
    final activeId = await getActiveId();
    for (final preset in presets) {
      if (preset.id == activeId) {
        return preset.template;
      }
    }
    return presets.first.template;
  }

  /// 生成唯一ID。
  String generateId() {
    final random = Random().nextInt(0xFFFFFF).toRadixString(16);
    return 'thinking-chain-${DateTime.now().millisecondsSinceEpoch}-$random';
  }
}
