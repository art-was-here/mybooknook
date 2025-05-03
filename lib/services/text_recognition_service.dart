import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

class TextRecognitionService {
  static Future<String?> scanISBN() async {
    try {
      // Check camera permission
      final status = await Permission.camera.request();
      if (status.isDenied) {
        throw Exception('Camera permission denied');
      }

      // Pick an image from the camera
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        imageQuality: 100,
        maxWidth: 1920, // Higher resolution for better text recognition
        maxHeight: 1080,
      );

      if (image == null) {
        throw Exception('No image selected');
      }

      print('Image captured successfully: ${image.path}');

      // Create an InputImage from the picked image
      final inputImage = InputImage.fromFilePath(image.path);

      // Initialize the text recognizer
      final textRecognizer = TextRecognizer();

      try {
        // Process the image
        final recognizedText = await textRecognizer.processImage(inputImage);
        print('\n=== Text Recognition Debug ===');
        print('Full recognized text: "${recognizedText.text}"');
        print('Text length: ${recognizedText.text.length}');
        print('Text lines:');
        recognizedText.text.split('\n').forEach((line) => print('  "$line"'));

        // Preprocess the text to improve ISBN detection
        String processedText = recognizedText.text;

        // Remove common OCR artifacts
        processedText = processedText
            .replaceAll(RegExp(r'[|]'), '1') // Replace vertical bars with 1
            .replaceAll(RegExp(r'[l]'), '1') // Replace lowercase L with 1
            .replaceAll(RegExp(r'[O]'), '0') // Replace uppercase O with 0
            .replaceAll(RegExp(r'[o]'), '0') // Replace lowercase o with 0
            .replaceAll(RegExp(r'[I]'), '1') // Replace uppercase I with 1
            .replaceAll(RegExp(r'[B]'), '8') // Replace uppercase B with 8
            .replaceAll(RegExp(r'[b]'), '6') // Replace lowercase b with 6
            .replaceAll(RegExp(r'[S]'), '5') // Replace uppercase S with 5
            .replaceAll(RegExp(r'[s]'), '5') // Replace lowercase s with 5
            .replaceAll(RegExp(r'[Z]'), '2') // Replace uppercase Z with 2
            .replaceAll(RegExp(r'[z]'), '2'); // Replace lowercase z with 2

        // Normalize spaces and hyphens
        processedText = processedText
            .replaceAll(RegExp(r'\s+'), ' ') // Normalize multiple spaces
            .replaceAll(
                RegExp(r'[-–—]'), '-') // Normalize different types of hyphens
            .replaceAll(RegExp(r'[.]'), '') // Remove periods
            .replaceAll(RegExp(r'[,]'), ''); // Remove commas

        print('\nProcessed text: "$processedText"');

        // Look for ISBN in various formats
        final isbnPatterns = [
          // ISBN with "ISBN" prefix and any format
          RegExp(r'ISBN[- ]*([0-9]{10,13})', caseSensitive: false),
          RegExp(
              r'ISBN[- ]*([0-9]{1,5}[- ]?[0-9]{1,7}[- ]?[0-9]{1,6}[- ]?[0-9])',
              caseSensitive: false),

          // ISBN-10 patterns
          RegExp(r'\b[0-9]-[0-9]{3}-[0-9]{5}-[0-9]\b'),
          RegExp(r'\b[0-9]{1,5}[- ]?[0-9]{1,7}[- ]?[0-9]{1,6}[- ]?[0-9]\b'),

          // ISBN-13 patterns
          RegExp(
              r'\b(?:978|979)[- ]?[0-9]{1,5}[- ]?[0-9]{2,7}[- ]?[0-9]{1,6}[- ]?[0-9]\b'),

          // Any 10 or 13 digit number
          RegExp(r'\b\d{10}\b'),
          RegExp(r'\b\d{13}\b'),

          // More flexible patterns
          RegExp(r'\b[0-9]{9,13}\b'), // Any 9-13 digit number
          RegExp(
              r'\b[0-9]{1,5}[- ]?[0-9]{1,7}[- ]?[0-9]{1,6}[- ]?[0-9]\b'), // Any number with hyphens
        ];

        print('\n=== Pattern Matching Debug ===');
        for (final pattern in isbnPatterns) {
          print('\nTrying pattern: ${pattern.pattern}');
          final matches = pattern.allMatches(processedText);
          print('Found ${matches.length} matches');

          for (final match in matches) {
            print('  Match: "${match.group(0)}"');
            try {
              // Get the full match first
              String? isbn = match.group(0);

              // If the pattern has a capture group, try to get that
              if (pattern.pattern.contains('(')) {
                isbn = match.group(1);
              }

              if (isbn == null) {
                print('  Warning: No ISBN found in match');
                continue;
              }

              // Remove any hyphens or spaces from the ISBN
              final cleanIsbn = isbn.replaceAll(RegExp(r'[- ]'), '');
              print('  Cleaned ISBN: $cleanIsbn');

              // Validate the length
              if (cleanIsbn.length != 10 && cleanIsbn.length != 13) {
                print('  Warning: Invalid ISBN length: ${cleanIsbn.length}');
                continue;
              }

              print('  Found valid ISBN: $cleanIsbn');
              return cleanIsbn;
            } catch (e) {
              print('  Error processing match: $e');
              continue;
            }
          }
        }

        // If no ISBN found, print the recognized text for debugging
        print('\n=== No ISBN Found ===');
        print('Original text: "${recognizedText.text}"');
        print('Processed text: "$processedText"');
        print('Text lines:');
        processedText.split('\n').forEach((line) => print('  "$line"'));
        throw Exception('No ISBN found in the image');
      } finally {
        // Clean up
        textRecognizer.close();
      }
    } catch (e) {
      print('Error scanning text: $e');
      rethrow;
    }
  }
}
