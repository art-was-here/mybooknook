import 'package:flutter/material.dart';

class ErrorService {
  static String? _errorMessage;

  static String? get errorMessage => _errorMessage;

  static void setError(String message) {
    _errorMessage = message;
  }

  static void clearError() {
    _errorMessage = null;
  }

  static Widget buildErrorWidget(BuildContext context, {Color? color}) {
    if (_errorMessage == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Container(
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color:
              (color ?? Theme.of(context).colorScheme.error).withOpacity(0.1),
          borderRadius: BorderRadius.circular(8.0),
          border: Border.all(
            color: color ?? Theme.of(context).colorScheme.error,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.error_outline,
              color: color ?? Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: 8.0),
            Expanded(
              child: Text(
                _errorMessage!,
                style: TextStyle(
                  color: color ?? Theme.of(context).colorScheme.error,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              color: color ?? Theme.of(context).colorScheme.error,
              onPressed: clearError,
            ),
          ],
        ),
      ),
    );
  }
}
