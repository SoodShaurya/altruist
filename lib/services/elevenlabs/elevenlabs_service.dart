import 'dart:async';
import 'dart:convert'; // Moved import here
import 'dart:io'; // Added for File operations
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart'; // Added for temporary directory

class ElevenLabsService {
  // WARNING: Hardcoding API keys is insecure. Consider secure storage.
  final String apiKey = 'sk_24bab9041881585d675e2907074990efeb2ffeb7765c415c';
  String voiceId = '21m00Tcm4TlvDq8ikWAM'; // Made non-final to allow changing
  final AudioPlayer _audioPlayer = AudioPlayer();

  // Expose the player complete stream
  Stream<void> get onPlaybackComplete => _audioPlayer.onPlayerComplete;

  Future<void> speak(String text) async {
    if (text.isEmpty) {
      debugPrint('Text cannot be empty');
      return;
    }

    final url = Uri.parse('https://api.elevenlabs.io/v1/text-to-speech/$voiceId/stream');
    final headers = {
      'Accept': 'audio/mpeg',
      'Content-Type': 'application/json',
      'xi-api-key': apiKey, // Use the hardcoded key
    };
    final body = {
      'text': text,
      'model_id': 'eleven_monolingual_v1', // Or another suitable model
      'voice_settings': {
        'stability': 0.5,
        'similarity_boost': 0.75,
      }
    };

    try {
      final response = await http.post(
        url,
        headers: headers,
        body: jsonEncode(body), // Ensure body is JSON encoded
      );

      if (response.statusCode == 200) {
        final Uint8List audioBytes = response.bodyBytes;

        // Get temporary directory
        final tempDir = await getTemporaryDirectory();
        final tempPath = tempDir.path;
        final filePath = '$tempPath/temp_audio_${DateTime.now().millisecondsSinceEpoch}.mp3';
        final file = File(filePath);

        // Write the bytes to the file
        await file.writeAsBytes(audioBytes);
        debugPrint('Audio saved to temporary file: $filePath');

        // Play from the file
        await _audioPlayer.play(DeviceFileSource(filePath));
        debugPrint('Playing audio from file...');

        // Optional: Clean up the file after playback
        _audioPlayer.onPlayerComplete.first.then((_) {
          debugPrint('Playback complete, deleting temporary file: $filePath');
          file.delete().catchError((e) {
            debugPrint('Error deleting temporary file: $e');
          });
        });

      } else {
        debugPrint('ElevenLabs API Error: ${response.statusCode}');
        debugPrint('Response body: ${response.body}');
        // Consider throwing an exception or returning an error state
      }
    } catch (e) {
      debugPrint('Error calling ElevenLabs API: $e');
      // Consider throwing an exception or returning an error state
    }
  }

  // Helper function to encode body (needed because http.post expects String or Uint8List)
  String jsonEncode(Object? object) =>
      const JsonEncoder().convert(object);

  // Method to allow external stopping of playback
  Future<void> stop() async {
    await _audioPlayer.stop();
    debugPrint('ElevenLabs playback stopped externally.');
  }

  // Method to change the voice ID
  void setVoice(String newVoiceId) {
    if (newVoiceId.isNotEmpty) {
      voiceId = newVoiceId;
      debugPrint('ElevenLabs voice changed to: $voiceId');
    } else {
      debugPrint('Attempted to set an empty voice ID.');
    }
  }
}
