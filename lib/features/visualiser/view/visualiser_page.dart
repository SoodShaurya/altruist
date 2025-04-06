import 'dart:math';
import 'package:flutter/material.dart';

// Represents a single particle in the simulation
class Particle {
  Offset position; // Current position
  Offset velocity; // Current velocity
  final Offset homePosition; // Target position it's attracted to
  final Color color;

  Particle({
    required this.position,
    required this.homePosition,
    this.velocity = Offset.zero,
    this.color = Colors.white,
  });
}

class VisualiserPage extends StatefulWidget {
  const VisualiserPage({super.key});

  @override
  State<VisualiserPage> createState() => _VisualiserPageState();
}

// Add TickerProviderStateMixin for animation
class _VisualiserPageState extends State<VisualiserPage>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  final List<Particle> _particles = [];
  final int _numParticles = 200; // Increased particle count
  final double _sphereRadius = 150.0; // Radius for particle home positions
  Offset? _touchPosition; // Current touch position

  // Physics parameters
  final double _attractionStrength = 0.02;
  final double _repulsionStrength = 150.0; // Increased repulsion
  final double _repulsionRadius = 80.0; // Radius around touch for repulsion
  final double _damping = 0.95; // Slows down particles
  final double _orbitStrength = 0.01; // Strength of the orbiting effect

  @override
  void initState() {
    super.initState();
    _initializeParticles();

    _controller = AnimationController(
      vsync: this,
      duration:
          const Duration(seconds: 1), // Duration doesn't really matter here
    )..addListener(_updateParticles);

    _controller.repeat(); // Run the animation loop continuously
  }

  void _initializeParticles() {
    final random = Random();
    // REMOVED: Cannot access MediaQuery here.
    // We calculate relative home positions only.
    // Absolute positioning happens after the first build.

    for (int i = 0; i < _numParticles; i++) {
      // Generate random point within a sphere using spherical coordinates
      double u = random.nextDouble(); // 0 to 1
      double v = random.nextDouble(); // 0 to 1
      double theta = 2 * pi * u; // Azimuthal angle
      double phi = acos(2 * v - 1); // Polar angle
      double r = _sphereRadius *
          pow(random.nextDouble(),
              1 / 3); // Radius, cube root for uniform distribution

      double x = r * sin(phi) * cos(theta);
      double y = r * sin(phi) * sin(theta);
      // We ignore z for 2D projection, or could use it for size/color scaling

      // Home position relative to center (will be added later)
      final homePos = Offset(x, y);

      _particles.add(
        Particle(
          // Initial position is the home position
          position: homePos,
          homePosition: homePos,
          color: Colors.white.withOpacity(0.7 + random.nextDouble() * 0.3),
        ),
      );
    }
  }

  void _updateParticles() {
    if (!mounted) return; // Ensure widget is still in the tree

    final Size screenSize = MediaQuery.of(context).size;
    final Offset center = Offset(screenSize.width / 2, screenSize.height / 2);

    for (var particle in _particles) {
      // Calculate vector from current position to home position (relative to center)
      final Offset homeVector =
          (center + particle.homePosition) - particle.position;
      // Attraction force towards home
      Offset attractionForce = homeVector * _attractionStrength;

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

      // Calculate orbiting force (perpendicular to the vector from center)
      final Offset vectorFromCenter = particle.position - center;
      Offset orbitForce = Offset.zero;
      if (vectorFromCenter.distanceSquared > 1e-4) { // Avoid division by zero/NaN
         // Perpendicular vector (rotate 90 degrees)
        final Offset perpendicular = Offset(-vectorFromCenter.dy, vectorFromCenter.dx);
        // Normalize and scale by orbit strength and distance (faster orbit further out, adjust as needed)
        final double orbitSpeedFactor = 1.0; // Could adjust this based on distance if desired
        orbitForce = perpendicular.scale(
          (_orbitStrength * orbitSpeedFactor) / perpendicular.distance,
          (_orbitStrength * orbitSpeedFactor) / perpendicular.distance
        );
      }

      // Update velocity (add orbitForce)
      particle.velocity =
          (particle.velocity + attractionForce + repulsionForce + orbitForce) * _damping;

      // Update position
      particle.position += particle.velocity;
    }

    // Trigger repaint
    setState(() {});
  }

  @override
  void dispose() {
    _controller.dispose(); // Clean up the controller
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Size screenSize = MediaQuery.of(context).size;
    final Offset center = Offset(screenSize.width / 2, screenSize.height / 2);

    // Check if particles need initial absolute positioning (only once after build)
    // We check if the first particle's position is still just its relative home position.
    if (_particles.isNotEmpty &&
        _particles[0].position == _particles[0].homePosition) {
      // Use addPostFrameCallback to position particles after the first frame is built
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          // Check if the widget is still mounted
          setState(() {
            // Calculate the absolute initial position based on the actual center
            for (var p in _particles) {
              // Set the initial position relative to the screen center
              p.position = center + p.homePosition;
            }
          });
        }
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Particle Visualiser'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white, // Make back button white
      ),
      backgroundColor: const Color(0xFF1E1E1E), // Match home page background
      body: GestureDetector(
        onPanStart: (details) {
          setState(() {
            _touchPosition = details.localPosition;
          });
        },
        onPanUpdate: (details) {
          setState(() {
            _touchPosition = details.localPosition;
          });
        },
        onPanEnd: (details) {
          setState(() {
            _touchPosition = null;
          });
        },
        child: CustomPaint(
          painter: VisualiserPainter(
            particles: _particles,
            center: center,
            sphereRadius: _sphereRadius, // Pass sphereRadius
          ),
          child: Container(), // Takes up the entire space
        ),
      ),
    );
  }
}

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
    const double maxSize = 3.5; // Max size for particles near center
    const double minSize = 1.0; // Min size for particles near edge

    for (var particle in particles) {
      paint.color = particle.color;

      // Calculate size based on distance from home position origin
      final double distFromHomeOrigin = particle.homePosition.distance;
      // Normalize distance (0 at center, 1 at sphereRadius)
      final double normalizedDist = (distFromHomeOrigin / sphereRadius).clamp(0.0, 1.0);
      // Interpolate size: larger closer to center, smaller further out
      final double particleSize = maxSize - (maxSize - minSize) * normalizedDist;

      // Draw particle at its current absolute position with calculated size
      canvas.drawCircle(particle.position, particleSize, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true; // Repaint whenever particles update
  }
}
