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

  // Dynamically parses the raw database row from Supabase
  factory Payment.fromJson(Map<String, dynamic> json) {
    return Payment(
      id: json['id']?.toString() ?? '',
      direction: json['direction']?.toString() ?? 'Tumpang Route',
      amount: json['amount'] != null ? double.parse(json['amount'].toString()) : 0.0,
      dueDate: json['due_date'] != null
          ? DateTime.parse(json['due_date'].toString())
          : DateTime.now(),
      dateRange: json['date_range']?.toString() ??
          'Month: ${json['month'] ?? ''} / ${json['year'] ?? ''}',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'direction': direction,
      'amount': amount,
      'due_date': dueDate.toIso8601String(),
      'date_range': dateRange,
    };
  }
}