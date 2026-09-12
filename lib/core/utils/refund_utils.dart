class RefundUtils {
  static double calculateRefund({
    required double dailyFee,
    required DateTime exceptionStart,
    required DateTime exceptionEnd,
  }) {
    final exceptionDays = exceptionEnd.difference(exceptionStart).inDays + 1;
    return dailyFee * exceptionDays;
  }
}