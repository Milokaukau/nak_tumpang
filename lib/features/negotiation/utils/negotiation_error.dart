import 'package:flutter/foundation.dart';

/// A failure from a negotiation mutation (propose/accept/reject) that is
/// safe to show directly to the user.
///
/// [cause] and [stackTrace] are kept only for logging/debugging - never
/// display them in the UI, since they may contain raw Supabase/Postgres
/// error details.
class NegotiationException implements Exception {
  final String message;
  final Object? cause;
  final StackTrace? stackTrace;

  NegotiationException(this.message, {this.cause, this.stackTrace});

  @override
  String toString() => message;
}

/// Default user-facing message for unexpected failures (network drop, RLS
/// rejection, unexpected Postgres error, etc). Keep this generic - the
/// caller can pass a more specific [fallbackMessage] where useful.
const String kDefaultNegotiationErrorMessage =
    "Couldn't update the negotiation. Please check your connection and try again.";

/// Runs a negotiation mutation and normalizes failures into a single
/// [NegotiationException] shape, so every call site (propose, accept,
/// reject, the atomic date RPCs, ...) reports errors the same way instead
/// of each button inventing its own try/catch.
///
/// - Validation failures should be raised as [NegotiationException] from
///   inside [action] (e.g. from [DateRangeRules.validate]); those messages
///   are passed straight through unchanged.
/// - Anything else (network error, Postgres/RLS error, ...) is logged via
///   [debugPrint] and rethrown as a [NegotiationException] carrying
///   [fallbackMessage], so the raw error never reaches the UI.
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
