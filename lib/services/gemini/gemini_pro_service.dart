import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

class GeminiProService {
  // WARNING: Storing API keys directly in source code is insecure for production apps.
  // Consider using environment variables, a configuration file, or a secrets manager.
  final String _apiKey =
      'AIzaSyB3BzS-5pWxaBt6sB1HR3T1YEWcLP_qw80'; // Replace with your actual key if needed
  late final GenerativeModel _model;

  GeminiProService() {
    _model = GenerativeModel(
      // Use gemini-1.5-flash for faster, potentially less capable responses,
      // or gemini-1.5-pro for more capable but potentially slower responses.
      // Ensure the model you choose supports multimodal input (image + text).
      // gemini-pro (the default text-only model) WILL NOT WORK here.
      model: 'gemini-1.5-flash-latest', // Or 'gemini-1.5-pro-latest'
      apiKey: _apiKey,
    );
  }

  Future<String?> generateContentWithImage({
    required String textPrompt,
    required Uint8List imageBytes,
  }) async {
    try {
      debugPrint("Sending prompt and image to Gemini Pro...");

      // Create the image part
      final imagePart = DataPart(
          'image/png', imageBytes); // Assuming PNG format from screenshot

      // Define the system instruction
      const systemInstruction =
          "You are a helpful assistant. Briefly respond to the following user query, considering the context from the provided image if relevant.";
      final systemPart = TextPart(systemInstruction);

      // Create the user's text part
      final userTextPart = TextPart(textPrompt);

      // Combine parts into a structured prompt list
      final prompt = [
        // System instruction first (implicitly user role for initial turn)
        Content.text(systemInstruction),
        // Then the user's multimodal input
        Content.multi([userTextPart, imagePart])
      ];

      // Send the request to the model
      final response = await _model.generateContent(prompt);

      debugPrint("Gemini Pro response received.");
      // Check for safety ratings if needed
      // if (response.promptFeedback?.blockReason != null) {
      //   debugPrint('Blocked due to: ${response.promptFeedback?.blockReason}');
      //   return 'Response blocked due to safety concerns.';
      // }

      return response.text;
    } catch (e) {
      debugPrint('Error calling Gemini Pro API: $e');
      // Consider more specific error handling (e.g., API key issues, network errors)
      return 'Error generating response: ${e.toString()}';
    }
  }
}
