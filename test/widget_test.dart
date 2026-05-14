// Basic Flutter widget test for Chrono Lite

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chrono_lite/main.dart';

void main() {
  // Ensure binding is initialized before setting mock values
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Mock SharedPreferences to avoid MissingPluginException
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('App launches smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ChronoLiteApp());

    // Allow async initialization to complete
    await tester.pumpAndSettle();

    // Verify the app launches (basic smoke test)
    expect(find.text('Tap to connect'), findsOneWidget);
  });
}
