class DateRangeRules {
  DateRangeRules._();

  static const int minDays = 14;

  static DateTime addTwoWeeks(DateTime date) {
    return DateTime(date.year, date.month, date.day).add(const Duration(days: minDays));
  }

  static DateTime minEndDate(DateTime start) => addTwoWeeks(start);

  static bool isAtLeastTwoWeeks(DateTime start, DateTime end) {
    if (end.isBefore(start)) return false;

    final s = DateTime(start.year, start.month, start.day);
    final e = DateTime(end.year, end.month, end.day);

    return e.difference(s).inDays >= minDays;
  }

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