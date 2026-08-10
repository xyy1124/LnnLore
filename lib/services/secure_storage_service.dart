import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  SecureStorageService._();

  static final SecureStorageService instance = SecureStorageService._();

  static const String _apiKeyPrefix = 'api_key_';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<void> saveApiKey(String configId, String apiKey) async {
    if (apiKey.trim().isEmpty) {
      await _storage.delete(key: '$_apiKeyPrefix$configId');
      return;
    }
    await _storage.write(key: '$_apiKeyPrefix$configId', value: apiKey.trim());
  }

  Future<String> readApiKey(String configId) async {
    return await _storage.read(key: '$_apiKeyPrefix$configId') ?? '';
  }

  Future<void> deleteApiKey(String configId) async {
    await _storage.delete(key: '$_apiKeyPrefix$configId');
  }

  /// v80：清理全部 API key（重置/清空数据时调用）——secure storage
  /// 无法按前缀列举，先 readAll 再按前缀删除。
  Future<void> clearApiKeys() async {
    final all = await _storage.readAll();
    for (final key in all.keys) {
      if (key.startsWith(_apiKeyPrefix)) {
        await _storage.delete(key: key);
      }
    }
  }

  Future<void> saveSecret(String key, String value) async {
    if (value.trim().isEmpty) {
      await _storage.delete(key: key);
      return;
    }
    await _storage.write(key: key, value: value);
  }

  Future<String> readSecret(String key) async {
    return await _storage.read(key: key) ?? '';
  }

  Future<void> deleteSecret(String key) async {
    await _storage.delete(key: key);
  }
}
