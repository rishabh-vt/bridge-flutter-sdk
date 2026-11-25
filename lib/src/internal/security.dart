const List<String> blockedSchemes = [
  'javascript:',
  'file:',
  'intent:',
  'content:',
  'view-source:',
];

/// Schemes that WebViews use during bootstrap / iframes — never cancel these.
bool isIgnorableNavigationScheme(String url) {
  final lower = url.trim().toLowerCase();
  return lower.startsWith('about:') ||
      lower.startsWith('data:') ||
      lower.startsWith('blob:');
}

bool isBlockedScheme(String url) {
  final lower = url.trim().toLowerCase();
  return blockedSchemes.any(lower.startsWith);
}

/// Launch URLs from Bridge must be HTTPS.
({bool ok, String? reason}) validateHttpsUrl(String url) {
  late final Uri parsed;
  try {
    parsed = Uri.parse(url);
  } catch (_) {
    return (ok: false, reason: 'malformed URL');
  }
  if (parsed.scheme == 'https') return (ok: true, reason: null);
  return (
    ok: false,
    reason: 'non-HTTPS URL not permitted (got ${parsed.scheme}:)',
  );
}

/// Mobile returnUrl must be a custom scheme (not http/https), e.g. `myapp://sdk-return`.
({bool ok, String? reason}) validateReturnUrl(String url) {
  late final Uri parsed;
  try {
    parsed = Uri.parse(url);
  } catch (_) {
    return (ok: false, reason: 'malformed URL');
  }
  final scheme = parsed.scheme.toLowerCase();
  if (scheme.isEmpty) {
    return (ok: false, reason: 'missing URL scheme');
  }
  if (scheme == 'http' || scheme == 'https') {
    return (
      ok: false,
      reason:
          'returnUrl must be a custom app scheme (e.g. myapp://sdk-return), not http(s)',
    );
  }
  if (scheme == 'javascript' ||
      scheme == 'file' ||
      scheme == 'data' ||
      scheme == 'blob') {
    return (ok: false, reason: 'blocked scheme "$scheme"');
  }
  return (ok: true, reason: null);
}

String _stripQueryAndFragment(String url) {
  final noHash = url.split('#').first;
  return noHash.split('?').first;
}

/// True when [url] is the configured custom-scheme [returnUrl] (query ignored).
bool isReturnUrl(String url, String returnUrl) {
  if (returnUrl.isEmpty) return false;
  final normalized = url.trim();
  final target = returnUrl.trim();
  if (normalized.isEmpty) return false;

  final actualBase = _stripQueryAndFragment(normalized);
  final targetBase = _stripQueryAndFragment(target);

  if (actualBase.toLowerCase() == targetBase.toLowerCase()) return true;
  if (actualBase.toLowerCase().startsWith('${targetBase.toLowerCase()}/')) {
    return true;
  }

  try {
    final actual = Uri.parse(normalized);
    final expected = Uri.parse(target);
    if (actual.scheme.toLowerCase() != expected.scheme.toLowerCase()) {
      return false;
    }

    // myapp://sdk-return  → host = sdk-return
    if (expected.host.isNotEmpty) {
      return actual.host.toLowerCase() == expected.host.toLowerCase();
    }

    // myapp:///sdk-return or path-only forms
    String clean(String p) => p.replaceFirst(RegExp(r'^/+'), '');
    final ep = clean(expected.path);
    final ap = clean(actual.path);
    if (ep.isEmpty) return true;
    return ap == ep || ap.startsWith('$ep/');
  } catch (_) {
    return normalized.toLowerCase().startsWith(targetBase.toLowerCase());
  }
}

String? returnReason(String url) {
  try {
    return Uri.parse(url).queryParameters['reason'];
  } catch (_) {
    return null;
  }
}
