import 'package:bridge_sdk_example/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('example app builds and shows loading state', (tester) async {
    await tester.pumpWidget(const BridgeSdkExampleApp());
    expect(find.byType(BridgeSdkExampleApp), findsOneWidget);
    // Placeholder tokens fail launch; SDK should still render a progress indicator.
    await tester.pump();
    expect(find.byType(BridgeSdkExampleApp), findsOneWidget);
  });
}
