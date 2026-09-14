import 'package:flutter/material.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/core/components/base_button.dart';
import 'package:nak_tumpang/features/negotiation/utils/negotiation_error.dart';

class ProposeValueBottomSheet extends StatefulWidget {
  final String title;
  final String currentValue;

  /// NOTE: this is awaited by the sheet before it closes (previously it
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
  /// Every caller of this sheet that I can see only ever uses it for the
  /// fee field — pickup/dropoff go through MapScreen, pickup time through
  /// TimeProposalBottomSheet, dates through DateRangeProposalBottomSheet.
  /// Detecting fee by title (same convention the old keyboardType/
  /// validation logic already used) keeps the free-text path available as
  /// a fallback for any other caller I don't have visibility into, rather
  /// than assuming this sheet is fee-only and deleting that path outright.
  bool get _isFee => widget.title.toLowerCase().contains('fee');

  static const int _minFee = 1; // RM1 floor — a fee can't be zero or negative

  // Fee mode state: Now a double to preserve incoming legacy fractional fees
  late double _feeValue;

  // Non-fee fallback mode state.
  late TextEditingController _controller;

  bool _isSubmitting = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    if (_isFee) {
      final parsed = double.tryParse(widget.currentValue);
      // Preserve fractional values on load, do not use .round()
      _feeValue = parsed ?? _minFee.toDouble();
      if (_feeValue < _minFee) _feeValue = _minFee.toDouble();
    } else {
      _controller = TextEditingController(text: widget.currentValue);
    }
  }

  @override
  void dispose() {
    if (!_isFee) _controller.dispose();
    super.dispose();
  }

  void _incrementFee() {
    if (_isSubmitting) return;
    setState(() {
      // Snaps to the next whole integer if fractional, or adds exactly 1.0
      _feeValue = (_feeValue + 1.0).floorToDouble();
    });
  }

  void _decrementFee() {
    if (_isSubmitting || _feeValue <= _minFee) return;
    setState(() {
      // Snaps down to the nearest whole integer, or subtracts exactly 1.0
      _feeValue = (_feeValue - 1.0).ceilToDouble();
      if (_feeValue < _minFee) _feeValue = _minFee.toDouble();
    });
  }

  // Formats correctly based on whether the number is currently fractional or whole
  String get _formattedFee {
    return _feeValue == _feeValue.truncateToDouble()
        ? _feeValue.toStringAsFixed(0)
        : _feeValue.toStringAsFixed(2);
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;

    final String value;
    if (_isFee) {
      value = _formattedFee;
    } else {
      value = _controller.text.trim();
      if (value.isEmpty) {
        const message = 'Please enter a value before submitting.';
        setState(() => _errorText = message);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(message), backgroundColor: Colors.red),
        );
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
          const SizedBox(height: 20),

          if (_isFee) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _StepButton(
                  icon: Icons.remove,
                  onPressed: (_isSubmitting || _feeValue <= _minFee) ? null : _decrementFee,
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        'RM $_formattedFee',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold, color: AppColors.black),
                      ),
                      const SizedBox(height: 2),
                      const Text('per day', style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
                _StepButton(
                  icon: Icons.add,
                  onPressed: _isSubmitting ? null : _incrementFee,
                ),
              ],
            ),
          ] else ...[
            TextField(
              controller: _controller,
              enabled: !_isSubmitting,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: widget.title,
              ),
            ),
          ],

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

/// Round +/- tap target used by the fee stepper, styled to match the
/// app's existing yellow-accent circular/pill button convention.
class _StepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;

  const _StepButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null;
    return Material(
      color: enabled ? AppColors.primaryYellow : Colors.grey.shade200,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(icon, color: enabled ? AppColors.black : Colors.grey, size: 26),
        ),
      ),
    );
  }
}