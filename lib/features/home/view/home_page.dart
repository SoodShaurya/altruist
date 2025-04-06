import 'dart:async';
// import 'dart:io'; // Removed, not needed for Deepgram streaming
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui'; // Added for Offset, Size, etc.

import 'package:altruist/services/deepgram/deepgram_stt_service.dart'; // Import Deepgram service
import 'package:altruist/services/elevenlabs/elevenlabs_service.dart';
import 'package:altruist/services/gemini/gemini_pro_service.dart';
// import 'package:altruist/services/google/google_stt_service.dart'; // Removed Google STT service
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Added for haptics
import 'package:flutter_svg/flutter_svg.dart';
import 'package:mic_stream/mic_stream.dart'; // Use mic_stream
// import 'package:path_provider/path_provider.dart'; // Removed, not needed for Deepgram streaming
import 'package:permission_handler/permission_handler.dart';
import 'package:screenshot/screenshot.dart';
import 'package:sliding_up_panel/sliding_up_panel.dart';

// --- Copied from visualiser_page.dart ---
// Represents a single particle in the simulation
class Particle {
  Offset position; // Current position
  Offset velocity; // Current velocity
  final Offset
      initialRingPosition; // Where it starts statically (relative to center)
  final Offset
      finalOrbitTargetPosition; // The center of its final orbit (relative to center)
  Offset
      currentTargetPosition; // Where it's currently trying to go (relative to center)
  Color color; // Made mutable
  final double
      particleSize; // Pre-calculated size (based on finalOrbitTargetPosition)

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

// Define application states (from tts_view.dart)
enum AppState {
  idle,
  listening,
  processing_stt,
  processing_gemini,
  speaking_tts
}

// Enum for the segmented button options
enum RecordingOption { screenRecording, camera }

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

// Added TickerProviderStateMixin
class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  // --- Original HomePage state ---
  bool _isCameraEnabled = true; // State for the camera toggle
  final PanelController _panelController =
      PanelController(); // Controller for the panel
  RecordingOption _selectedRecordingOption =
      RecordingOption.screenRecording; // State for segmented button

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
  final double _jitterStrength = 0.2; // How much random jitter to add
  final Random _random = Random(); // Random number generator for jitter
  bool _isAnimating = false; // Start in static state
  final double _initialRingRadiusFactor =
      0.8; // How far out the initial ring is
  final double _activationTapRadius =
      50.0; // Radius around center to activate animation (Increased)

  // Particle size constants
  static const double _maxSize = 1.1;
  static const double _minSize = 0.5;
  // --- End Copied State ---

  // --- Added State from _TtsViewState (using mic_stream) ---
  final _textController = TextEditingController(); // For conversation log
  final _voiceIdController = TextEditingController(); // For voice ID input
  final _elevenLabsService = ElevenLabsService();
  final _sttService = DeepgramSttService(); // Use the new Deepgram STT service
  final _geminiProService = GeminiProService(); // Instantiate Gemini Pro service
  final _screenshotController = ScreenshotController(); // Add screenshot controller

  AppState _appState = AppState.idle;
  StreamSubscription<Uint8List>? _micStreamSubscription;
  StreamSubscription<void>? _playbackCompleteSubscription;
  StreamSubscription<Map<String, dynamic>>? _deepgramSubscription; // Subscription for Deepgram results
  String _currentTranscript = ""; // To hold interim transcript

  // --- VAD/Buffering related state REMOVED ---
  // Timer? _silenceTimer;
  // final List<Uint8List> _speechBuffer = [];
  // String? _tempAudioFilePath;
  // final double _vadThreshold = 0.01;
  // final Duration _silenceDuration = const Duration(milliseconds: 2000);
  // final Duration _minSpeechDuration = const Duration(milliseconds: 1000);
  // DateTime? _speechStartTime;
  // --- End Added State ---

  // Merged initState
  @override
  void initState() {
    super.initState();
    // Visualiser Init
    _initializeParticles();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..addListener(_updateParticles);
    _controller.repeat(); // Keep visualiser running

    // TTS/STT Init (mic_stream based)
    _voiceIdController.text = _elevenLabsService.voiceId; // Init voice ID field
    _initAudio(); // Initialize audio permissions and listeners
  }

  // Merged dispose
  @override
  void dispose() {
    // Visualiser Dispose
    _controller.dispose();

    // TTS/STT/Recorder Dispose (mic_stream based)
    _textController.dispose();
    _voiceIdController.dispose();
    _stopListening(); // Ensure mic stream and Deepgram connection are stopped
    _playbackCompleteSubscription?.cancel();
    _sttService.dispose(); // Dispose Deepgram service
    // _elevenLabsService.dispose(); // No dispose method

    super.dispose();
  }

  // --- Copied methods from _VisualiserPageState (Unchanged) ---
  void _initializeParticles() {
    final random = Random();
    final double ringRadius = _sphereRadius * _initialRingRadiusFactor;
    _particles.clear();
    for (int i = 0; i < _numParticles; i++) {
      final double initialAngle = (i / _numParticles) * 2 * pi;
      final double initialX = ringRadius * cos(initialAngle);
      final double initialY = ringRadius * sin(initialAngle);
      final initialRingPos = Offset(initialX, initialY);
      double u = random.nextDouble();
      double v = random.nextDouble();
      double theta = 2 * pi * u;
      double phi = acos(2 * v - 1);
      double r = _sphereRadius * pow(random.nextDouble(), 1 / 3);
      double finalX = r * sin(phi) * cos(theta);
      double finalY = r * sin(phi) * sin(theta);
      final finalOrbitPos = Offset(finalX, finalY);
      final double distFromFinalOrigin = finalOrbitPos.distance;
      final double normalizedDist =
          (distFromFinalOrigin / _sphereRadius).clamp(0.0, 1.0);
      final double particleSize =
          _maxSize - (_maxSize - _minSize) * normalizedDist;
      _particles.add(
        Particle(
          position: initialRingPos,
          initialRingPosition: initialRingPos,
          finalOrbitTargetPosition: finalOrbitPos,
          currentTargetPosition: initialRingPos,
          particleSize: particleSize,
          velocity: Offset.zero,
          color: Colors.white.withOpacity(0.7 + random.nextDouble() * 0.3),
        ),
      );
    }
  }

  void _updateParticles() {
    final Offset? currentCenter = _center;
    if (!mounted || currentCenter == null) return;

    if (_isAnimating) {
      _rotationAngle += _rotationSpeed;
      for (var particle in _particles) {
        final double cosA = cos(_rotationAngle);
        final double sinA = sin(_rotationAngle);
        final double rotatedX = particle.finalOrbitTargetPosition.dx * cosA -
            particle.finalOrbitTargetPosition.dy * sinA;
        final double rotatedY = particle.finalOrbitTargetPosition.dx * sinA +
            particle.finalOrbitTargetPosition.dy * cosA;
        particle.currentTargetPosition = Offset(rotatedX, rotatedY);
      }
    }

    for (var particle in _particles) {
      final Offset targetVector =
          (currentCenter + particle.currentTargetPosition) - particle.position;
      Offset attractionForce = targetVector * _attractionStrength;
      Offset repulsionForce = Offset.zero;
      if (_isAnimating && _touchPosition != null) {
        final Offset touchVector = particle.position - _touchPosition!;
        final double distance = touchVector.distance;
        if (distance < _repulsionRadius && distance > 0) {
          final double strength =
              _repulsionStrength * (1.0 - distance / _repulsionRadius);
          repulsionForce =
              touchVector.scale(strength / distance, strength / distance);
        }
      }
      particle.velocity =
          (particle.velocity + attractionForce + repulsionForce) * _damping;
      particle.position += particle.velocity;
      final double jitterX = (_random.nextDouble() - 0.5) * 2 * _jitterStrength;
      final double jitterY = (_random.nextDouble() - 0.5) * 2 * _jitterStrength;
      particle.position += Offset(jitterX, jitterY);
    }
    setState(() {});
  }
  // --- End Copied Visualiser Methods ---

  // --- Added Methods from _TtsViewState (mic_stream based) ---

  // Renamed from _init in tts_view.dart
  Future<void> _initAudio() async {
    await _requestPermissions();
    // Don't start listening immediately, wait for tap interaction
    // Listen for TTS completion
    _playbackCompleteSubscription =
        _elevenLabsService.onPlaybackComplete.listen((_) {
      debugPrint("TTS Playback Complete");
      if (mounted && _appState == AppState.speaking_tts) {
        setStateIfMounted(() {
          _appState = AppState.idle;
        });
        // Only restart listening if the animation is still active
        if (_isAnimating) {
           _startListening(); // Go back to listening
        }
      }
    });
     debugPrint("Audio listener initialized.");
  }

  // --- Permission Handling (using permission_handler) ---
  Future<bool> _requestPermissions() async {
    // Use permission_handler directly
    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      debugPrint('Microphone permission denied by user.');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission is required.')),
        );
      }
      return false;
    }
    debugPrint('Microphone permission granted.');
    return true;
  }

  // --- Core Logic: Listening, VAD, STT, TTS (using mic_stream) ---

  Future<void> _startListening() async {
    // Prevent starting if not idle, or already listening, or not animating
    if (_appState != AppState.idle || _micStreamSubscription != null || !_isAnimating) {
       debugPrint("Cannot start listening. State: $_appState, Animating: $_isAnimating, Sub: ${_micStreamSubscription != null}");
       return;
    }

    debugPrint("Attempting to start listening...");

    // --- Request Permission On Demand ---
    final hasPermission = await _requestPermissions();
    if (!hasPermission) {
      // Reset state if permission is denied
      setStateIfMounted(() {
        _isAnimating = false; // Stop animation if permission denied
        _appState = AppState.idle;
        for (var p in _particles) {
          p.currentTargetPosition = p.initialRingPosition;
        }
      });
      return;
    }
    // --- End Permission Request ---

    debugPrint("Permission granted. Starting mic stream...");

    try {
      Stream<Uint8List>? stream = await MicStream.microphone(
          audioSource: AudioSource.DEFAULT,
          sampleRate: 16000,
          channelConfig: ChannelConfig.CHANNEL_IN_MONO,
          audioFormat: AudioFormat.ENCODING_PCM_16BIT);

      if (stream == null) {
        debugPrint("Failed to get microphone stream.");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not access microphone.')),
          );
        }
        setStateIfMounted(() { _appState = AppState.idle; });
        return;
      }

      // Connect to Deepgram *before* starting mic stream
      await _sttService.connect();
      if (!_sttService.isConnected) {
        debugPrint("Failed to connect to Deepgram.");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not connect to transcription service.')),
          );
        }
        setStateIfMounted(() { _appState = AppState.idle; });
        return; // Don't start mic if Deepgram failed
      }

      // Listen to Deepgram responses
      _deepgramSubscription = _sttService.transcriptStream.listen(
        _handleDeepgramResponse,
        onError: (error) {
           debugPrint("Deepgram stream error: $error");
           // Handle error appropriately, maybe show snackbar, reset state
           setStateIfMounted(() { _appState = AppState.idle; });
           _stopListening(); // Stop everything on Deepgram error
        },
        onDone: () {
           debugPrint("Deepgram stream closed.");
           // Handle closure if needed, maybe reset state if unexpected
           if (mounted && _appState != AppState.idle) {
              setStateIfMounted(() { _appState = AppState.idle; });
           }
        }
      );

      // Now start the mic stream
      _micStreamSubscription = stream.listen(
        _handleMicData,
        onError: (error) {
          debugPrint("Mic stream error: $error");
          _stopListening(); // Stop everything (mic and deepgram) on error
          setStateIfMounted(() { _appState = AppState.idle; });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Microphone error: $error')),
            );
          }
        },
        onDone: () {
          debugPrint("Mic stream closed.");
          if (mounted && _appState == AppState.listening) {
            _stopListening(); // Ensure cleanup if stream closes unexpectedly
            setStateIfMounted(() { _appState = AppState.idle; });
          }
        },
        cancelOnError: true,
      );

      setStateIfMounted(() {
        _appState = AppState.listening;
        _currentTranscript = ""; // Clear transcript for new session
        // _speechBuffer.clear(); // REMOVED
        // _speechStartTime = null; // REMOVED
      });
       debugPrint("Listening started (Mic stream and Deepgram connected).");

    } catch (e) {
      debugPrint("Error initializing mic stream: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to initialize microphone: $e')),
        );
      }
      setStateIfMounted(() { _appState = AppState.idle; });
    }
  }

  // Now stops both mic stream and Deepgram connection
  Future<void> _stopListening() async {
    if (_micStreamSubscription == null && !_sttService.isConnected) return; // Already stopped

    debugPrint("Stopping listening (Mic stream and Deepgram connection)...");

    // Cancel subscriptions first
    await _micStreamSubscription?.cancel();
    await _deepgramSubscription?.cancel();
    _micStreamSubscription = null;
    _deepgramSubscription = null;

    // Close Deepgram connection
    await _sttService.close();

    // Clear transcript
    _currentTranscript = "";

    // Reset state if not already idle (might be called during state transitions)
    // if (mounted && _appState != AppState.idle) {
    //    setStateIfMounted(() { _appState = AppState.idle; });
    // }
    // State reset is handled more explicitly in onTapDown and after processing.

    // _silenceTimer?.cancel(); // REMOVED
    // _silenceTimer = null; // REMOVED
    debugPrint("Listening stopped.");
  }

  // Process incoming audio chunks - Now just sends to Deepgram
  void _handleMicData(Uint8List data) {
    if (!mounted || !_isAnimating || !_sttService.isConnected) return; // Only process if animating and connected

    // Barge-in logic
    if (_appState == AppState.speaking_tts) {
      // Calculate RMS just for barge-in detection
      double rms = _calculateRMSForBargeIn(data);
      if (rms > 0.01) { // Use a simple threshold for barge-in
        debugPrint("Barge-in detected!");
        // --- Ensure UI/Service calls run on the platform thread ---
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return; // Check if still mounted in the callback
          _elevenLabsService.stop(); // Stop TTS playback
          // Reset state immediately to allow new speech processing
          setStateIfMounted(() {
            _appState = AppState.listening;
            _currentTranscript = ""; // Clear any partial transcript
          });
        });
        // --- End Platform Thread Execution ---
        // No need to buffer, just let the next audio chunk go to Deepgram
        // We might lose the very first chunk of the barge-in, but Deepgram should catch up.
      }
      // Don't send audio to Deepgram while TTS is speaking unless barge-in detected
      return;
    }

    // Send audio data directly to Deepgram service if listening
    if (_appState == AppState.listening) {
      _sttService.sendAudio(data);
    }
  }

  // Minimal RMS calculation specifically for barge-in detection threshold
  // Could be replaced with simpler energy check if preferred
  double _calculateRMSForBargeIn(Uint8List audioData) {
     double sum = 0;
     if (audioData.isEmpty) return 0.0;
     // Assuming 16-bit PCM
     for (int i = 0; i < audioData.lengthInBytes; i += 2) {
       int sample = (audioData[i + 1] << 8) | audioData[i];
       if (sample > 32767) sample -= 65536; // Convert to signed 16-bit
       double normalizedSample = sample / 32768.0; // Normalize
       sum += normalizedSample * normalizedSample;
     }
     double rms = sqrt(sum / (audioData.lengthInBytes / 2));
     return rms;
  }

  // --- Handler for Deepgram Stream Responses ---
  void _handleDeepgramResponse(Map<String, dynamic> response) {
    if (!mounted || !_isAnimating) return; // Ignore if not active

    final type = response['type'];

    if (type == 'Results') {
      final channel = response['channel'];
      final alternatives = channel?['alternatives'] as List<dynamic>?;
      final transcript = alternatives?.first?['transcript'] as String?;
      final isFinal = response['is_final'] as bool? ?? false;
      final speechFinal = response['speech_final'] as bool? ?? false;

      if (transcript != null && transcript.isNotEmpty) {
        if (isFinal) {
          // Append final segment to the current transcript
          _currentTranscript += transcript + " "; // Add space after segment

          if (speechFinal) {
            // End of utterance detected by Deepgram
            debugPrint("Deepgram final transcript: $_currentTranscript");
            if (_appState == AppState.listening) { // Only process if we were listening
               setStateIfMounted(() {
                 _appState = AppState.processing_gemini; // Go straight to Gemini
                 _textController.text += "You: ${_currentTranscript.trim()}\n"; // Update log
               });
               _transcribeAndGenerateResponse(_currentTranscript.trim()); // Trigger Gemini/TTS
               _currentTranscript = ""; // Reset for next utterance
            }
          }
        } else {
          // Interim results - maybe display them? (Optional)
          // debugPrint("Interim: $transcript");
          // You could update a temporary display field here if needed
        }
      }
    } else if (type == 'Metadata') {
      // Handle metadata if needed
    } else if (type == 'SpeechStarted') {
      debugPrint("Deepgram detected speech start.");
      // Could potentially update UI state here
    } else if (type == 'UtteranceEnd') {
      debugPrint("Deepgram detected utterance end.");
      // This might be redundant if using speech_final, but good for logging
    } else if (type == 'Error') {
       debugPrint("Deepgram Error: ${response['reason']}");
       // Handle error - maybe show snackbar, stop listening
       if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(content: Text('Transcription error: ${response['reason']}')),
          );
          _stopListening();
          setStateIfMounted(() { _appState = AppState.idle; });
       }
    } else if (type == 'Disconnected') {
       debugPrint("Deepgram disconnected notification received.");
       // Handle potential unexpected disconnect
       if (mounted && _appState != AppState.idle) {
          _stopListening();
          setStateIfMounted(() { _appState = AppState.idle; });
       }
    }
  }

  // --- VAD / Buffering / File Saving Methods REMOVED ---
  // _calculateRMS removed (replaced with minimal barge-in version)
  // _onSilenceDetected removed
  // _processBufferedAudio removed
  // _createWavHeader removed
  // _deleteTempFile removed


  // --- Modified Transcribe/Generate/Speak methods ---

  // Modified to accept final transcript string directly, removed STT part
  Future<void> _transcribeAndGenerateResponse(String finalTranscription) async {
    // Check if component is still mounted and animation is active
    // (Processing might have started just before user tapped to stop animation)
    if (!mounted || !_isAnimating) {
      debugPrint("Transcription/Generation cancelled: Not mounted or not animating.");
      setStateIfMounted(() { _appState = AppState.idle; });
      // File deletion handled in _processBufferedAudio's finally block
      return;
    }
    // Check STT service (already checked in original, good practice)
     if (_sttService == null) { // Should be initialized, but check anyway
       debugPrint("Transcription/Generation cancelled: STT service is null.");
       setStateIfMounted(() { _appState = AppState.idle; });
       if (_isAnimating) _startListening(); // Restart if still animating
       return;
     }

    // STT part is now handled by Deepgram stream before calling this function
    debugPrint("Starting generation pipeline for final transcript: $finalTranscription");
    String transcription = finalTranscription; // Use the provided final transcript
    Uint8List? screenshotBytes;

    // --- 1. Transcribe Audio --- REMOVED ---
    // Transcription is already done and passed as argument.
    // Log update was moved to _handleDeepgramResponse

    // --- 2. Capture Screenshot ---
    try {
      screenshotBytes = await _screenshotController.capture();
       if (!mounted || !_isAnimating) return; // Re-check after async

      if (screenshotBytes == null) {
        debugPrint('Screenshot capture failed.');
      } else {
        debugPrint('Screenshot captured successfully (${screenshotBytes.lengthInBytes} bytes).');
      }
    } catch (e) {
      debugPrint('Error capturing screenshot: $e');
      // Proceed without screenshot
    }

    // --- 3. Generate Content with Gemini Pro ---
    // State should already be processing_gemini (set in _handleDeepgramResponse)
    if (mounted && _isAnimating && transcription.isNotEmpty) {
       // setStateIfMounted(() { _appState = AppState.processing_gemini; }); // State already set
       String? geminiResponseText;

       try {
         if (screenshotBytes != null) {
           // Screenshot available
           geminiResponseText = await _geminiProService.generateContentWithImage(
             textPrompt: transcription,
             imageBytes: screenshotBytes,
           );
         } else {
           // Fallback: Screenshot failed, use text-only (or just speak transcription)
           // For now, let's assume we want to speak *something*, even if Gemini fails
           // If you have a text-only Gemini call, put it here.
           // Otherwise, we'll just speak the transcription later if geminiResponseText is null.
           debugPrint("Screenshot failed, attempting text-only generation or fallback.");
           // Example: geminiResponseText = await _geminiProService.generateContent(textPrompt: transcription);
         }

         if (!mounted || !_isAnimating) return; // Re-check after async

         if (geminiResponseText != null && geminiResponseText.isNotEmpty) {
           debugPrint('Gemini Pro response: $geminiResponseText');
           // Update conversation log
           setStateIfMounted(() {
             _textController.text += "AI: $geminiResponseText\n";
           });
           await _speakResponse(geminiResponseText); // Wait for speak to potentially finish/fail
         } else {
           // Gemini failed or returned empty, maybe speak transcription as fallback?
           debugPrint('Gemini Pro returned empty or null response. Speaking transcription as fallback.');
           // Update log to indicate fallback
           setStateIfMounted(() {
             _textController.text += "(AI failed, speaking transcription)\n";
           });
           await _speakResponse(transcription); // Speak original transcription
         }
       } catch (e) {
         debugPrint('Error during Gemini Pro call: $e');
         if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(content: Text('Error communicating with AI: $e')),
           );
           // Fallback: Speak transcription if AI fails
           setStateIfMounted(() {
             _textController.text += "(AI error, speaking transcription)\n";
             _appState = AppState.idle; // Reset state before speaking fallback
           });
           await _speakResponse(transcription); // Speak original transcription
         }
       }
    } else {
      // Handle cases where transcription failed or component unmounted/inactive
      debugPrint("Transcription missing or component unmounted/inactive, cannot proceed.");
      if (mounted) {
        setStateIfMounted(() { _appState = AppState.idle; });
        if (_isAnimating) _startListening(); // Restart if still animating
      }
    }
     // Final file cleanup happens in _processBufferedAudio's finally block
  }


  // Speak the provided text using TTS
  Future<void> _speakResponse(String text) async {
    // Only speak if still mounted and animating
    if (!mounted || !_isAnimating) {
       debugPrint("Speak cancelled: Not mounted or not animating.");
       setStateIfMounted(() { _appState = AppState.idle; });
       // Don't restart listening here, let the completion handler or tap handle it
       return;
    }
    debugPrint("Speaking response: $text");

    setStateIfMounted(() { _appState = AppState.speaking_tts; });

    try {
      await _elevenLabsService.speak(text);
      // State transition back to idle/listening is handled by _playbackCompleteSubscription
      // OR if speak fails below.
    } catch (e) {
      debugPrint('Error during TTS: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error during TTS: $e')),
        );
        // If TTS fails, go back to idle and potentially restart listening
        setStateIfMounted(() { _appState = AppState.idle; });
        if (_isAnimating) _startListening();
      }
    }
  }

  // Helper to safely call setState only if mounted
  void setStateIfMounted(VoidCallback fn) {
    if (mounted) {
      setState(fn);
    }
  }

  // --- UI Build Methods ---

  @override
  Widget build(BuildContext context) {
    const Color backgroundColor = Color(0xFF1E1E1E);
    const Color panelColor = Color(0xFF2A2A2A);
    const Color accentColor = Colors.white;

    return Screenshot(
      controller: _screenshotController,
      child: Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.menu, color: accentColor),
            onPressed: () { /* TODO: Implement */ },
          ),
          title: const Text(
            'altruist',
            style: TextStyle(
                fontFamily: 'Alliance No. 1',
                color: accentColor,
                fontWeight: FontWeight.w500),
          ),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.person_outline, color: accentColor),
              onPressed: () { /* TODO: Implement */ },
            ),
          ],
        ),
        body: SlidingUpPanel(
          controller: _panelController,
          minHeight: 100,
          maxHeight: MediaQuery.of(context).size.height * 0.7, // Increased max height for log
          parallaxEnabled: true,
          parallaxOffset: .5,
          color: panelColor,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24.0),
            topRight: Radius.circular(24.0),
          ),
          collapsed: _buildCollapsedPanel(),
          panel: _buildExpandedPanel(), // Now includes log and voice ID
          body: _buildBodyContent(), // Contains visualiser
        ),
      ),
    );
  }

  // Unchanged from original home_page.dart
  Widget _buildCollapsedPanel() {
    const Color accentColor = Colors.white;
    const Color inactiveColor = Colors.grey;

    return GestureDetector(
      onTap: () {
        if (_panelController.isPanelClosed) {
          _panelController.open();
        }
      },
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF2A2A2A),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24.0),
            topRight: Radius.circular(24.0),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(
                  left: 25.0, right: 25.0, top: 20.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SvgPicture.asset(
                    'assets/icons/logo.svg',
                    height: 40,
                    colorFilter:
                        const ColorFilter.mode(accentColor, BlendMode.srcIn),
                  ),
                  const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.keyboard_arrow_up,
                          color: inactiveColor, size: 20),
                      SizedBox(height: 2),
                      Text(
                        'settings',
                        style: TextStyle(color: inactiveColor, fontSize: 12),
                      ),
                    ],
                  ),
                  SizedBox(
                    height: 40,
                    width: 40,
                    child: OutlinedButton(
                      onPressed: () {
                        setState(() {
                          _isCameraEnabled = !_isCameraEnabled;
                        });
                      },
                      style: OutlinedButton.styleFrom(
                        shape: const CircleBorder(),
                        padding: EdgeInsets.zero,
                        side: const BorderSide(color: inactiveColor),
                        foregroundColor: accentColor,
                      ),
                      child: Icon(
                        _isCameraEnabled
                            ? Icons.videocam_outlined
                            : Icons.videocam_off_outlined,
                        color: accentColor,
                        size: 23,
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

  // Modified to include elements from tts_view.dart
  Widget _buildExpandedPanel() {
    const Color accentColor = Colors.white;
    const Color panelColor = Color(0xFF2A2A2A);
    const Color buttonBackgroundColor = Color(0xFF3C3C3C);
    const Color selectedButtonColor = Color(0xFF505050);
    final theme = Theme.of(context); // For text field styling

    return Container(
      decoration: const BoxDecoration(
        color: panelColor,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24.0),
          topRight: Radius.circular(24.0),
        ),
      ),
      // Use ListView for potentially long content
      child: ListView( // Changed from Column to ListView
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 15.0),
        children: [
          // Header Row (Unchanged)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Settings',
                style: TextStyle(
                  color: accentColor,
                  fontSize: 24,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'Alliance No. 1',
                ),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.widgets_outlined, color: accentColor),
                    onPressed: () { /* TODO: Implement */ },
                  ),
                  IconButton(
                    icon: const Icon(Icons.inbox_outlined, color: accentColor),
                    onPressed: () { /* TODO: Implement */ },
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Segmented Button (Unchanged)
          Center(
            child: SegmentedButton<RecordingOption>(
              segments: const <ButtonSegment<RecordingOption>>[
                ButtonSegment<RecordingOption>(
                  value: RecordingOption.screenRecording,
                  label: Text('Screen Recording'),
                ),
                ButtonSegment<RecordingOption>(
                  value: RecordingOption.camera,
                  label: Text('Camera'),
                ),
              ],
              selected: <RecordingOption>{_selectedRecordingOption},
              onSelectionChanged: (Set<RecordingOption> newSelection) {
                setState(() {
                  _selectedRecordingOption = newSelection.first;
                });
              },
              style: SegmentedButton.styleFrom(
                backgroundColor: buttonBackgroundColor,
                foregroundColor: accentColor.withOpacity(0.7),
                selectedForegroundColor: accentColor,
                selectedBackgroundColor: selectedButtonColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.0),
                ),
              ),
            ),
          ),
          const SizedBox(height: 25), // Spacing

          // --- Voice ID Input (from tts_view.dart) ---
          Text('ElevenLabs Voice', style: theme.textTheme.titleMedium?.copyWith(color: accentColor)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _voiceIdController,
                  style: const TextStyle(color: accentColor), // Text color
                  decoration: InputDecoration(
                    labelText: 'Voice ID',
                    labelStyle: TextStyle(color: accentColor.withOpacity(0.7)),
                    filled: true,
                    fillColor: buttonBackgroundColor, // Background color
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12.0),
                      borderSide: BorderSide.none, // No border
                    ),
                    focusedBorder: OutlineInputBorder( // Border when focused
                      borderRadius: BorderRadius.circular(12.0),
                      borderSide: const BorderSide(color: accentColor, width: 1.0),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: () {
                  final newVoiceId = _voiceIdController.text.trim();
                  if (newVoiceId.isNotEmpty) {
                    _elevenLabsService.setVoice(newVoiceId);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Voice ID set to: $newVoiceId')),
                    );
                    FocusScope.of(context).unfocus(); // Hide keyboard
                  }
                },
                 style: ElevatedButton.styleFrom(
                   backgroundColor: selectedButtonColor, // Button color
                   foregroundColor: accentColor, // Text color
                   shape: RoundedRectangleBorder(
                     borderRadius: BorderRadius.circular(12.0),
                   ),
                   padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                 ),
                child: const Text('Set'),
              ),
            ],
          ),
          // --- End Voice ID Input ---

          const SizedBox(height: 25), // Spacing

          // --- Conversation Log (from tts_view.dart) ---
          Text('Conversation Log', style: theme.textTheme.titleMedium?.copyWith(color: accentColor)),
          const SizedBox(height: 8),
          TextField(
            controller: _textController,
            readOnly: true,
            minLines: 4,
            maxLines: 8, // Adjust max lines as needed
            style: const TextStyle(color: accentColor),
            decoration: InputDecoration(
              filled: true,
              fillColor: buttonBackgroundColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.0),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.all(12.0), // Padding inside the text field
            ),
          ),
          // --- End Conversation Log ---

        ],
      ),
    );
  }

  // Modified to use mic_stream start/stop logic
  Widget _buildBodyContent() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 100.0), // Keep padding below panel minHeight
      child: LayoutBuilder(
        builder: (context, constraints) {
          final Size size = constraints.biggest;
          final Offset center = Offset(size.width / 2, size.height / 2);

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && (_center == null || (_center! - center).distance > 1.0)) {
              final bool needsInitialPositioning = _particles.isNotEmpty &&
                  _particles[0].position == _particles[0].initialRingPosition;
              setStateIfMounted(() { // Use safe setState
                _center = center;
                if (needsInitialPositioning) {
                  for (var p in _particles) {
                    p.position = center + p.initialRingPosition;
                  }
                }
              });
            }
          });

          return GestureDetector(
            onTapDown: (details) {
              if (_center == null) return;

              if (_isAnimating) {
                // --- Deactivate Animation and Stop Audio ---
                debugPrint("Deactivating animation and stopping audio...");
                setStateIfMounted(() {
                  _isAnimating = false;
                  _touchPosition = null;
                  for (var p in _particles) {
                    p.currentTargetPosition = p.initialRingPosition;
                  }
                  HapticFeedback.mediumImpact();

                  // Stop audio processing (mic and Deepgram)
                  _stopListening(); // Stops mic stream and Deepgram connection
                  _elevenLabsService.stop(); // Stop any ongoing TTS
                  _appState = AppState.idle; // Reset state
                  // _speechBuffer.clear(); // REMOVED
                  // _silenceTimer?.cancel(); // REMOVED
                  // _speechStartTime = null; // REMOVED
                });
                 debugPrint("Animation stopped, listening stopped.");
              } else {
                // --- Activate Animation and Start Audio ---
                final tapPos = details.localPosition;
                final distanceToCenter = (tapPos - _center!).distance;
                if (distanceToCenter < _activationTapRadius) {
                   debugPrint("Activating animation and starting audio...");
                  setStateIfMounted(() {
                    _isAnimating = true;
                    for (var p in _particles) {
                      p.currentTargetPosition = p.finalOrbitTargetPosition;
                    }
                    HapticFeedback.mediumImpact();

                    // Start audio processing (mic_stream)
                    _appState = AppState.idle; // Ensure starting from idle
                  });
                  // Start listening AFTER setting state
                  _startListening(); // Use the mic_stream start method
                   debugPrint("Animation started, listening initiated.");
                }
              }
            },
            onPanStart: (details) {
              if (_isAnimating) setStateIfMounted(() { _touchPosition = details.localPosition; });
            },
            onPanUpdate: (details) {
              if (_isAnimating) setStateIfMounted(() { _touchPosition = details.localPosition; });
            },
            onPanEnd: (details) {
              if (_isAnimating) setStateIfMounted(() { _touchPosition = null; });
            },
            child: CustomPaint(
              size: size,
              painter: VisualiserPainter(
                particles: _particles,
                center: center,
                sphereRadius: _sphereRadius,
              ),
            ),
          );
        },
      ),
    );
  }
} // End of _HomePageState

// --- Copied from visualiser_page.dart (Unchanged) ---
class VisualiserPainter extends CustomPainter {
  final List<Particle> particles;
  final Offset center;
  final double sphereRadius;

  VisualiserPainter({
    required this.particles,
    required this.center,
    required this.sphereRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (var particle in particles) {
      paint.color = particle.color;
      canvas.drawCircle(particle.position, particle.particleSize, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}
// --- End Copied Section ---
