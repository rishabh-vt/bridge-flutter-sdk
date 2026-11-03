import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../types/types.dart';

class DocumentDownloadResult {
  const DocumentDownloadResult({
    required this.total,
    required this.succeeded,
    required this.failed,
  });

  final int total;
  final int succeeded;
  final int failed;

  Map<String, dynamic> toJson() => {
        'total': total,
        'succeeded': succeeded,
        'failed': failed,
      };
}

String _sanitizeFileName(String name) {
  final cleaned = name.replaceAll(RegExp(r'[/\\?%*:|"<>]'), '_').trim();
  return cleaned.isEmpty ? 'document' : cleaned;
}

class DocumentDownloadService {
  const DocumentDownloadService();

  Future<bool> downloadDocument(
    String url,
    String label,
    Logger logger,
  ) async {
    final fileName = '${_sanitizeFileName(label)}.pdf';
    try {
      final bytes = await _fetchBytes(url);
      if (Platform.isAndroid) {
        await _downloadOnAndroid(bytes, fileName);
      } else {
        await _downloadOnIos(bytes, fileName);
      }
      return true;
    } catch (error) {
      logger.warn('Failed to download document', [label, error]);
      return false;
    }
  }

  Future<Uint8List> _fetchBytes(String url) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'HTTP ${response.statusCode} fetching $url',
        uri: Uri.parse(url),
      );
    }
    return response.bodyBytes;
  }

  Future<void> _downloadOnAndroid(Uint8List bytes, String fileName) async {
    // Prefer the public Downloads directory when available (MediaStore-visible
    // path on modern Android via getDownloadsDirectory).
    final downloads = await getDownloadsDirectory();
    final dir = downloads ?? await getExternalStorageDirectory();
    if (dir == null) {
      throw StateError('No writable download directory on Android');
    }
    final file = File(p.join(dir.path, fileName));
    await file.writeAsBytes(bytes, flush: true);
  }

  Future<void> _downloadOnIos(Uint8List bytes, String fileName) async {
    // App Documents directory — visible in Files app when the host sets
    // UIFileSharingEnabled + LSSupportsOpeningDocumentsInPlace.
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, fileName));
    await file.writeAsBytes(bytes, flush: true);
  }
}

const documentDownloadService = DocumentDownloadService();
