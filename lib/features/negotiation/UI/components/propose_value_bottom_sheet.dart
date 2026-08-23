import 'package:flutter/material.dart';

class ProposeValueBottomSheet extends StatefulWidget {
  final String title;
  final String currentValue;
  final Function(String) onSubmit;

  const ProposeValueBottomSheet({
    super.key,
    required this.title,
    required this.currentValue,
    required this.onSubmit,
  });

  @override
  State<ProposeValueBottomSheet> createState() => _ProposeValueBottomSheetState();
}

class _ProposeValueBottomSheetState extends State<ProposeValueBottomSheet> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Adds padding for the keyboard
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(
        left: 20.0,
        right: 20.0,
        top: 20.0,
        bottom: bottomInset + 20.0,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Propose new ${widget.title}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: widget.title,
            ),
            // Use number keyboard if it's a fee
            keyboardType: widget.title.toLowerCase().contains('fee')
                ? const TextInputType.numberWithOptions(decimal: true)
                : TextInputType.text,
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFB300), // Primary Yellow
                foregroundColor: Colors.black,
              ),
              onPressed: () {
                if (_controller.text.trim().isNotEmpty) {
                  widget.onSubmit(_controller.text.trim());
                  Navigator.pop(context); // Close the bottom sheet
                }
              },
              child: const Text('Submit Proposal'),
            ),
          ),
        ],
      ),
    );
  }
}