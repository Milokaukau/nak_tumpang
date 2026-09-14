import 'package:flutter/material.dart';
import 'package:nak_tumpang/core/components/base_button.dart';
import 'package:nak_tumpang/features/negotiation/utils/negotiation_error.dart';

class ProposeValueBottomSheet extends StatefulWidget {
  final String title;
  final String currentValue;

  /// NOTE: this is now awaited by the sheet before it closes (previously it
  /// was fired without awaiting, so the sheet closed immediately and any
  /// failure from the mutation was silently lost). Throw a
  /// [NegotiationException] from here (or let one propagate) to show a
  /// user-facing error in the sheet and keep it open for retry.
  final Future<void> Function(String) onSubmit;

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
  bool _isSubmitting = false;
  String? _errorText;

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

  Future<void> _submit() async {
    if (_isSubmitting) return;
    final value = _controller.text.trim();
    if (value.isEmpty) {
      const message = 'Please enter a value before submitting.';
      setState(() => _errorText = message);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(message), backgroundColor: Colors.red));
      return;
    }
    if (widget.title.toLowerCase().contains('fee')) {
      final fee = double.tryParse(value);
      if (fee == null || fee <= 0) {
        const message = 'Please enter a valid fee greater than RM 0.';
        setState(() => _errorText = message);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(message), backgroundColor: Colors.red));
        return;
      }
    }

    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });

    try {
      await widget.onSubmit(value);
      if (mounted) Navigator.pop(context);
    } on NegotiationException catch (e) {
      if (mounted) setState(() => _errorText = e.message);
    } catch (e) {
      if (mounted) setState(() => _errorText = kDefaultNegotiationErrorMessage);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
            enabled: !_isSubmitting,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: widget.title,
            ),
            keyboardType: widget.title.toLowerCase().contains('fee')
                ? const TextInputType.numberWithOptions(decimal: true)
                : TextInputType.text,
          ),
          if (_errorText != null) ...[
            const SizedBox(height: 8),
            Text(_errorText!, style: const TextStyle(color: Colors.red, fontSize: 13)),
          ],
          const SizedBox(height: 20),

          BaseButton(
            text: _isSubmitting ? 'Submitting...' : 'Submit Proposal',
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}
