import 'package:altruist/features/home/view/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:moon_design/moon_design.dart';
import 'package:animate_do/animate_do.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  static const String routeName = '/onboarding'; // Optional: Define route name

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_complete', true);
    if (mounted) {
      // Navigate to the main app screen (CounterPage in this case)
      // Navigate to the new HomePage
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomePage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarBrightness: Brightness.dark, // For iOS
      statusBarIconBrightness: Brightness.dark, // For Android
    ));

    return Scaffold(
      backgroundColor: Colors.white, // AppColors.kBackground -> Colors.white
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20), // Reduced top padding
            Expanded(
              flex: 3, // Keep flex for PageView dominance
              child: PageView.builder(
                itemCount: onboardingList.length,
                controller: _pageController,
                onPageChanged: (value) {
                  setState(() {
                    _currentIndex = value;
                  });
                },
                itemBuilder: (context, index) {
                  return OnboardingCard(
                    onBoarding: onboardingList[index],
                  );
                },
              ),
            ),
            // Removing color/size parameters to check defaults
            MoonDotIndicator(
              dotCount: onboardingList.length,
              selectedDot: _currentIndex,
              // color: Colors.grey.withOpacity(0.5), // Removed
              // activeColor: Colors.blue, // Removed
              // size: 8, // Removed
              // activeSize: 8, // Removed
              gap: 6, // Keeping gap as it might be valid
            ),
            const SizedBox(height: 30), // Further reduced height between indicator and button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40.0), // Increased horizontal padding for button
              child: Row( // Row might be unnecessary now, but keeping for structure
                children: [
                  Expanded(
                    child: MoonOutlinedButton(
                      buttonSize: MoonButtonSize.lg, // Adjusted size for better fit
                      borderColor: Colors.blue, // AppColors.kPrimary -> Colors.blue
                      label: Text(
                        _currentIndex == (onboardingList.length - 1)
                            ? 'Get Started'
                            : 'Next',
                        style: const TextStyle(color: Colors.blue), // AppColors.kPrimary -> Colors.blue
                      ),
                      onTap: () {
                        if (_currentIndex == (onboardingList.length - 1)) {
                          _completeOnboarding();
                        } else {
                          _pageController.nextPage(
                            duration: const Duration(milliseconds: 500),
                            curve: Curves.ease,
                          );
                        }
                      },
                    ),
                  ),
                  // Removed SizedBox separator and the entire progress indicator section
                ],
              ),
            ),
            const SizedBox(height: 40), // Increased bottom padding slightly
          ],
        ),
      ),
    );
  }
}

class OnboardingData {
  final String title1;
  final String title2;
  final String description;
  // Removed image field as we are using placeholders

  OnboardingData({
    required this.title1,
    required this.title2,
    required this.description,
  });
}

// Updated list without image paths
List<OnboardingData> onboardingList = [
  OnboardingData(
    title1: 'Diverse ',
    title2: 'and fresh food',
    description:
        'With an extensive menu prepared by talented chefs, fresh quality food.',
  ),
  OnboardingData(
    title1: 'Easy to ',
    title2: 'change dish ingredients',
    description:
        'You are a foodie, you can add or subtract ingredients in the dish.',
  ),
  OnboardingData(
    title1: 'Delivery ',
    title2: 'Is given on time',
    description:
        'With an extensive menu prepared by talented chefs, fresh quality food.',
  )
];

class OnboardingCard extends StatelessWidget {
  final OnboardingData onBoarding;

  const OnboardingCard({
    required this.onBoarding,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return FadeInDown(
      duration: const Duration(milliseconds: 1400),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 30),
        child: Column(
          children: [
            // Placeholder for the image
            Expanded(
              child: Center(
                child: Container(
                  width: 250, // Example size
                  height: 250, // Example size
                  color: Colors.grey[300], // Placeholder color
                  child: const Center(child: Text('Image Placeholder')),
                ),
              ),
            ),
            const SizedBox(height: 20), // Spacing after placeholder
            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                text: onBoarding.title1,
                style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w400,
                  color: Colors.black, // AppColors.kSecondary -> Colors.black
                ),
                children: [
                  TextSpan(
                    text: onBoarding.title2,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 36,
                      color: Colors.black, // Ensure title2 also uses the standard color
                    ),
                  )
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              onBoarding.description,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black54, // AppColors.kSecondary -> Colors.black54 (slightly lighter)
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
