const List<String> blockedSchemes = [
  'javascript:',
  'data:',
  'file:',
  'blob:',
  'intent:',
  'content:',
  'about:',
  'view-source:',
];

const int maxCrashRecoveries = 2;

bool isBlockedScheme(String url) {
  final lower = url.trim().toLowerCase();
  return blockedSchemes.any(lower.startsWith);
}

String? safeOrigin(String url) {
  try {
    final uri = Uri.parse(url);
    if (!uri.hasScheme || uri.host.isEmpty) return null;
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$port';
  } catch (_) {
    return null;
  }
}

Set<String> buildOriginWhitelist({
  required String webviewUrl,
  List<String>? allowedOrigins,
}) {
  final origins = <String>{};
  final base = safeOrigin(webviewUrl);
  if (base != null) origins.add(base);
  if (allowedOrigins != null) {
    for (final o in allowedOrigins) {
      final parsed = safeOrigin(o);
      if (parsed != null) origins.add(parsed);
    }
  }
  return origins;
}

({bool allowed, String? reason}) isUrlAllowed(
  String url,
  Set<String> whitelist,
) {
  if (isBlockedScheme(url)) {
    return (allowed: false, reason: 'blocked-scheme');
  }
  final origin = safeOrigin(url);
  if (origin == null) {
    return (allowed: false, reason: 'unparseable-url');
  }
  if (!whitelist.contains(origin)) {
    return (allowed: false, reason: 'origin-not-whitelisted');
  }
  return (allowed: true, reason: null);
}

/// Escape a value for safe embedding inside an injected JS body.
String safeJsLiteral(Object? value) {
  // Use dart:convert via jsonEncode equivalent through a small helper.
  final json = _jsonEncode(value);
  return json
      .replaceAll('\u2028', '\\u2028')
      .replaceAll('\u2029', '\\u2029')
      .replaceAllMapped(
        RegExp(r'<\/(script)', caseSensitive: false),
        (m) => '<\\/${m[1]}',
      );
}

String _jsonEncode(Object? value) {
  if (value == null) return 'null';
  if (value is String) return _quote(value);
  if (value is num || value is bool) return value.toString();
  if (value is List) {
    return '[${value.map(_jsonEncode).join(',')}]';
  }
  if (value is Map) {
    final entries = value.entries.map((e) {
      return '${_quote(e.key.toString())}:${_jsonEncode(e.value)}';
    });
    return '{${entries.join(',')}}';
  }
  return _quote(value.toString());
}

String _quote(String s) {
  final escaped = s
      .replaceAll(r'\', r'\\')
      .replaceAll('"', r'\"')
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r')
      .replaceAll('\t', r'\t');
  return '"$escaped"';
}

({bool ok, String? reason}) validateUrlScheme(
  String url, {
  String? environment,
}) {
  late final Uri parsed;
  try {
    parsed = Uri.parse(url);
  } catch (_) {
    return (ok: false, reason: 'malformed URL');
  }
  if (parsed.scheme == 'https') return (ok: true, reason: null);
  if (parsed.scheme == 'http' && environment == 'dev') {
    return (ok: true, reason: null);
  }
  return (
    ok: false,
    reason:
        'non-HTTPS URL not permitted (got ${parsed.scheme}:). Use environment="dev" to allow HTTP.',
  );
}
