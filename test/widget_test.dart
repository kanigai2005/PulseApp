import 'package:flutter_test/flutter_test.dart';
import 'package:autonap/main.dart';

void main() {
  testWidgets('AutoNap app renders smoke test', (WidgetTester tester) async {
    // Build AutoNapApp and trigger a frame.
    await tester.pumpWidget(const AutoNapApp());
    await tester.pumpAndSettle();

    // Verify AutoNap title is displayed
    expect(find.text('AutoNap'), findsOneWidget);
  });
}
