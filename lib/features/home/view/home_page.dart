import 'dart:math';
import 'dart:ui'; // Added for Offset, Size, etc.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:sliding_up_panel/sliding_up_panel.dart';

// --- Copied from visualiser_page.dart ---
// Represents a single particle in the simulation
class Particle {
  Offset position; // Current position
  Offset velocity; // Current velocity
  final Offset initialRingPosition; // Where it starts statically (relative to center)
  final Offset finalOrbitTargetPosition; // The center of its final orbit (relative to center)
  Offset currentTargetPosition; // Where it's currently trying to go (relative to center)
  Color color; // Made mutable
  final double particleSize; // Pre-calculated size (based on finalOrbitTargetPosition)

  Particle({
    required this.position,
    required this.initialRingPosition,
    required this.finalOrbitTargetPosition,
    required this.currentTargetPosition,
    required this.particleSize,
    this.velocity = Offset.zero,
    this.color = Colors.white,
  });
}
// --- End Copied Section ---

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

// Added TickerProviderStateMixin
class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  // Original HomePage state
  bool _isCameraEnabled = true; // State for the camera toggle
  final PanelController _panelController =
      PanelController(); // Controller for the panel

  // --- Copied state from _VisualiserPageState ---
  late AnimationController _controller;
  final List<Particle> _particles = [];
  final int _numParticles = 700; // Increased particle count
  final double _sphereRadius = 150.0; // Radius for particle home positions
  Offset? _touchPosition; // Current touch position
  Offset? _center; // Store the center calculated by LayoutBuilder

  // Physics parameters
  final double _attractionStrength = 0.02;
  final double _repulsionStrength = 150.0; // Increased repulsion
  final double _repulsionRadius = 80.0; // Radius around touch for repulsion
  final double _damping = 0.9; // Slows down particles (Reduced for less bounce)
  double _rotationAngle = 0.0; // Current rotation angle for targets
  final double _rotationSpeed = 0.005; // Speed of target rotation
  final double _jitterStrength = 0.15; // How much random jitter to add
  final Random _random = Random(); // Random number generator for jitter
  bool _isAnimating = false; // Start in static state
  final double _initialRingRadiusFactor = 0.8; // How far out the initial ring is
  final double _activationTapRadius = 50.0; // Radius around center to activate animation (Increased)

  // Particle size constants
  static const double _maxSize = 1.1;
  static const double _minSize = 0.5;
  // --- End Copied State ---

  // Merged initState
  @override
  void initState() {
    super.initState();
    _initializeParticles(); // From visualiser
    _controller = AnimationController( // From visualiser
      vsync: this,
      duration: const Duration(seconds: 1), // Duration doesn't really matter here
    )..addListener(_updateParticles);
    _controller.repeat(); // Run the animation loop continuously
  }

  // Merged dispose
  @override
  void dispose() {
    _controller.dispose(); // From visualiser
    super.dispose();
  }

  // --- Copied methods from _VisualiserPageState ---
  void _initializeParticles() {
    // This method now only sets up the relative positions and other particle properties.
    // The absolute positioning based on the actual center happens in the LayoutBuilder's
    // post-frame callback after the first build.

    final random = Random();
    final double ringRadius = _sphereRadius * _initialRingRadiusFactor;

    _particles.clear(); // Clear existing particles if re-initializing

    for (int i = 0; i < _numParticles; i++) {
      // 1. Calculate initial position on the static ring (relative to 0,0)
      final double initialAngle = (i / _numParticles) * 2 * pi;
      final double initialX = ringRadius * cos(initialAngle);
      final double initialY = ringRadius * sin(initialAngle);
      final initialRingPos = Offset(initialX, initialY);

      // 2. Generate random final orbit target position within the sphere (relative to 0,0)
      double u = random.nextDouble();
      double v = random.nextDouble();
      double theta = 2 * pi * u;
      double phi = acos(2 * v - 1);
      double r = _sphereRadius * pow(random.nextDouble(), 1 / 3);
      double finalX = r * sin(phi) * cos(theta);
      double finalY = r * sin(phi) * sin(theta);
      final finalOrbitPos = Offset(finalX, finalY);

      // 3. Pre-calculate particle size based on its *final* orbit distance
      final double distFromFinalOrigin = finalOrbitPos.distance;
      final double normalizedDist = (distFromFinalOrigin / _sphereRadius).clamp(0.0, 1.0);
      final double particleSize = _maxSize - (_maxSize - _minSize) * normalizedDist;

      _particles.add(
        Particle(
          // Position starts relative, will be made absolute later
          position: initialRingPos,
          initialRingPosition: initialRingPos,
          finalOrbitTargetPosition: finalOrbitPos,
          currentTargetPosition: initialRingPos, // Initially target the ring
          particleSize: particleSize,
          velocity: Offset.zero,
          color: Colors.white.withOpacity(0.7 + random.nextDouble() * 0.3),
        ),
      );
    }
  }

  void _updateParticles() {
    // Use the stored center if available
    final Offset? currentCenter = _center;
    // Only update if animating, mounted, and center is known
    if (!mounted || !_isAnimating || currentCenter == null) return;

    // Update rotation angle
    _rotationAngle += _rotationSpeed;

    for (var particle in _particles) {
      // Rotate the *final* orbit target position
      final double cosA = cos(_rotationAngle);
      final double sinA = sin(_rotationAngle);
      final double rotatedX = particle.finalOrbitTargetPosition.dx * cosA - particle.finalOrbitTargetPosition.dy * sinA;
      final double rotatedY = particle.finalOrbitTargetPosition.dx * sinA + particle.finalOrbitTargetPosition.dy * cosA;
      // Update the current target to be the rotated final position
      particle.currentTargetPosition = Offset(rotatedX, rotatedY);

      // Calculate vector from current position to the *current target* position (relative to center)
      final Offset targetVector =
          (currentCenter + particle.currentTargetPosition) - particle.position;
      // Attraction force towards the current target
      Offset attractionForce = targetVector * _attractionStrength;

      Offset repulsionForce = Offset.zero;
      if (_touchPosition != null) {
        final Offset touchVector = particle.position - _touchPosition!;
        final double distance = touchVector.distance;

        if (distance < _repulsionRadius && distance > 0) {
          // Force is stronger closer to the touch point, inversely proportional to distance
          final double strength =
              _repulsionStrength * (1.0 - distance / _repulsionRadius);
          repulsionForce =
              touchVector.scale(strength / distance, strength / distance);
        }
      }

      // Update velocity
      particle.velocity =
          (particle.velocity + attractionForce + repulsionForce) * _damping;

      // Update position based on velocity
      particle.position += particle.velocity;

      // Add random jitter
      final double jitterX = (_random.nextDouble() - 0.5) * 2 * _jitterStrength;
      final double jitterY = (_random.nextDouble() - 0.5) * 2 * _jitterStrength;
      particle.position += Offset(jitterX, jitterY);
    }

    // Trigger repaint to ensure CustomPaint updates even without touch interaction
    setState(() {});
  }
  // --- End Copied Methods ---


  @override
  Widget build(BuildContext context) {
    // Define colors or use Theme
    const Color backgroundColor = Color(0xFF1E1E1E); // Dark background
    const Color panelColor = Color(0xFF2A2A2A); // Slightly lighter panel
    const Color accentColor = Colors.white;
    // const Color inactiveColor = Colors.grey; // Defined in _buildCollapsedPanel

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent, // Make AppBar transparent
        elevation: 0, // Remove shadow
        leading: IconButton(
          icon: const Icon(Icons.menu, color: accentColor),
          onPressed: () {
            // TODO: Implement drawer or menu action
          },
        ),
        title: const Text(
          'Altruist',
          style: TextStyle(color: accentColor, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline, color: accentColor),
            onPressed: () {
              // TODO: Implement profile action
            },
          ),
        ],
      ),
      body: SlidingUpPanel(
        controller: _panelController,
        minHeight: 100, // Increased height of the collapsed panel
        maxHeight: MediaQuery.of(context).size.height *
            0.5, // Panel expands to half screen
        parallaxEnabled: true,
        parallaxOffset: .5,
        color: panelColor, // Background color of the panel
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24.0),
          topRight: Radius.circular(24.0),
        ),
        // Content visible when the panel is collapsed (the bottom bar)
        collapsed: _buildCollapsedPanel(),
        // Content visible when the panel is expanded
        panel: _buildExpandedPanel(),
        // Content behind the sliding panel - NOW THE VISUALISER
        body: _buildBodyContent(),
      ),
    );
  }

  Widget _buildCollapsedPanel() {
    const Color accentColor = Colors.white;
    const Color inactiveColor = Colors.grey;

    // GestureDetector to handle tap for opening the panel
    return GestureDetector(
      onTap: () {
        if (_panelController.isPanelClosed) {
          _panelController.open();
        }
      },
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF2A2A2A), // Match panel color explicitly if needed
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24.0),
            topRight: Radius.circular(24.0),
          ),
        ),
        // Use Column to align content to the top
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start, // Align children to the top
          children: [
            Padding( // Add padding around the Row
              padding: const EdgeInsets.only(left: 25.0, right: 25.0, top: 20.0), // Adjust top padding as needed
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Left: Logo
                  SvgPicture.asset(
                    'assets/icons/logo.svg',
                    height: 40, // Adjust size as needed
                    colorFilter:
                        const ColorFilter.mode(accentColor, BlendMode.srcIn),
                  ),
                  // Center: Settings text and icon
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center, // Center within its own space
                    children: [
                      const Icon(Icons.keyboard_arrow_up,
                          color: inactiveColor, size: 20),
                      const SizedBox(height: 2),
                      const Text(
                        'settings',
                        style: TextStyle(color: inactiveColor, fontSize: 12),
                      ),
                    ],
                  ),
                  // Right: Camera Toggle Button
                  SizedBox(
                     height: 40, // Match logo height
                     width: 40,  // Ensure circular aspect ratio
                     child: OutlinedButton(
                       onPressed: () {
                         setState(() {
                           _isCameraEnabled = !_isCameraEnabled;
                         });
                       },
                       style: OutlinedButton.styleFrom(
                         shape: const CircleBorder(),
                         padding: EdgeInsets.zero, // Remove default padding
                         side: BorderSide(color: inactiveColor), // Outline color
                         foregroundColor: accentColor, // Icon color for ripple effect
                       ),
                       child: Icon(
                         _isCameraEnabled ? Icons.videocam_outlined : Icons.videocam_off_outlined,
                         color: accentColor,
                         size: 23, // Adjust icon size as needed
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedPanel() {
    // Placeholder content for the expanded panel
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF2A2A2A), // Match panel color explicitly if needed
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24.0),
          topRight: Radius.circular(24.0),
        ),
      ),
      child: const Center(
        child: Text(
          "Expanded Panel Content",
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
      ),
    );
  }

  // --- Updated _buildBodyContent with Visualiser ---
  Widget _buildBodyContent() {
    // Content behind the panel - Now the Visualiser
    return LayoutBuilder(
      builder: (context, constraints) {
        final Size size = constraints.biggest; // Get the size from LayoutBuilder
        final Offset center = Offset(size.width / 2, size.height / 2);

        // Update the center state variable after the first frame and if it changes
        // This ensures _updateParticles and gesture handlers have the correct center.
        WidgetsBinding.instance.addPostFrameCallback((_) {
           if (mounted && (_center == null || (_center! - center).distance > 1.0)) {
             // Check if particles need initial absolute positioning
             final bool needsInitialPositioning = _particles.isNotEmpty &&
                 _particles[0].position == _particles[0].initialRingPosition;

             setState(() {
               _center = center;
               // Set initial absolute positions if needed
               if (needsInitialPositioning) {
                  for (var p in _particles) {
                    p.position = center + p.initialRingPosition;
                  }
               }
             });
           }
        });

        return GestureDetector(
           // Activate animation on tap near center if not already animating
           onTapDown: (details) {
             if (!_isAnimating && _center != null) { // Check _center is not null
               final tapPos = details.localPosition;
               final distanceToCenter = (tapPos - _center!).distance; // Use stored _center
               if (distanceToCenter < _activationTapRadius) {
                 setState(() {
                   _isAnimating = true;
                   // Trigger the transition: tell particles to move to their final orbit
                   for (var p in _particles) {
                     p.currentTargetPosition = p.finalOrbitTargetPosition;
                   }
                 });
               }
             }
           },
           onPanStart: (details) {
             // Only allow pan interaction if already animating
             if (_isAnimating) {
               setState(() {
                 _touchPosition = details.localPosition;
               });
             }
           },
           onPanUpdate: (details) {
             // Only allow pan interaction if already animating
             if (_isAnimating) {
               setState(() {
                 _touchPosition = details.localPosition;
               });
             }
           },
           onPanEnd: (details) {
             // Only allow pan interaction if already animating
             if (_isAnimating) {
               setState(() {
                 _touchPosition = null;
               });
             }
           },
           child: CustomPaint(
             // Use the size from LayoutBuilder for the painter
             size: size,
             painter: VisualiserPainter(
               particles: _particles,
               // Pass the calculated center to the painter
               center: center, // Pass the center calculated from constraints
               sphereRadius: _sphereRadius,
             ),
             // A child is needed for CustomPaint to size correctly if size isn't provided
             // child: Container(), // Not strictly needed since size is provided
           ),
         );
      },
    );
  }
  // --- End Updated _buildBodyContent ---
}


// --- Copied from visualiser_page.dart ---
// CustomPainter to draw the particles
class VisualiserPainter extends CustomPainter {
  final List<Particle> particles;
  final Offset center;
  final double sphereRadius; // Add sphereRadius

  VisualiserPainter({
    required this.particles,
    required this.center,
    required this.sphereRadius, // Require sphereRadius
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    for (var particle in particles) {
      paint.color = particle.color;

      // Draw particle at its current absolute position using pre-calculated size
      canvas.drawCircle(particle.position, particle.particleSize, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true; // Repaint whenever particles update
  }
}
// --- End Copied Section ---
