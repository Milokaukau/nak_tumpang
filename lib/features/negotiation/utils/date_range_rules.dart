/// Centralizes the "Tumpang subscription must be at least 1 month" rule.
///
/// Previously this math lived only inside [DateRangeProposalBottomSheet]
/// (`_addOneMonth`), which meant the UI could enforce a slightly different
/// definition of "1 month" than the ViewModel/service layer, and a client
/// that bypassed the picker (or a future caller) could send an invalid
/// range straight to Supabase. Both the bottom sheet and
/// [NegotiationViewModel] now call into this single implementation.
class DateRangeRules {
  DateRangeRules._();

  /// Adds one calendar month to [date], clamping the day of month for
  /// target months that are shorter (e.g. 31 Jan -> 28/29 Feb).
  static DateTime addOneMonth(DateTime date) {
    final year = date.month == 12 ? date.year + 1 : date.year;
    final month = date.month == 12 ? 1 : date.month + 1;
    final daysInTargetMonth = DateTime(year, month + 1, 0).day;
    final day = date.day > daysInTargetMonth ? daysInTargetMonth : date.day;
    return DateTime(year, month, day);
  }

  /// The earliest valid end date for a subscription starting on [start].
  static DateTime minEndDate(DateTime start) => addOneMonth(start);

  /// True if [end] satisfies the "at least 1 month" rule relative to
  /// [start]. Also false for a reversed range (end before start).
  static bool isAtLeastOneMonth(DateTime start, DateTime end) {
    if (end.isBefore(start)) return false;
    return !end.isBefore(minEndDate(start));
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
    if (!isAtLeastOneMonth(start, end)) {
      return 'Tumpang subscription must be at least 1 month long.';
    }
    return null;
  }
}
