import 'package:flutter/material.dart';

/// Lets the user propose a Tumpang start + end date together.
/// Rules:
/// - Picking a start date auto-sets the end date to (start + 1 month).
/// - The end date calendar disables (greys out) any date before
///   (start + 1 month) — the subscription must be at least 1 month.
/// - Dates beyond 1 month are freely selectable.
class DateRangeProposalBottomSheet extends StatefulWidget {
  final String initialStartDate; // e.g. "2026-09-04"
  final String initialEndDate;   // e.g. "2026-10-04"

  const DateRangeProposalBottomSheet({
    super.key,
    required this.initialStartDate,
    required this.initialEndDate,
  });

  @override
  State<DateRangeProposalBottomSheet> createState() => _DateRangeProposalBottomSheetState();
}

class _DateRangeProposalBottomSheetState extends State<DateRangeProposalBottomSheet> {
  late DateTime _startDate;
  late DateTime _endDate;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _startDate = DateTime.tryParse(widget.initialStartDate) ?? today;
    if (_startDate.isBefore(today)) _startDate = today;

    final parsedEnd = DateTime.tryParse(widget.initialEndDate);
    final minEnd = _addOneMonth(_startDate);
    _endDate = (parsedEnd != null && !parsedEnd.isBefore(minEnd)) ? parsedEnd : minEnd;
  }

  /// Adds one calendar month, safely clamping the day (e.g. 31 Jan -> 28/29 Feb).
  DateTime _addOneMonth(DateTime d) {
    final year = d.month == 12 ? d.year + 1 : d.year;
    final month = d.month == 12 ? 1 : d.month + 1;
    final daysInTargetMonth = DateTime(year, month + 1, 0).day;
    final day = d.day > daysInTargetMonth ? daysInTargetMonth : d.day;
    return DateTime(year, month, day);
  }

  String _format(DateTime d) =>
      "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

  ThemeData _yellowTheme(BuildContext context) => Theme.of(context).copyWith(
    colorScheme: const ColorScheme.light(
      primary: Colors.amber,
      onPrimary: Colors.white,
      onSurface: Colors.black,
    ),
  );

  Future<void> _pickStartDate() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate.isBefore(today) ? today : _startDate,
      firstDate: today,
      lastDate: today.add(const Duration(days: 730)),
      builder: (context, child) => Theme(data: _yellowTheme(context), child: child!),
    );

    if (picked != null) {
      setState(() {
        _startDate = picked;
        // Auto-set end date to exactly 1 month out whenever start date changes.
        _endDate = _addOneMonth(picked);
      });
    }
  }

  Future<void> _pickEndDate() async {
    final minEnd = _addOneMonth(_startDate);
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate.isBefore(minEnd) ? minEnd : _endDate,
      firstDate: minEnd, // anything earlier than +1 month is greyed out / unselectable
      lastDate: _startDate.add(const Duration(days: 730)),
      builder: (context, child) => Theme(data: _yellowTheme(context), child: child!),
    );

    if (picked != null) {
      setState(() => _endDate = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Propose Tumpang Dates',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'Subscription must be at least 1 month.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 16),

          TextFormField(
            readOnly: true,
            onTap: _pickStartDate,
            controller: TextEditingController(text: _format(_startDate)),
            decoration: const InputDecoration(
              labelText: 'Start Date',
              border: OutlineInputBorder(),
              suffixIcon: Icon(Icons.calendar_today, color: Colors.grey),
            ),
          ),
          const SizedBox(height: 16),

          TextFormField(
            readOnly: true,
            onTap: _pickEndDate,
            controller: TextEditingController(text: _format(_endDate)),
            decoration: const InputDecoration(
              labelText: 'End Date',
              border: OutlineInputBorder(),
              suffixIcon: Icon(Icons.calendar_today, color: Colors.grey),
            ),
          ),

          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                foregroundColor: Colors.black,
              ),
              onPressed: () {
                Navigator.pop(context, {
                  'start': _format(_startDate),
                  'end': _format(_endDate),
                });
              },
              child: const Text('Submit Proposal'),
            ),
          ),
        ],
      ),
    );
  }
}