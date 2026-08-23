import 'package:flutter/material.dart';

class NegotiationFieldRow extends StatelessWidget {
  final String title;
  final String value;
  final bool isAccepted;
  final bool isRequestedByMe;
  final VoidCallback onAccept;
  final VoidCallback onPropose;

  const NegotiationFieldRow({
    super.key,
    required this.title,
    required this.value,
    required this.isAccepted,
    required this.isRequestedByMe,
    required this.onAccept,
    required this.onPropose,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title (e.g., "Tumpang Fee")
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 4),

          // Current Value (e.g., "RM 60.00")
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),

          // Logic for what to show at the bottom of the row
          if (isAccepted)
            const Text(
              '✓ Accepted',
              style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
            )
          else if (isRequestedByMe)
            const Text(
              '(Waiting for Acceptance)',
              style: TextStyle(color: Colors.orange, fontStyle: FontStyle.italic),
            )
          else
            Row(
              children: [
                OutlinedButton(
                  onPressed: onPropose,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.black,
                    side: const BorderSide(color: Colors.black),
                  ),
                  child: const Text('Propose another'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: onAccept,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Accept'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}