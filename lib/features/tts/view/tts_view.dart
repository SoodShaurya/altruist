import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math'; // For VAD calculation

import 'package:altruist/services/elevenlabs/elevenlabs_service.dart';
// import 'package:altruist/elevenlabs/elevenlabs_stt_service.dart'; // No longer needed
// import 'package:altruist/services/google/google_stt_service.dart'; // Removed Google STT service
import 'package:altruist/services/gemini/gemini_pro_service.dart'; // Import Gemini Pro service
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mic_stream/mic_stream.dart'; // Import mic_stream
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:screenshot/screenshot.dart'; // Import screenshot package
// import 'package:record/record.dart'; // No longer needed for recording trigger

// Define application states
enum AppState {
  idle,
  listening,
  processing_stt,
  processing_gemini,
  speaking_tts
} // Added processing_gemini

class TtsView extends StatefulWidget {
  const TtsView({super.key});

  @override
  State<TtsView> createState() => _TtsViewState();
}

class _TtsViewState extends State<TtsView> {
  final _textController = TextEditingController();
  final _voiceIdController =
      TextEditingController(); // Controller for voice ID input
  final _elevenLabsService = ElevenLabsService();
  // final _sttService = GoogleSttService(); // Removed Google STT service
  final _geminiProService =
      GeminiProService(); // Instantiate Gemini Pro service
  final _screenshotController =
      ScreenshotController(); // Add screenshot controller

  AppState _appState = AppState.idle;
  StreamSubscription<Uint8List>? _micStreamSubscription;
  StreamSubscription<void>? _playbackCompleteSubscription;
  Timer? _silenceTimer;
  final List<Uint8List> _speechBuffer = [];
  String? _tempAudioFilePath; // Path for saving buffered audio

  // VAD Parameters (tune these)
  final double _vadThreshold =
      0.01; // RMS threshold for speech detection (Increased from 0.01)
  final Duration _silenceDuration = const Duration(
      milliseconds:
          2000); // Time to wait before processing (Increased from 1500)
  final Duration _minSpeechDuration = const Duration(
      milliseconds:
          3000); // Minimum speech length to process (Increased from 300)
  DateTime? _speechStartTime;

  @override
  void initState() {
    super.initState();
    // Initialize voice ID controller with the current voice ID
    _voiceIdController.text = _elevenLabsService.voiceId;
    _init();
  }

  Future<void> _init() async {
    await _requestPermissions();
    // Start listening immediately if permission granted
    if (await Permission.microphone.isGranted) {
      _startListening();
    } else {
      // Optionally show a message that mic is needed
      debugPrint("Microphone permission not granted at init.");
    }
    // Listen for TTS completion
    _playbackCompleteSubscription =
        _elevenLabsService.onPlaybackComplete.listen((_) {
      debugPrint("TTS Playback Complete");
      if (mounted && _appState == AppState.speaking_tts) {
        setState(() {
          _appState = AppState.idle;
        });
        _startListening(); // Go back to listening
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _voiceIdController.dispose(); // Dispose the new controller
    _stopListening(); // Ensure stream is stopped
    _silenceTimer?.cancel();
    _playbackCompleteSubscription?.cancel();
    // _sttService.dispose(); // Remove dispose call if ElevenLabsSttService doesn't have it
    super.dispose();
  }

  // --- Permission Handling ---
  Future<void> _requestPermissions() async {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      final status = await Permission.microphone.request();
      if (status != PermissionStatus.granted) {
        debugPrint('Microphone permission denied.');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission is required.')),
        );
      }
    }
  }

  // --- Core Logic: Listening, VAD, STT, TTS ---

  Future<void> _startListening() async {
    if (_appState != AppState.idle && _appState != AppState.listening)
      return; // Prevent starting if busy/speaking
    if (_micStreamSubscription != null) return; // Already listening

    debugPrint("Starting listening...");
    if (!await Permission.microphone.isGranted) {
      debugPrint("Cannot start listening, permission denied.");
      await _requestPermissions(); // Try requesting again
      if (!await Permission.microphone.isGranted) return;
    }

    try {
      // Get the stream, handling potential errors
      Stream<Uint8List>? stream = await MicStream.microphone(
          audioSource: AudioSource.DEFAULT,
          sampleRate: 16000, // Common sample rate for STT
          channelConfig: ChannelConfig.CHANNEL_IN_MONO,
          audioFormat: AudioFormat.ENCODING_PCM_16BIT);

      if (stream == null) {
        debugPrint("Failed to get microphone stream.");
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not access microphone.')),
        );
        setState(() {
          _appState = AppState.idle;
        });
        return;
      }

      _micStreamSubscription = stream.listen(
        _handleMicData,
        onError: (error) {
          debugPrint("Mic stream error: $error");
          _stopListening(); // Stop on error
          setState(() {
            _appState = AppState.idle;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Microphone error: $error')),
          );
        },
        onDone: () {
          debugPrint("Mic stream closed.");
          if (mounted && _appState == AppState.listening) {
            _stopListening(); // Ensure cleanup if stream closes unexpectedly
            setState(() {
              _appState = AppState.idle;
            });
          }
        },
        cancelOnError: true, // Automatically cancel subscription on error
      );

      setState(() {
        _appState = AppState.listening;
        _speechBuffer.clear(); // Clear buffer for new session
      });
    } catch (e) {
      debugPrint("Error initializing mic stream: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to initialize microphone: $e')),
      );
      setState(() {
        _appState = AppState.idle;
      });
    }
  }

  void _stopListening() {
    debugPrint("Stopping listening...");
    _micStreamSubscription?.cancel();
    _micStreamSubscription = null;
    _silenceTimer?.cancel();
    _silenceTimer = null;
    // Don't reset state here, might be transitioning
  }

  // Process incoming audio chunks for VAD
  void _handleMicData(Uint8List data) {
    if (!mounted) return;

    // Simple RMS calculation for VAD (adjust as needed)
    double rms = _calculateRMS(data);
    // debugPrint("RMS: $rms"); // Uncomment for tuning

    bool isSpeaking = rms > _vadThreshold;

    if (isSpeaking) {
      _speechStartTime ??= DateTime.now(); // Mark start time on first detection
      _silenceTimer?.cancel(); // Reset silence timer on speech
      _silenceTimer = null;

      // Barge-in logic
      if (_appState == AppState.speaking_tts) {
        debugPrint("Barge-in detected!");
        _elevenLabsService.stop(); // Stop TTS playback
        // _playbackCompleteSubscription handles state change implicitly? No, need explicit change.
        setState(() {
          _appState = AppState.listening; // Immediately switch to listening
          _speechBuffer.clear(); // Clear buffer for new user input
          _speechBuffer.add(data); // Add the interrupting data
        });
        return; // Skip further processing for this chunk
      }

      // Start or continue listening
      if (_appState == AppState.idle) {
        setState(() {
          _appState = AppState.listening;
        });
      }

      if (_appState == AppState.listening) {
        _speechBuffer.add(data); // Add speech data to buffer
      }
    } else {
      // Silence detected
      if (_appState == AppState.listening &&
          _silenceTimer == null &&
          _speechBuffer.isNotEmpty) {
        // Start silence timer only if we were listening and have data
        _silenceTimer = Timer(_silenceDuration, _onSilenceDetected);
      }
    }
  }

  // Calculate Root Mean Square for basic VAD
  double _calculateRMS(Uint8List audioData) {
    double sum = 0;
    // Assuming 16-bit PCM
    for (int i = 0; i < audioData.lengthInBytes; i += 2) {
      int sample = (audioData[i + 1] << 8) | audioData[i];
      // Convert to signed 16-bit
      if (sample > 32767) sample -= 65536;
      // Normalize to -1.0 to 1.0 (approx)
      double normalizedSample = sample / 32768.0;
      sum += normalizedSample * normalizedSample;
    }
    double rms = sqrt(sum / (audioData.lengthInBytes / 2));
    return rms;
  }

  // Called when silence duration is met
  void _onSilenceDetected() {
    if (!mounted || _appState != AppState.listening || _speechBuffer.isEmpty) {
      _silenceTimer = null; // Ensure timer is cleared if state changed
      return;
    }

    final speechDuration = _speechStartTime != null
        ? DateTime.now().difference(_speechStartTime!)
        : Duration.zero;
    _speechStartTime = null; // Reset start time

    if (speechDuration < _minSpeechDuration) {
      debugPrint("Speech too short ($speechDuration), ignoring.");
      _speechBuffer.clear();
      _silenceTimer = null;
      // Stay in listening state
      return;
    }

    debugPrint("Silence detected, processing speech...");
    _stopListening(); // Stop the mic stream while processing

    setState(() {
      _appState = AppState.processing_stt;
    });

    _processBufferedAudio(); // Process the collected audio
  }

  // Combine buffered audio chunks, save, and trigger processing pipeline
  Future<void> _processBufferedAudio() async {
    if (_speechBuffer.isEmpty) {
      debugPrint("No audio in buffer to process.");
      setState(() {
        _appState = AppState.idle;
      });
      _startListening(); // Go back to idle/listening
      return;
    }

    // Combine chunks into a single byte list
    final combinedData = BytesBuilder();
    for (var chunk in _speechBuffer) {
      combinedData.add(chunk);
    }
    final audioBytes = combinedData.toBytes();
    _speechBuffer.clear(); // Clear buffer immediately

    // --- Save to temporary file (Required by STT Service) ---
    try {
      final tempDir = await getTemporaryDirectory();
      _tempAudioFilePath =
          '${tempDir.path}/vad_recording_${DateTime.now().millisecondsSinceEpoch}.wav'; // Save as WAV

      // --- Create WAV Header ---
      final file = File(_tempAudioFilePath!);
      final header = _createWavHeader(
          audioBytes.length, 16000, 1, 16); // 16kHz, Mono, 16-bit
      final fileSink = file.openWrite();
      fileSink.add(header);
      fileSink.add(audioBytes);
      await fileSink.close();
      debugPrint("Buffered audio saved to: $_tempAudioFilePath");

      // --- Start Transcription and Generation Pipeline ---
      await _transcribeAndGenerateResponse(
          _tempAudioFilePath!); // Call the new pipeline function
    } catch (e) {
      debugPrint("Error saving/processing buffered audio: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error processing audio: $e')),
      );
      setState(() {
        _appState = AppState.idle;
      });
      _startListening(); // Go back to idle/listening
    } finally {
      // Clean up temp file (even if transcription/generation fails)
      if (_tempAudioFilePath != null) {
        final tempFile = File(_tempAudioFilePath!);
        if (await tempFile.exists()) {
          tempFile.delete().catchError(
              (e) => debugPrint("Error deleting VAD temp file: $e"));
          debugPrint("Deleted VAD temp file: $_tempAudioFilePath");
        }
        _tempAudioFilePath = null;
      }
    }
  }

  // Creates a minimal WAV header for raw PCM data
  Uint8List _createWavHeader(
      int dataLength, int sampleRate, int numChannels, int bitsPerSample) {
    final byteRate = (sampleRate * numChannels * bitsPerSample) ~/ 8;
    final blockAlign = (numChannels * bitsPerSample) ~/ 8;
    final totalDataLen = dataLength;
    final totalWavLen =
        totalDataLen + 36; // 44 bytes header - 8 bytes for RIFF/WAVE chunks

    final header = ByteData(44);
    final bytes = Uint8List.view(header.buffer);

    // RIFF chunk
    bytes.setRange(0, 4, [0x52, 0x49, 0x46, 0x46]); // 'RIFF'
    header.setUint32(4, totalWavLen, Endian.little);
    bytes.setRange(8, 12, [0x57, 0x41, 0x56, 0x45]); // 'WAVE'

    // fmt chunk
    bytes.setRange(12, 16, [0x66, 0x6d, 0x74, 0x20]); // 'fmt '
    header.setUint32(16, 16, Endian.little); // Subchunk1Size (16 for PCM)
    header.setUint16(20, 1, Endian.little); // AudioFormat (1 for PCM)
    header.setUint16(22, numChannels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);

    // data chunk
    bytes.setRange(36, 40, [0x64, 0x61, 0x74, 0x61]); // 'data'
    header.setUint32(40, totalDataLen, Endian.little);

    return bytes;
  }

  // New function: Transcribe audio, capture screenshot, generate response with Gemini Pro
  Future<void> _transcribeAndGenerateResponse(String audioFilePath) async {
    debugPrint(
        "Starting transcription and generation pipeline for: $audioFilePath");
    String? transcription;
    Uint8List? screenshotBytes;

    // --- 1. Transcribe Audio ---
    // State is already processing_stt
    // NOTE: STT Service was removed, this section needs reimplementation
    // if STT is required in this view again. For now, we'll skip it.
    try {
      // transcription = await _sttService.transcribeAudio(audioFilePath); // Removed call
      // Simulate transcription failure for now as STT is not available here
      transcription = null; // Assume transcription failed
      debugPrint('STT Service removed, skipping transcription step.');

      if (transcription == null || transcription.isEmpty) {
        debugPrint('Transcription failed or returned empty (STT service removed).');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Speech-to-text failed.')),
          );
          setState(() {
            _appState = AppState.idle;
          });
          _startListening(); // Go back to listening
        }
        return; // Stop processing if transcription failed
      }
      debugPrint('Transcription successful: $transcription');
      if (mounted) {
        // Update text field immediately after transcription
        setState(() {
          _textController.text = transcription!;
        });
      }
    } catch (e) {
      debugPrint('Error during transcription: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error during transcription: $e')),
        );
        setState(() {
          _appState = AppState.idle;
        });
        _startListening(); // Go back to listening
      }
      return; // Stop processing on error
    }

    // --- 2. Capture Screenshot ---
    try {
      // Capture the screenshot *after* transcription is done
      screenshotBytes = await _screenshotController.capture();
      if (screenshotBytes == null) {
        debugPrint('Screenshot capture failed.');
        // Decide if you want to proceed without screenshot or show error
        // For now, let's proceed without it but log the error
      } else {
        debugPrint(
            'Screenshot captured successfully (${screenshotBytes.lengthInBytes} bytes).');
      }
    } catch (e) {
      debugPrint('Error capturing screenshot: $e');
      // Proceed without screenshot on error
    }

    // --- 3. Generate Content with Gemini Pro ---
    if (mounted && transcription != null && screenshotBytes != null) {
      // Screenshot available, call multimodal Gemini
      setState(() {
        _appState = AppState.processing_gemini; // Update state
      });
      try {
        final geminiResponse = await _geminiProService.generateContentWithImage(
          textPrompt: transcription,
          imageBytes: screenshotBytes,
        );

        if (mounted) {
          if (geminiResponse != null && geminiResponse.isNotEmpty) {
            debugPrint('Gemini Pro response: $geminiResponse');
            // Append Gemini response to the text field
            setState(() {
              _textController.text += "\n\nGemini: $geminiResponse";
            });
            _speakResponse(geminiResponse); // Speak the Gemini response
          } else {
            debugPrint('Gemini Pro returned empty or null response.');
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Failed to get response from AI.')),
            );
            setState(() {
              _appState = AppState.idle;
            });
            _startListening(); // Go back to listening
          }
        }
      } catch (e) {
        debugPrint('Error during Gemini Pro call: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error communicating with AI: $e')),
          );
          setState(() {
            _appState = AppState.idle;
          });
          _startListening(); // Go back to listening
        }
      }
    } else if (mounted && transcription != null) {
      // --- Fallback: If screenshot failed or wasn't captured, just speak the transcription ---
      // Alternatively, you could call a text-only Gemini model here.
      debugPrint(
          "Screenshot failed or unavailable, speaking transcription only.");
      _speakResponse(transcription);
    } else {
      // Handle cases where transcription might have failed earlier (already handled above)
      // Or if component became unmounted.
      debugPrint(
          "Transcription missing or component unmounted, cannot proceed.");
      if (mounted) {
        setState(() {
          _appState = AppState.idle;
        });
        _startListening();
      }
    }
  }

  // Legacy function name, now just calls the pipeline
  Future<void> _transcribeAudio(String audioFilePath) async {
    await _transcribeAndGenerateResponse(audioFilePath);
  }

  // Speak the provided text using TTS
  Future<void> _speakResponse(String text) async {
    if (!mounted) return;
    debugPrint("Speaking response: $text");

    setState(() {
      _appState = AppState.speaking_tts;
    });

    try {
      await _elevenLabsService.speak(text);
      // IMPORTANT: State transition back to idle/listening is handled
      // by the _playbackCompleteSubscription listening to onPlaybackComplete.
    } catch (e) {
      debugPrint('Error during TTS: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error during TTS: $e')),
        );
        // If TTS fails, go back to listening
        setState(() {
          _appState = AppState.idle;
        });
        _startListening();
      }
    }
  }

  // --- UI ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('VAD Conversation'), // Updated title
      ),
      // Wrap the Scaffold body with Screenshot widget
      body: Screenshot(
        controller: _screenshotController,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              // Status Indicator
              _buildStatusIndicator(),
              const SizedBox(height: 20),

              // Text Display
              TextField(
                controller: _textController,
                decoration: const InputDecoration(
                  labelText: 'Conversation Log', // Updated label
                  border: OutlineInputBorder(),
                ),
                minLines: 5,
                maxLines: 10,
                readOnly: true, // Make read-only as input is via voice
              ),
              const SizedBox(height: 20),

              // --- Voice ID Input ---
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _voiceIdController,
                      decoration: const InputDecoration(
                        labelText: 'ElevenLabs Voice ID',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: () {
                      final newVoiceId = _voiceIdController.text.trim();
                      _elevenLabsService.setVoice(newVoiceId);
                      // Optional: Show feedback
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Voice ID set to: $newVoiceId')),
                      );
                      // Hide keyboard
                      FocusScope.of(context).unfocus();
                    },
                    child: const Text('Set Voice'),
                  ),
                ],
              ),
              // --- End Voice ID Input ---

              const SizedBox(height: 20), // Add some spacing
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusIndicator() {
    IconData icon;
    Color color;
    String text;

    switch (_appState) {
      case AppState.idle:
        icon = Icons.mic_off;
        color = Colors.grey;
        text = "Idle (Tap to start)"; // Or auto-start
        break;
      case AppState.listening:
        icon = Icons.mic;
        color = Colors.blue;
        text = "Listening...";
        break;
      case AppState.processing_stt:
        icon = Icons.record_voice_over; // Changed icon
        color = Colors.orange;
        text = "Transcribing...";
        break;
      case AppState.processing_gemini: // Added case for Gemini processing
        icon = Icons.smart_toy_outlined;
        color = Colors.purple;
        text = "Thinking...";
        break;
      case AppState.speaking_tts:
        icon = Icons.volume_up;
        color = Colors.green;
        text = "Speaking... (Tap to stop)"; // Indicate tappable
        break;
    }

    // Allow tapping idle state to start listening OR speaking state to stop
    return InkWell(
      onTap: () {
        if (!mounted) return;
        if (_appState == AppState.idle) {
          _startListening();
        } else if (_appState == AppState.speaking_tts) {
          debugPrint("Stop requested via UI tap.");
          _elevenLabsService.stop(); // Stop TTS
          // Explicitly transition state and restart listening
          setState(() {
            _appState = AppState.idle;
          });
          _startListening();
        }
      },
      child: Column(
        children: [
          Icon(icon, size: 40, color: color),
          const SizedBox(height: 8),
          Text(text, style: TextStyle(color: color, fontSize: 16)),
        ],
      ),
    );
  }
}
