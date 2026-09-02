class Payment {
  final String id;
  final String subscriptionId;
  final String direction;
  final double amount;
  final DateTime dueDate;
  final DateTime? paidAt;
  final String dateRange;
  final int month;
  final int year;

  Payment({
    required this.id,
    required this.subscriptionId,
    required this.direction,
    required this.amount,
    required this.dueDate,
    this.paidAt,
    required this.dateRange,
    required this.month,
    required this.year,
  });

  bool get isPaid => paidAt != null;

  factory Payment.fromJson(Map<String, dynamic> json) {
    final sub = json['tumpang_subscription'] as Map<String, dynamic>?;

    String derivedDirection = 'Tumpang Subscription';
    if (sub != null && sub['pickup_location'] != null && sub['dropoff_location'] != null) {
      derivedDirection = '${sub['pickup_location']} → ${sub['dropoff_location']}';
    } else if (json['direction'] != null) {
      derivedDirection = json['direction'].toString();
    }

    final m = json['month'] is int ? json['month'] as int : int.tryParse(json['month']?.toString() ?? '1') ?? 1;
    final y = json['year'] is int ? json['year'] as int : int.tryParse(json['year']?.toString() ?? '2026') ?? 2026;

    final monthNames = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final monthLabel = (m >= 1 && m <= 12) ? monthNames[m - 1] : 'Month $m';

    return Payment(
      id: json['id']?.toString() ?? '',
      subscriptionId: json['tumpang_subscription_id']?.toString() ?? '',
      direction: derivedDirection,
      amount: json['amount'] != null ? double.parse(json['amount'].toString()) : 0.0,
      dueDate: json['due_date'] != null
          ? DateTime.parse(json['due_date'].toString())
          : DateTime.now(),
      paidAt: json['paid_at'] != null ? DateTime.parse(json['paid_at'].toString()) : null,
      dateRange: json['date_range']?.toString() ?? '$monthLabel $y Billing',
      month: m,
      year: y,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'tumpang_subscription_id': subscriptionId,
      'amount': amount,
      'due_date': dueDate.toIso8601String(),
      'paid_at': paidAt?.toIso8601String(),
      'month': month,
      'year': year,
    };
  }
}