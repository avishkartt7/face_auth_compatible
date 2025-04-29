// lib/onboarding/onboarding_screen.dart

import 'package:flutter/material.dart';
import 'package:face_auth_compatible/constants/theme.dart';
import 'package:face_auth_compatible/pin_entry/pin_entry_view.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({Key? key}) : super(key: key);

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> with SingleTickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  final int _numPages = 3;

  // Animation controller for page transitions and elements
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  final List<Map<String, String>> _pages = [
    {
      'title': 'Welcome to Phoenician',
      'subtitle': 'Technical Services',
      'description': 'Secure workplace authentication powered by advanced facial recognition technology',
      'image': 'assets/images/onboarding_welcome.svg',
    },
    {
      'title': 'Positive Team',
      'subtitle': 'Environment',
      'description': 'Join our positive and collaborative workplace culture',
      'image': 'assets/images/onboarding_positive.svg',
    },
    {
      'title': 'Teamwork Makes',
      'subtitle': 'the Dream Work',
      'description': 'Together we achieve more with secure and efficient authentication',
      'image': 'assets/images/onboarding_teamwork.svg',
    },
  ];

  @override
  void initState() {
    super.initState();

    // Initialize animations
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    // Start animation
    _animationController.forward();

    // Listen for page changes to restart animation
    _pageController.addListener(() {
      if (_pageController.page!.round() != _currentPage) {
        setState(() {
          _currentPage = _pageController.page!.round();
        });
        _animationController.reset();
        _animationController.forward();
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _markOnboardingComplete() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboardingComplete', true);
  }

  void _navigateToPinEntry() {
    _markOnboardingComplete();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const PinEntryView()),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Get screen size for responsive design
    final Size screenSize = MediaQuery.of(context).size;

    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          // Use a more modern gradient with multiple colors and stops
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF7C4DFF).withOpacity(0.8), // Deep purple
              const Color(0xFF5E72E4),                  // Indigo
              const Color(0xFF4FB0FF),                  // Light blue
            ],
            stops: const [0.1, 0.5, 0.9],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              // Decorative elements - circles for modern design
              Positioned(
                top: -screenSize.height * 0.08,
                left: -screenSize.width * 0.08,
                child: Container(
                  width: screenSize.width * 0.4,
                  height: screenSize.width * 0.4,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.12),
                  ),
                ),
              ),
              Positioned(
                bottom: screenSize.height * 0.15,
                right: -screenSize.width * 0.1,
                child: Container(
                  width: screenSize.width * 0.3,
                  height: screenSize.width * 0.3,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.08),
                  ),
                ),
              ),

              // Skip button
              Positioned(
                top: 16,
                right: 16,
                child: _currentPage < _numPages - 1
                    ? TextButton(
                  onPressed: _navigateToPinEntry,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(color: Colors.white.withOpacity(0.3), width: 1),
                    ),
                    backgroundColor: Colors.white.withOpacity(0.2),
                  ),
                  child: const Text(
                    'Skip',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                )
                    : const SizedBox(),
              ),

              // Main content
              PageView.builder(
                controller: _pageController,
                onPageChanged: (int page) {
                  setState(() {
                    _currentPage = page;
                  });
                },
                itemCount: _numPages,
                itemBuilder: (context, index) {
                  return _buildPageContent(index, screenSize);
                },
              ),

              // Bottom navigation dots
              Positioned(
                bottom: 30.0,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    _numPages,
                        (index) => _buildDotIndicator(index),
                  ),
                ),
              ),

              // Get Started button for last page only
              if (_currentPage == _numPages - 1)
                Positioned(
                  bottom: 80.0,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: GestureDetector(
                      onTap: _navigateToPinEntry,
                      child: Container(
                        width: 200,
                        height: 50,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(25),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Text(
                            "Get Started",
                            style: TextStyle(
                              color: Color(0xFF5E72E4),
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPageContent(int index, Size screenSize) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 40),

            // Image container with stylish border
            Container(
              margin: EdgeInsets.symmetric(horizontal: screenSize.width * 0.1),
              height: screenSize.height * 0.35,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withOpacity(0.3),
                  width: 1.5,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Center(
                    child: Container(
                      width: screenSize.width * 0.6,
                      height: screenSize.height * 0.3,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.black.withOpacity(0.2),
                          width: 1,
                        ),
                      ),
                      child: SvgPicture.asset(
                        _pages[index]['image']!,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            SizedBox(height: screenSize.height * 0.05),

            // Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: Text(
                _pages[index]['title']!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),

            // Subtitle
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: Text(
                _pages[index]['subtitle']!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),

            SizedBox(height: screenSize.height * 0.03),

            // Description with a stylish container
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: Text(
                  _pages[index]['description']!,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 16,
                    height: 1.5,
                    letterSpacing: 0.3,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDotIndicator(int index) {
    bool isActive = _currentPage == index;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.symmetric(horizontal: 5),
      height: 8,
      width: isActive ? 24 : 8,
      decoration: BoxDecoration(
        color: isActive ? Colors.white : Colors.white.withOpacity(0.3),
        borderRadius: BorderRadius.circular(4),
        boxShadow: isActive
            ? [
          BoxShadow(
            color: Colors.white.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 1),
          ),
        ]
            : null,
      ),
    );
  }
}