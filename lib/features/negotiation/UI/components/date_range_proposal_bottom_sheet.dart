import 'package:flutter/material.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/features/negotiation/utils/date_range_rules.dart';

class DateRangeProposalBottomSheet extends StatefulWidget {
  final String initialStartDate;
  final String initialEndDate;

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
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // 1. Parse Start Date (Default to sysdate if invalid or in the past)
    _startDate = DateTime.tryParse(widget.initialStartDate) ?? today;
    _startDate = DateTime(_startDate.year, _startDate.month, _startDate.day);

    if (_startDate.isBefore(today)) {
      _startDate = today;
    }

    // 2. Parse End Date & Auto-Fill Default (Start + 14 days)
    final parsedEnd = DateTime.tryParse(widget.initialEndDate);
    final twoWeeksLater = DateRangeRules.minEndDate(_startDate); // start + 14 days

    if (parsedEnd != null) {
      final normalizedEnd = DateTime(parsedEnd.year, parsedEnd.month, parsedEnd.day);
      if (normalizedEnd.isBefore(twoWeeksLater)) {
        _endDate = twoWeeksLater;
      } else {
        _endDate = normalizedEnd;
      }
    } else {
      // New Request / First Entry Default: Exactly start + 14 days
      _endDate = twoWeeksLater;
    }
  }

  String _formatDisplay(DateTime d) =>
      "${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}";

  String _formatIso(DateTime d) =>
      "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

  ThemeData _yellowTheme(BuildContext context) => Theme.of(context).copyWith(
    colorScheme: const ColorScheme.light(
      primary: AppColors.primaryYellow,
      onPrimary: Colors.white,
      onSurface: Colors.black,
    ),
  );

  Future<void> _pickStartDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

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
        // Auto-fill exactly 2 weeks out whenever start date is manually changed
        _endDate = DateRangeRules.addTwoWeeks(picked);
      });
    }
  }

  Future<void> _pickEndDate() async {
    final minEnd = DateRangeRules.minEndDate(_startDate);
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate.isBefore(minEnd) ? minEnd : _endDate,
      firstDate: minEnd, // Greys out any date earlier than 2 weeks
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
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.black),
          ),
          const SizedBox(height: 6),
          const Text(
            'Subscription must be at least 2 weeks.',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 18),

          TextFormField(
            readOnly: true,
            onTap: _pickStartDate,
            controller: TextEditingController(text: _formatDisplay(_startDate)),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.black),
            decoration: const InputDecoration(
              labelText: 'Start Date',
              labelStyle: TextStyle(color: Colors.black87),
              border: OutlineInputBorder(),
              suffixIcon: Icon(Icons.calendar_today, color: Colors.black54),
            ),
          ),
          const SizedBox(height: 16),

          TextFormField(
            readOnly: true,
            onTap: _pickEndDate,
            controller: TextEditingController(text: _formatDisplay(_endDate)),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.black),
            decoration: const InputDecoration(
              labelText: 'End Date',
              labelStyle: TextStyle(color: Colors.black87),
              border: OutlineInputBorder(),
              suffixIcon: Icon(Icons.calendar_today, color: Colors.black54),
            ),
          ),

          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryYellow,
                foregroundColor: AppColors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                if (!_endDate.isAfter(_startDate) || !DateRangeRules.isAtLeastTwoWeeks(_startDate, _endDate)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('End date must be at least 14 days after the start date.'), backgroundColor: Colors.red),
                  );
                  return;
                }
                Navigator.pop(context, {
                  'start': _formatIso(_startDate),
                  'end': _formatIso(_endDate),
                });
              },
              child: const Text('Submit Proposal', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
