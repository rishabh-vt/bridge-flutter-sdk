import 'dart:convert';

import '../internal/constants.dart';
import '../types/types.dart';

class StorageService {
  StorageService(this._storage, this._logger);

  final StorageAdapter _storage;
  final Logger _logger;

  Future<AuthTokens> loadTokens() async {
    try {
      final raw = await _storage.getItem(webviewTokensKey);
      if (raw == null || raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map(
          (k, v) => MapEntry(k.toString(), v as String?),
        );
      }
      return {};
    } catch (error) {
      _logger.warn('Failed to load persisted tokens', [error]);
      return {};
    }
  }

  Future<void> saveTokens(AuthTokens tokens) async {
    try {
      await _storage.setItem(webviewTokensKey, jsonEncode(tokens));
    } catch (error) {
      _logger.warn('Failed to persist tokens', [error]);
    }
  }

  Future<void> clearTokens() async {
    try {
      await _storage.removeItem(webviewTokensKey);
    } catch (error) {
      _logger.warn('Failed to clear tokens', [error]);
    }
  }
}
