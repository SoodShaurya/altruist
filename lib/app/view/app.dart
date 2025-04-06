import 'package:altruist/features/home/view/home_page.dart';
import 'package:altruist/features/onboarding/view/onboarding_screen.dart'; // Import onboarding screen
import 'package:altruist/l10n/l10n.dart';
import 'package:flutter/material.dart';
// Removed Moon Design import
import 'package:shared_preferences/shared_preferences.dart'; // Import shared_preferences

class App extends StatefulWidget { // Changed to StatefulWidget
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> { // Added State class
  bool _isLoading = true;
  bool _showOnboarding = true;

  @override
  void initState() {
    super.initState();
    _checkOnboardingStatus();
  }

  Future<void> _checkOnboardingStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final onboardingComplete = prefs.getBool('onboarding_complete') ?? false;
    setState(() {
      _showOnboarding = !onboardingComplete;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Show loading indicator while checking prefs
    if (_isLoading) {
      return const MaterialApp(
        home: Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    // Removed MoonProvider wrapper
    return MaterialApp(
      theme: ThemeData(
        appBarTheme: AppBarTheme(
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        ),
        useMaterial3: true,
      ),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
        // Conditionally set home based on onboarding status
        home: _showOnboarding ? const OnboardingScreen() : const HomePage(),
    );
  }
}
