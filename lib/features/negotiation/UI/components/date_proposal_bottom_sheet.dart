import 'package:flutter/material.dart';

// Ensure this is inside a StatefulWidget so you can update the UI
class DateProposalBottomSheet extends StatefulWidget {
  final String initialDate; // e.g., "2026-09-01"

  const DateProposalBottomSheet({super.key, required this.initialDate});

  @override
  State<DateProposalBottomSheet> createState() => _DateProposalBottomSheetState();
}

class _DateProposalBottomSheetState extends State<DateProposalBottomSheet> {
  late TextEditingController _dateController;

  @override
  void initState() {
    super.initState();
    _dateController = TextEditingController(text: widget.initialDate);
  }

  @override
  void dispose() {
    _dateController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    // Parse the current date or default to today if parsing fails
    DateTime initial = DateTime.tryParse(_dateController.text) ?? DateTime.now();

    // Ensure initialDate is not before firstDate to prevent crashes
    if (initial.isBefore(DateTime.now())) {
      initial = DateTime.now();
    }

    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now(), // Enforces >= sysdate
      lastDate: DateTime.now().add(const Duration(days: 365)), // 1 year into the future
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.amber, // Matches your app's yellow theme
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (pickedDate != null) {
      // Format to yyyy-MM-dd
      final String formattedDate =
          "${pickedDate.year}-${pickedDate.month.toString().padLeft(2, '0')}-${pickedDate.day.toString().padLeft(2, '0')}";

      setState(() {
        _dateController.text = formattedDate;
      });
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
            'Propose new Start Date',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),

          // The Calendar Picker Field
          TextFormField(
            controller: _dateController,
            readOnly: true, // Prevents manual typing
            onTap: () => _selectDate(context),
            decoration: const InputDecoration(
              labelText: 'Start Date',
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
                // Submit _dateController.text to ViewModel
                Navigator.pop(context, _dateController.text);
              },
              child: const Text('Submit Proposal'),
            ),
          ),
        ],
      ),
    );
  }
}