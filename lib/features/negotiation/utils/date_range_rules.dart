/// Centralizes the "Tumpang subscription must be at least 2 weeks" rule.
///
/// Previously this math lived only inside [DateRangeProposalBottomSheet],
/// which meant the UI could enforce a slightly different
/// definition than the ViewModel/service layer, and a client
/// that bypassed the picker (or a future caller) could send an invalid
/// range straight to Supabase. Both the bottom sheet and
/// [NegotiationViewModel] now call into this single implementation.
class DateRangeRules {
  DateRangeRules._();

  static const int minDays = 14;

  /// Adds exactly 2 weeks (14 days) to [date].
  static DateTime addTwoWeeks(DateTime date) {
    return DateTime(date.year, date.month, date.day).add(const Duration(days: minDays));
  }

  /// The earliest valid end date for a subscription starting on [start].
  static DateTime minEndDate(DateTime start) => addTwoWeeks(start);

  /// True if [end] satisfies the "at least 2 weeks" rule relative to
  /// [start]. Also false for a reversed range (end before start).
  static bool isAtLeastTwoWeeks(DateTime start, DateTime end) {
    if (end.isBefore(start)) return false;

    // Normalize to midnight to avoid time-of-day math errors
    final s = DateTime(start.year, start.month, start.day);
    final e = DateTime(end.year, end.month, end.day);

    return e.difference(s).inDays >= minDays;
  }

  /// Validates a proposed [start]/[end] pair.
  ///
  /// Returns a short, user-facing error message if the range is invalid,
  /// or `null` if the range is valid. Callers (ViewModel, service) should
  /// treat a non-null result as a hard rejection - do not send the mutation
  /// to Supabase.
  static String? validate(DateTime start, DateTime end) {
    if (end.isBefore(start)) {
      return 'The end date cannot be before the start date.';
    }
    if (!isAtLeastTwoWeeks(start, end)) {
      return 'Tumpang subscription must be at least 2 weeks (14 days) long.';
    }
    return null;
  }
}