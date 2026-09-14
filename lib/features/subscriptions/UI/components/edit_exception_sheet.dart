import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/features/home/UI/components/exception_request_form/exception_request_form.dart';
import 'package:nak_tumpang/features/home/view_models/home_view_model.dart';
import 'package:nak_tumpang/features/subscriptions/view_models/subscription_view_model.dart';

class EditExceptionSheet extends StatefulWidget {
  final Map<String, dynamic> exception;
  final VoidCallback onChanged;
  final String otherUserId; // 👈 ADDED THIS
  final DateTime? minDate;
  final DateTime? maxDate;

  const EditExceptionSheet({
    super.key,
    required this.exception,
    required this.onChanged,
    required this.otherUserId, // 👈 ADDED THIS
    this.minDate,
    this.maxDate,
  });

  @override
  State<EditExceptionSheet> createState() => _EditExceptionSheetState();
}

class _EditExceptionSheetState extends State<EditExceptionSheet> {
  DateTime? startDate;
  DateTime? endDate;
  String? reason;
  String? _validationError;
  final TextEditingController customReasonController = TextEditingController();
  bool isSubmitting = false;

  bool get isDriverInitiated => widget.exception['initiated_by_role'] == 'driver';

  @override
  void initState() {
    super.initState();
    startDate = DateTime.tryParse(widget.exception['start_date'] ?? '');
    endDate = DateTime.tryParse(widget.exception['end_date'] ?? '');

    final existingReason = widget.exception['reason'] as String?;
    final knownReasons = isDriverInitiated ? HomeViewModel.driverReasons : HomeViewModel.passengerReasons;
    if (existingReason != null && knownReasons.contains(existingReason)) {
      reason = existingReason;
    } else {
      reason = 'Others';
      customReasonController.text = existingReason ?? '';
    }
  }

  @override
  void dispose() {
    customReasonController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (startDate == null || endDate == null || reason == null) return;
    setState(() => isSubmitting = true);

    final reasonText = reason == 'Others' ? customReasonController.text.trim() : reason!;
    final vm = context.read<SubscriptionViewModel>();

    final success = await vm.updateException(
      exceptionId: widget.exception['id'],
      startDate: startDate!,
      endDate: endDate!,
      reason: reasonText,
      otherUserId: widget.otherUserId,
      subscriptionId: widget.exception['tumpang_subscription_id']?.toString(),
    );

    setState(() => isSubmitting = false);
    if (success && mounted) {
      Navigator.of(context).pop();
      widget.onChanged();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Request updated.')));
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this request?'),
        content: const Text('This will permanently remove this schedule change. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Back')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel Request', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final vm = context.read<SubscriptionViewModel>();
    final success = await vm.cancelException(widget.exception['id']);
    if (success && mounted) {
      Navigator.of(context).pop();
      widget.onChanged();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Request cancelled.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final reasonOptions = isDriverInitiated ? HomeViewModel.driverReasons : HomeViewModel.passengerReasons;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(bottom: 24),
                  height: 4,
                  width: 40,
                  decoration: BoxDecoration(color: AppColors.greyBorder, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const Text('Edit request', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              ExceptionRequestForm(
                dateRangeLabel: isDriverInitiated ? 'Unavailable from' : 'Not needed from',
                startDate: startDate,
                endDate: endDate,
                errorText: _validationError,
                onDateError: (msg) => setState(() => _validationError = msg),
                onStartDateChanged: (d) => setState(() {
                  _validationError = null;
                  startDate = d;
                  if (endDate != null && endDate!.isBefore(d)) endDate = null;
                }),
                onEndDateChanged: (d) => setState(() {
                  _validationError = null;
                  endDate = d;
                }),
                reasonOptions: reasonOptions,
                selectedReason: reason,
                onReasonChanged: (r) => setState(() => reason = r),
                customReasonController: customReasonController,
                infoBoxColor: isDriverInitiated ? AppColors.warningAmberBg : AppColors.successGreenBg,
                infoBoxTextColor: isDriverInitiated ? AppColors.warningAmberText : AppColors.successGreenText,
                infoBoxText: 'Save your changes, or cancel this request entirely below.',
                confirmLabel: 'Save changes',
                isSubmitting: isSubmitting,
                minDate: widget.minDate,
                maxDate: widget.maxDate,
                onCancel: () => Navigator.of(context).pop(),
                onConfirm: _save,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _delete,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: const BorderSide(color: Colors.red),
                  ),
                  child: const Text('Cancel this request', style: TextStyle(color: Colors.red)),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }
}