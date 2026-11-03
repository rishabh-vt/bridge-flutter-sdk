import 'package:shared_preferences/shared_preferences.dart';

import '../types/types.dart';
import 'constants.dart';

class SharedPreferencesStorage implements StorageAdapter {
  SharedPreferencesStorage([this._prefs]);

  SharedPreferences? _prefs;

  Future<SharedPreferences> _ensure() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  @override
  Future<String?> getItem(String key) async {
    final prefs = await _ensure();
    return prefs.getString(key);
  }

  @override
  Future<void> setItem(String key, String value) async {
    final prefs = await _ensure();
    await prefs.setString(key, value);
  }

  @override
  Future<void> removeItem(String key) async {
    final prefs = await _ensure();
    await prefs.remove(key);
  }
}

StorageAdapter getDefaultStorage() => SharedPreferencesStorage();

const String _redacted = '[REDACTED]';

Object? _redactValue(Object? value) {
  if (value == null) return value;
  if (value is String) return value;
  if (value is List) return value.map(_redactValue).toList();
  if (value is Map) {
    return value.map((k, v) {
      final key = k.toString();
      if (webviewAuthKeysSet.contains(key) && v != null) {
        return MapEntry(key, _redacted);
      }
      return MapEntry(key, _redactValue(v));
    });
  }
  return value;
}

List<Object?> _redactArgs(List<Object?> args) =>
    args.map(_redactValue).toList(growable: false);

class ConsoleLogger implements Logger {
  ConsoleLogger({required this.enabled});

  final bool enabled;

  void _log(String level, Object? message, List<Object?> args) {
    if (!enabled) return;
    // ignore: avoid_print
    print('[BridgeSDK][$level] $message ${_redactArgs(args)}');
  }

  @override
  void debug(Object? message, [List<Object?> args = const []]) =>
      _log('debug', message, args);

  @override
  void info(Object? message, [List<Object?> args = const []]) =>
      _log('info', message, args);

  @override
  void warn(Object? message, [List<Object?> args = const []]) =>
      _log('warn', message, args);

  @override
  void error(Object? message, [List<Object?> args = const []]) =>
      _log('error', message, args);
}

Logger createDefaultLogger({required bool enabled}) =>
    ConsoleLogger(enabled: enabled);
