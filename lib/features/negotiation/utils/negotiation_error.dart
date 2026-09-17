import 'package:flutter/foundation.dart';

class NegotiationException implements Exception {
  final String message;
  final Object? cause;
  final StackTrace? stackTrace;

  NegotiationException(this.message, {this.cause, this.stackTrace});

  @override
  String toString() => message;
}

const String kDefaultNegotiationErrorMessage =
    "Couldn't update the negotiation. Please check your connection and try again.";

Future<T> runNegotiationAction<T>(
    Future<T> Function() action, {
      String fallbackMessage = kDefaultNegotiationErrorMessage,
    }) async {
  try {
    return await action();
  } on NegotiationException {
    rethrow;
  } catch (e, stack) {
    debugPrint('Negotiation action failed: $e\n$stack');
    throw NegotiationException(fallbackMessage, cause: e, stackTrace: stack);
  }
}