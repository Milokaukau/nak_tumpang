// The shared data blueprint (id, amount, dates). Placed in core so both the Payment feature and a future Payment History feature can access the same data model.

class Payment {
  final String id;
  final String direction;
  final double amount;
  final DateTime dueDate;
  final String dateRange;

  Payment({
    required this.id,
    required this.direction,
    required this.amount,
    required this.dueDate,
    required this.dateRange,
  });
}