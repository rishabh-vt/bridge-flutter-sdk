import 'package:bridge_flutter_sdk/bridge_flutter_sdk.dart';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BridgeSdkExampleApp());
}

class BridgeSdkExampleApp extends StatelessWidget {
  const BridgeSdkExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'bridge-flutter-sdk',
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: BridgeSdk(
          firmId: '397',
          branchIdRi: '3136',
          branchIdNri: '3532',
          authFormSlug: 'nse-ifsc-branch',
          appName: 'ViewTrade Test',
          helpEmail: 'support@viewtrade.in',
          helpUrl: 'https://www.viewtrade.com/about-us/',
          tncUrl: 'https://assets.viewtrade.in/assets/policies/tnc.html',
          ppUrl:
              'https://assets.viewtrade.in/assets/policies/privacyPolicy.html',
          disclaimerUrl:
              'https://assets.viewtrade.in/assets/policies/disclaimer.html',
          aboutUrl: 'https://www.viewtrade.com/about-us/',
          environment: Environment.uat,
          theme: const ThemeConfig(
            primaryColor: '#3C2D83',
            secondaryColor: '#DDF0F2',
          ),
          // Print WebView fetch/XHR + bridge messages to the Flutter console.
          enableApiLogs: true,
          onError: (err) {
            debugPrint('[SDK] ${err.code.wireName} ${err.message}');
          },
          onReady: () => debugPrint('[SDK] ready'),
          onAuthChange: (state) {
            debugPrint('[SDK] auth authenticated=${state.authenticated}');
          },
          onCheckoutEvent: (event) {
            debugPrint('[SDK] checkout ${event.runtimeType}');
          },
        ),
      ),
    );
  }
}
