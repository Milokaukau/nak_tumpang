import 'package:flutter/material.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';

/// Lets the user propose a new Pickup Time using the native time picker
/// instead of typing it manually. Returns a "HH:mm:00" string via
/// Navigator.pop to match the format already stored in Supabase
/// (e.g. "08:00:00").
class TimeProposalBottomSheet extends StatefulWidget {
  final String initialTime; // e.g. "08:00:00"

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

  String _format(TimeOfDay t) =>
      "${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00";

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primaryYellow,
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
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
              child: Text(_selectedTime.format(context), style: const TextStyle(fontSize: 16)),
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
                Navigator.pop(context, _format(_selectedTime));
              },
              child: const Text('Submit Proposal'),
            ),
          ),
        ],
      ),
    );
  }
}