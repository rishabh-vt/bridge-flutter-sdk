// Product-facing names (UAT / PROD), not lowerCamelCase.
// ignore_for_file: constant_identifier_names

/// Single SDK prop that selects UAT vs PROD launch backend.
enum Environment {
  /// https://bridge-backend-staging.viewtrade.in/launch
  UAT,

  /// https://sdk-backend.viewtrade.in/launch
  PROD;

  /// Full `/launch` endpoint for this environment.
  String get launchUrl => switch (this) {
        Environment.UAT =>
          'https://bridge-backend-staging.viewtrade.in/launch',
        Environment.PROD => 'https://sdk-backend.viewtrade.in/launch',
      };
}

/// Fired when Bridge navigates to the host [returnUrl] (custom scheme).
class BridgeReturn {
  const BridgeReturn({
    required this.url,
    this.reason,
  });

  /// Full return URL including query (e.g. `myapp://sdk-return?reason=logout`).
  final String url;

  /// Query `reason` when present: `logout`, `email_verified`, `error`, …
  final String? reason;
}
