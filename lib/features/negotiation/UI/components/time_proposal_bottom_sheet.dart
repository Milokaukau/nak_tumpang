import 'package:flutter/material.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';

class TimeProposalBottomSheet extends StatefulWidget {
  final String initialTime;

  const TimeProposalBottomSheet({super.key, required this.initialTime});

  @override
  State<TimeProposalBottomSheet> createState() => _TimeProposalBottomSheetState();
}

class _TimeProposalBottomSheetState extends State<TimeProposalBottomSheet> {
  late TimeOfDay _selectedTime;

  @override
  void initState() {
    super.initState();
    _selectedTime = _parseTime(widget.initialTime);
  }

  TimeOfDay _parseTime(String value) {
    final parts = value.split(':');
    if (parts.length >= 2) {
      final hour = int.tryParse(parts[0]);
      final minute = int.tryParse(parts[1]);
      if (hour != null && minute != null) {
        return TimeOfDay(hour: hour, minute: minute);
      }
    }
    return TimeOfDay.now();
  }

  // Format exactly for the UI display (e.g. "08:00 AM")
  String _formatAmPm(TimeOfDay t) {
    final int hour = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final String period = t.period == DayPeriod.am ? 'AM' : 'PM';
    final String minute = t.minute.toString().padLeft(2, '0');
    return '$hour:$minute $period';
  }

  // Format exactly for the Supabase database (e.g. "08:00:00")
  String _formatDatabase(TimeOfDay t) =>
      "${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00";

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      builder: (context, child) {
        // Force AM/PM mode by overriding MediaQuery
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
          child: Theme(
            data: Theme.of(context).copyWith(
              colorScheme: const ColorScheme.light(
                primary: AppColors.primaryYellow,
                onPrimary: Colors.white,
                onSurface: Colors.black,
              ),
            ),
            child: child!,
          ),
        );
      },
    );

    if (picked != null) {
      setState(() => _selectedTime = picked);
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
            'Propose new Pickup Time',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),

          InkWell(
            onTap: _pickTime,
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Pickup Time',
                border: OutlineInputBorder(),
                suffixIcon: Icon(Icons.access_time, color: Colors.grey),
              ),
              // Display in enforced AM/PM format
              child: Text(_formatAmPm(_selectedTime), style: const TextStyle(fontSize: 16)),
            ),
          ),

          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryYellow,
                foregroundColor: AppColors.black,
              ),
              onPressed: () {
                // Submit the backend 24-hour format to the database
                Navigator.pop(context, _formatDatabase(_selectedTime));
              },
              child: const Text('Submit Proposal'),
            ),
          ),
        ],
      ),
    );
  }
}