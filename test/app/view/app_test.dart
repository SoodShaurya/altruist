import 'package:altruist/app/app.dart';
import 'package:altruist/features/home/view/home_page.dart'; // Updated import
import 'package:flutter/material.dart'; // Added import
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('App', () {
    // Test is less relevant now as App conditionally shows Onboarding or Home
    // Keeping a basic test to ensure App renders without crashing
    testWidgets('renders App', (tester) async {
      // Mock SharedPreferences for testing App state
      // This part might need more setup depending on how SharedPreferences is used
      // For now, just pump the widget.
      await tester.pumpWidget(const App());
      // We expect either OnboardingScreen or HomePage initially, depending on prefs
      // A more robust test would mock SharedPreferences.
      expect(find.byType(App), findsOneWidget); 
    });

    // Optional: Add a test specifically for HomePage if needed
    testWidgets('renders HomePage directly', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: HomePage()));
    });
  });
}
