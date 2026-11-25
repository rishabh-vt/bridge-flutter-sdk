import 'dart:convert';

import 'package:http/http.dart' as http;

import '../types/errors.dart';
import '../types/types.dart';

/// Payload sent to `POST /launch` (JSON — same fields as the form POST guide).
class LaunchRequest {
  const LaunchRequest({
    required this.token,
    required this.refreshToken,
    required this.clientName,
    required this.returnUrl,
    required this.accessTokenExpiresAt,
    required this.refreshTokenExpiresAt,
  });

  final String token;
  final String refreshToken;
  final String clientName;
  final String returnUrl;
  final String accessTokenExpiresAt;
  final String refreshTokenExpiresAt;

  Map<String, dynamic> toJson() => {
        'token': token,
        'clientName': clientName,
        'refreshToken': refreshToken,
        'returnUrl': returnUrl,
        'accessTokenExpiresAt': accessTokenExpiresAt,
        'refreshTokenExpiresAt': refreshTokenExpiresAt,
      };
}

/// Calls the Bridge backend `/launch` endpoint and returns `launchUrl`.
class LaunchService {
  LaunchService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// POSTs [request] to the `/launch` URL for [environment].
  Future<String> fetchLaunchUrl({
    required Environment environment,
    required LaunchRequest request,
  }) async {
    final uri = Uri.parse(environment.launchUrl);

    late final http.Response response;
    try {
      response = await _client.post(
        uri,
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(request.toJson()),
      );
    } catch (error) {
      throw SdkError(
        SdkErrorCode.launchFailed,
        'BridgeSDK: launch request failed — $error',
        error,
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SdkError(
        SdkErrorCode.launchFailed,
        'BridgeSDK: launch failed with HTTP ${response.statusCode}',
        response.body,
      );
    }

    late final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (error) {
      throw SdkError(
        SdkErrorCode.launchFailed,
        'BridgeSDK: launch response was not valid JSON',
        error,
      );
    }

    if (decoded is! Map<String, dynamic>) {
      throw SdkError(
        SdkErrorCode.launchFailed,
        'BridgeSDK: launch response must be a JSON object',
        decoded,
      );
    }

    final launchUrl = decoded['launchUrl'];
    if (launchUrl is! String || launchUrl.isEmpty) {
      throw SdkError(
        SdkErrorCode.launchFailed,
        'BridgeSDK: launch response missing non-empty "launchUrl"',
        decoded,
      );
    }

    return launchUrl;
  }

  void close() => _client.close();
}
