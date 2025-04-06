import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

// Replace with your actual Deepgram API key
const String _apiKey = 'e4c91b7fdf1d785a034ab20e720afeb0230ee7e3';

// Deepgram WebSocket URL with desired parameters
const String _dgUrl =
    'wss://api.deepgram.com/v1/listen?encoding=linear16&sample_rate=16000&language=en-US&interim_results=true&vad_events=true&endpointing=300';
    // encoding=linear16: Matches mic_stream output
    // sample_rate=16000: Matches mic_stream output
    // language=en-US: Target language
    // interim_results=true: Get results as they come in
    // vad_events=true: Get VAD events (useful for knowing when speech starts/stops)
    // endpointing=300: Automatically detect end of speech after 300ms of silence

class DeepgramSttService {
  WebSocketChannel? _channel;
  StreamController<Map<String, dynamic>> _transcriptController =
      StreamController.broadcast();
  StreamSubscription? _channelSubscription;

  // Stream for external listeners to get transcription results
  Stream<Map<String, dynamic>> get transcriptStream =>
      _transcriptController.stream;

  bool get isConnected => _channel != null;

  Future<void> connect() async {
    if (_channel != null) {
      debugPrint('Deepgram connection already established.');
      return;
    }

    debugPrint('Connecting to Deepgram...');
    try {
      _channel = IOWebSocketChannel.connect(
        Uri.parse(_dgUrl),
        headers: {'Authorization': 'Token $_apiKey'},
      );

      _channelSubscription = _channel!.stream.listen(
        (event) {
          // Ensure event is a String before decoding
          if (event is String) {
            try {
              final dynamic parsedJson = jsonDecode(event); // Keep dynamic for initial parsing
              // Ensure parsedJson is a Map before adding to controller
              if (parsedJson is Map<String, dynamic>) {
                 // Add the raw JSON event to the stream for the UI to handle
                 if (!_transcriptController.isClosed) {
                   _transcriptController.add(parsedJson); // Now type-safe
                 }
                 // Optional: Log specific parts for debugging
                 if (parsedJson['type'] == 'Results') {
                   // Ensure transcript is treated as String?
                   final dynamic transcriptDynamic = parsedJson['channel']?['alternatives']?[0]?['transcript'];
                   final String? transcript = transcriptDynamic is String ? transcriptDynamic : null;

                   final isFinal = parsedJson['is_final'] as bool? ?? false; // Use 'as bool?' for safety
                   final speechFinal = parsedJson['speech_final'] as bool? ?? false; // Use 'as bool?' for safety

                   // Check type before checking isNotEmpty
                   if (transcript != null && transcript.isNotEmpty) {
                     debugPrint('Deepgram Transcript (final: $isFinal, speech_final: $speechFinal): $transcript');
                   }
                 } else if (parsedJson['type'] == 'Metadata') {
                    debugPrint('Deepgram Metadata: $parsedJson');
                 } else if (parsedJson['type'] == 'SpeechStarted') {
                    debugPrint('Deepgram Speech Started');
                 } else if (parsedJson['type'] == 'UtteranceEnd') {
                    debugPrint('Deepgram Utterance End');
                 } else if (parsedJson['type'] == 'Error') {
                    // Ensure reason is treated as String?
                    final dynamic reasonDynamic = parsedJson['reason'];
                    final String reason = reasonDynamic is String ? reasonDynamic : 'Unknown error reason';
                    debugPrint('Deepgram Error: $reason');
                 }
              } else {
                 debugPrint('Received non-Map JSON from Deepgram: $parsedJson');
              }

            } catch (e, stackTrace) { // Catch stackTrace too
              debugPrint('Error parsing Deepgram message: $e\n$stackTrace');
              // Optionally add error event to stream
              if (!_transcriptController.isClosed) {
                 _transcriptController.addError(e, stackTrace); // Pass the actual error object and stacktrace
              }
            }
          } else {
             debugPrint('Received non-String message from Deepgram: ${event.runtimeType}');
          }
        },
        onDone: () {
          debugPrint('Deepgram connection closed.');
          _handleDisconnect();
        },
        onError: (Object error, StackTrace? stackTrace) { // Explicitly type parameters
          debugPrint('Deepgram connection error: $error\n$stackTrace');
          if (!_transcriptController.isClosed) {
             _transcriptController.addError(error, stackTrace); // Now types match
          }
          _handleDisconnect();
        },
        cancelOnError: true,
      );
      debugPrint('Deepgram connection successful.');
    } catch (e, stackTrace) { // Catch block already has types inferred correctly
      debugPrint('Error connecting to Deepgram: $e\n$stackTrace');
       if (!_transcriptController.isClosed) {
         _transcriptController.addError(e, stackTrace); // Pass the actual error object and stacktrace
       }
      _channel = null; // Ensure channel is null on connection failure
    }
  }

  void sendAudio(Uint8List data) {
    // Use null-aware access for safer check
    if (_channel?.sink != null) {
      // debugPrint('Sending ${data.lengthInBytes} bytes to Deepgram'); // Can be noisy
      _channel!.sink.add(data);
    } else {
      debugPrint('Cannot send audio: Deepgram channel not connected or sink closed.');
    }
  }

  Future<void> close() async {
    debugPrint('Closing Deepgram connection...');
    await _channelSubscription?.cancel();
    await _channel?.sink.close();
    _channel = null;
    _channelSubscription = null;
    // Don't close the controller here if the service might be reused.
    // If the service is meant to be single-use, close it:
    // await _transcriptController.close();
    debugPrint('Deepgram connection resources released.');
  }

  void _handleDisconnect() {
     if (_channel != null) { // Prevent multiple disconnect calls
        debugPrint('Handling Deepgram disconnect.');
        _channelSubscription?.cancel(); // Ensure subscription is cancelled
        _channel = null;
        _channelSubscription = null;
        // Optionally notify listeners about the disconnection
        if (!_transcriptController.isClosed) {
          _transcriptController.add({'type': 'Disconnected'});
        }
     }
  }

  // Optional: Method to properly dispose when the service is no longer needed
  void dispose() {
    close(); // Ensure connection is closed
    _transcriptController.close(); // Close the stream controller
    debugPrint('DeepgramSttService disposed.');
  }
}
