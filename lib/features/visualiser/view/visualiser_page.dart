import 'dart:math';
import 'package:flutter/material.dart';

// Represents a single particle in the simulation
class Particle {
  Offset position; // Current position
  Offset velocity; // Current velocity
  final Offset originalHomePosition; // Original target position (relative to center)
  Offset currentTargetPosition; // Current target position (relative to center, rotates)
  final Color color;

  Particle({
    required this.position,
    required this.originalHomePosition,
    required this.currentTargetPosition,
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
  final int _numParticles = 700; // Increased particle count
  final double _sphereRadius = 150.0; // Radius for particle home positions
  Offset? _touchPosition; // Current touch position

  // Physics parameters
  final double _attractionStrength = 0.02;
  final double _repulsionStrength = 150.0; // Increased repulsion
  final double _repulsionRadius = 80.0; // Radius around touch for repulsion
  final double _damping = 0.95; // Slows down particles
  double _rotationAngle = 0.0; // Current rotation angle for targets
  final double _rotationSpeed = 0.005; // Speed of target rotation

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

      // REMOVED: Initial velocity calculation is no longer needed

      _particles.add(
        Particle(
          // Initial position is the home position
          position: homePos,
          originalHomePosition: homePos, // Store the original relative position
          currentTargetPosition: homePos, // Initially, target is the home position
          color: Colors.white.withOpacity(0.7 + random.nextDouble() * 0.3),
        ),
      );
    }
  }

  void _updateParticles() {
    if (!mounted) return; // Ensure widget is still in the tree

    final Size screenSize = MediaQuery.of(context).size;
    final Offset center = Offset(screenSize.width / 2, screenSize.height / 2);

    // Update rotation angle
    _rotationAngle += _rotationSpeed;

    for (var particle in _particles) {
      // Rotate the target position
      final double cosA = cos(_rotationAngle);
      final double sinA = sin(_rotationAngle);
      final double rotatedX = particle.originalHomePosition.dx * cosA - particle.originalHomePosition.dy * sinA;
      final double rotatedY = particle.originalHomePosition.dx * sinA + particle.originalHomePosition.dy * cosA;
      particle.currentTargetPosition = Offset(rotatedX, rotatedY);

      // Calculate vector from current position to the *current target* position (relative to center)
      final Offset targetVector =
          (center + particle.currentTargetPosition) - particle.position;
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

      // Update velocity (No orbit force needed anymore)
      particle.velocity =
          (particle.velocity + attractionForce + repulsionForce) * _damping;

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
    // We check if the first particle's position is still just its relative original home position.
    if (_particles.isNotEmpty &&
        _particles[0].position == _particles[0].originalHomePosition) {
      // Use addPostFrameCallback to position particles after the first frame is built
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          // Check if the widget is still mounted
          setState(() {
            // Calculate the absolute initial position based on the actual center
            for (var p in _particles) {
              // Set the initial position relative to the screen center using the original home position
              p.position = center + p.originalHomePosition;
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
    const double maxSize = 1.1; // Max size for particles near center
    const double minSize = 0.5; // Min size for particles near edge

    for (var particle in particles) {
      paint.color = particle.color;

      // Calculate size based on distance from the *original* home position origin
      final double distFromHomeOrigin = particle.originalHomePosition.distance;
      // Normalize distance (0 at center, 1 at sphereRadius)
      final double normalizedDist =
          (distFromHomeOrigin / sphereRadius).clamp(0.0, 1.0);
      // Interpolate size: larger closer to center, smaller further out
      final double particleSize =
          maxSize - (maxSize - minSize) * normalizedDist;

      // Draw particle at its current absolute position with calculated size
      canvas.drawCircle(particle.position, particleSize, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true; // Repaint whenever particles update
  }
}
