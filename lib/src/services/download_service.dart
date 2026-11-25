import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/// Host MethodChannel that saves bytes into the public Downloads folder.
///
/// Android host apps should implement `saveToDownloads` (see example
/// `MainActivity.kt`). If the channel is missing, files fall back to app docs.
const String bridgeDownloadsChannelName = 'bridge_flutter_sdk/downloads';

const Set<String> downloadableExtensions = {
  'pdf',
  'doc',
  'docx',
  'xls',
  'xlsx',
  'csv',
  'zip',
  'ppt',
  'pptx',
};

const Map<String, String> _mimeExtensions = {
  'application/pdf': '.pdf',
  'application/zip': '.zip',
  'application/x-zip-compressed': '.zip',
  'application/msword': '.doc',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document':
      '.docx',
  'application/vnd.ms-excel': '.xls',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': '.xlsx',
  'text/csv': '.csv',
  'application/vnd.ms-powerpoint': '.ppt',
  'application/vnd.openxmlformats-officedocument.presentationml.presentation':
      '.pptx',
};

bool isDownloadableUrl(WebUri? uri) {
  if (uri == null) return false;
  final path = uri.path.toLowerCase();
  if (path.isEmpty) return false;
  // Strip trailing slash; match ".pdf" even with query/hash on the URI.
  final file = path.split('/').last;
  final ext = file.contains('.') ? file.split('.').last : '';
  return downloadableExtensions.contains(ext);
}

bool isDownloadableMime(String? mimeType) {
  if (mimeType == null || mimeType.isEmpty) return false;
  final mime = mimeType.split(';').first.trim().toLowerCase();
  if (_mimeExtensions.containsKey(mime)) return true;
  if (mime == 'application/pdf' || mime.endsWith('/pdf')) return true;
  if (mime.contains('msword') ||
      mime.contains('ms-excel') ||
      mime.contains('ms-powerpoint') ||
      mime.contains('officedocument') ||
      mime.contains('spreadsheet') ||
      mime.contains('presentation')) {
    return true;
  }
  return false;
}

/// True when the URL or MIME is a document type (PDF, office, zip, …).
bool shouldSaveDocument({String? url, String? mimeType}) {
  if (isDownloadableMime(mimeType)) return true;
  if (url == null || url.isEmpty) return false;
  try {
    return isDownloadableUrl(WebUri(url));
  } catch (_) {
    return false;
  }
}

const Set<String> _archiveExtensions = {'zip'};

bool isArchiveUrl(WebUri? uri) {
  if (uri == null) return false;
  final file = uri.path.toLowerCase().split('/').last;
  final ext = file.contains('.') ? file.split('.').last : '';
  return _archiveExtensions.contains(ext);
}

bool isArchiveMime(String? mimeType) {
  if (mimeType == null || mimeType.isEmpty) return false;
  final mime = mimeType.split(';').first.trim().toLowerCase();
  return mime == 'application/zip' ||
      mime == 'application/x-zip-compressed' ||
      mime == 'multipart/x-zip';
}

/// Archives / bulk packages must be saved (e.g. "Download all documents").
/// Individual PDF/doc links should open for viewing instead.
bool shouldForceDownload({
  String? url,
  String? mimeType,
  String? suggestedFileName,
}) {
  if (isArchiveMime(mimeType)) return true;
  final name = suggestedFileName?.trim().toLowerCase() ?? '';
  if (name.endsWith('.zip')) return true;
  if (url == null || url.isEmpty) return false;
  try {
    return isArchiveUrl(WebUri(url));
  } catch (_) {
    return false;
  }
}

String sanitizeFileName(String name) =>
    name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

String ensureFileExtension(String name, String mimeType) {
  final cleaned = sanitizeFileName(name.isEmpty ? 'download' : name);
  if (cleaned.contains('.')) return cleaned;
  final ext = _mimeExtensions[mimeType.split(';').first.trim().toLowerCase()];
  return ext == null ? cleaned : '$cleaned$ext';
}

/// Handles Bridge document downloads (blob ZIP + http(s) PDFs) per the mobile guide.
class DownloadService {
  DownloadService({
    MethodChannel? channel,
    http.Client? client,
  })  : _channel = channel ?? const MethodChannel(bridgeDownloadsChannelName),
        _client = client ?? http.Client();

  final MethodChannel _channel;
  final http.Client _client;

  /// Requests storage / notification permissions required to persist downloads.
  ///
  /// - **Android &lt; 10**: `WRITE_EXTERNAL_STORAGE` via [Permission.storage]
  /// - **Android 13+**: [Permission.notification] (optional progress UX)
  /// - **Android 10+**: MediaStore Downloads needs no storage permission
  /// - **iOS**: app Documents / Files sharing — no runtime permission
  Future<void> ensureDownloadPermissions() async {
    if (kIsWeb) return;

    if (Platform.isAndroid) {
      final notification = await Permission.notification.request();
      debugPrint('BridgeSDK: notification permission → $notification');

      // On API 29+ MediaStore write does not need storage permission.
      // On older devices, public Downloads requires WRITE_EXTERNAL_STORAGE.
      final storage = await Permission.storage.request();
      debugPrint('BridgeSDK: storage permission → $storage');

      if (storage.isPermanentlyDenied) {
        debugPrint(
          'BridgeSDK: storage permanently denied — '
          'MediaStore (API 29+) or app documents fallback will be used',
        );
      }
      return;
    }

    if (Platform.isIOS) {
      // Documents directory + UIFileSharingEnabled — no runtime permission.
      // Ensure the documents folder exists before the first write.
      final docs = await getApplicationDocumentsDirectory();
      if (!await docs.exists()) {
        await docs.create(recursive: true);
      }
      debugPrint('BridgeSDK: iOS downloads folder ready → ${docs.path}');
    }
  }

  Future<void> handleDownloadStart({
    required InAppWebViewController controller,
    required DownloadStartRequest request,
    void Function(String fileName)? onSaved,
    void Function(Object error)? onError,
  }) async {
    try {
      final name = await saveFromWebView(
        controller: controller,
        url: request.url.toString(),
        suggestedName: request.suggestedFilename,
        mimeType: request.mimeType,
      );
      onSaved?.call(name);
    } catch (e, st) {
      debugPrint('BridgeSDK: download failed — $e\n$st');
      onError?.call(e);
    }
  }

  /// Saves blob:/data:/http(s) via the WebView (keeps cookies / auth).
  Future<String> saveFromWebView({
    required InAppWebViewController controller,
    required String url,
    String? suggestedName,
    String? mimeType,
  }) async {
    await ensureDownloadPermissions();

    final lower = url.trim().toLowerCase();
    if (lower.startsWith('blob:') || lower.startsWith('data:')) {
      return _saveBlobOrData(
        controller,
        url,
        suggestedName: suggestedName,
        mimeType: mimeType,
      );
    }

    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      try {
        return await _saveHttpViaWebView(
          controller,
          url,
          suggestedName: suggestedName,
          mimeType: mimeType,
        );
      } catch (e) {
        debugPrint('BridgeSDK: in-page fetch failed ($e) — HTTP fallback');
        return downloadHttpUri(
          WebUri(url),
          suggestedName: suggestedName,
        );
      }
    }

    throw StateError('Unsupported download URL scheme: $url');
  }

  Future<String> downloadHttpUri(WebUri uri, {String? suggestedName}) async {
    await ensureDownloadPermissions();

    final name = ensureFileExtension(
      suggestedName ?? _guessFileName(uri.toString()) ?? 'download',
      'application/octet-stream',
    );

    final cookies = await CookieManager.instance().getCookies(url: uri);
    final cookieHeader = cookies.isEmpty
        ? null
        : cookies.map((c) => '${c.name}=${c.value}').join('; ');

    final response = await _client.get(
      Uri.parse(uri.toString()),
      headers: {
        if (cookieHeader != null) 'Cookie': cookieHeader,
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('HTTP ${response.statusCode} downloading $name');
    }
    final mime = response.headers['content-type']?.split(';').first.trim() ??
        'application/octet-stream';
    final finalName = ensureFileExtension(name, mime);
    await _persistBytes(response.bodyBytes, finalName, mime);
    return finalName;
  }

  Future<String> _saveHttpViaWebView(
    InAppWebViewController controller,
    String url, {
    String? suggestedName,
    String? mimeType,
  }) async {
    final result = await controller.callAsyncJavaScript(
      functionBody: '''
const res = await fetch(url, { credentials: 'include', redirect: 'follow' });
if (!res.ok) throw new Error('HTTP ' + res.status);
const blob = await res.blob();
const data = await new Promise((resolve, reject) => {
  const reader = new FileReader();
  reader.onloadend = () => resolve(reader.result);
  reader.onerror = () => reject(new Error('could not read the file'));
  reader.readAsDataURL(blob);
});
let name = suggested || '';
const cd = res.headers.get('content-disposition') || '';
const star = /filename\\*=(?:UTF-8''|utf-8'')([^;]+)/i.exec(cd);
const plain = /filename="?([^";]+)"?/i.exec(cd);
if (star && star[1]) name = decodeURIComponent(star[1].trim());
else if (plain && plain[1]) name = plain[1].trim();
return { data: data, name: name, mime: blob.type || fallbackMime || '' };
''',
      arguments: {
        'url': url,
        'suggested': suggestedName ?? '',
        'fallbackMime': mimeType ?? '',
      },
    );

    final value = result?.value;
    if (value is! Map || value['data'] is! String) {
      throw result?.error ?? StateError('could not read the file');
    }

    final dataUrl = value['data'] as String;
    final pageName = (value['name'] as String?)?.trim() ?? '';
    final mime = (value['mime'] as String?)?.trim().isNotEmpty == true
        ? (value['mime'] as String).trim()
        : (RegExp(r'^data:([^;,]+)').firstMatch(dataUrl)?.group(1) ??
            mimeType ??
            'application/octet-stream');
    final name = ensureFileExtension(
      pageName.isNotEmpty
          ? pageName
          : (suggestedName ?? _guessFileName(url) ?? 'download'),
      mime,
    );
    final comma = dataUrl.indexOf(',');
    final b64 = comma >= 0 ? dataUrl.substring(comma + 1) : dataUrl;
    await _persistBytes(base64Decode(b64), name, mime);
    return name;
  }

  Future<String> _saveBlobOrData(
    InAppWebViewController controller,
    String url, {
    String? suggestedName,
    String? mimeType,
  }) async {
    final result = await controller.callAsyncJavaScript(
      functionBody: '''
let blob = (window.__blobs || {})[url];
if (!blob) blob = await (await fetch(url)).blob();
const data = await new Promise((resolve, reject) => {
  const reader = new FileReader();
  reader.onloadend = () => resolve(reader.result);
  reader.onerror = () => reject(new Error('could not read the file'));
  reader.readAsDataURL(blob);
});
return {
  data: data,
  name: (window.__blobNames || {})[url] || suggested || '',
  mime: blob.type || fallbackMime || ''
};
''',
      arguments: {
        'url': url,
        'suggested': suggestedName ?? '',
        'fallbackMime': mimeType ?? '',
      },
    );

    final value = result?.value;
    if (value is! Map || value['data'] is! String) {
      throw result?.error ?? StateError('could not read the file');
    }

    final dataUrl = value['data'] as String;
    final pageName = (value['name'] as String?)?.trim() ?? '';
    final mime = (value['mime'] as String?)?.trim().isNotEmpty == true
        ? (value['mime'] as String).trim()
        : (RegExp(r'^data:([^;,]+)').firstMatch(dataUrl)?.group(1) ??
            mimeType ??
            'application/octet-stream');
    final name = ensureFileExtension(
      pageName.isNotEmpty ? pageName : (suggestedName ?? 'download'),
      mime,
    );
    final comma = dataUrl.indexOf(',');
    final b64 = comma >= 0 ? dataUrl.substring(comma + 1) : dataUrl;
    await _persistBytes(base64Decode(b64), name, mime);
    return name;
  }

  Future<void> _persistBytes(
    List<int> bytes,
    String fileName,
    String mimeType,
  ) async {
    try {
      await _channel.invokeMethod<void>('saveToDownloads', {
        'bytes': Uint8List.fromList(bytes),
        'fileName': fileName,
        'mimeType': mimeType,
      });
      debugPrint('BridgeSDK: saved via native channel → $fileName');
      return;
    } on MissingPluginException {
      debugPrint(
        'BridgeSDK: $bridgeDownloadsChannelName not implemented — '
        'saving to app documents',
      );
    } catch (e) {
      debugPrint('BridgeSDK: native save failed ($e) — falling back to docs');
    }

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    debugPrint('BridgeSDK: saved to ${file.path}');
  }

  String? _guessFileName(String url) {
    try {
      final path = Uri.parse(url).path;
      if (path.isEmpty) return null;
      final seg = path.split('/').last;
      return seg.isEmpty ? null : seg;
    } catch (_) {
      return null;
    }
  }

  void close() => _client.close();
}
