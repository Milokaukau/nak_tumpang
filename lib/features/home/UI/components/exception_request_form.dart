import 'package:flutter/material.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/core/components/base_button.dart';

class ExceptionRequestForm extends StatelessWidget {
  final String dateRangeLabel;
  final DateTime? startDate;
  final DateTime? endDate;
  final ValueChanged<DateTime> onStartDateChanged;
  final ValueChanged<DateTime> onEndDateChanged;
  final List<String> reasonOptions;
  final String? selectedReason;
  final ValueChanged<String?> onReasonChanged;
  final TextEditingController customReasonController;
  final Color infoBoxColor;
  final Color infoBoxTextColor;
  final String infoBoxText;
  final String confirmLabel;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;
  final bool isSubmitting;
  final DateTime? minDate;
  final DateTime? maxDate;
  final ValueChanged<String> onDateError;
  final String? errorText;

  final List<String> emergencyReasons;

  const ExceptionRequestForm({
    super.key,
    required this.dateRangeLabel,
    required this.startDate,
    required this.endDate,
    required this.onStartDateChanged,
    required this.onEndDateChanged,
    required this.reasonOptions,
    required this.selectedReason,
    required this.onReasonChanged,
    required this.customReasonController,
    required this.infoBoxColor,
    required this.infoBoxTextColor,
    required this.infoBoxText,
    required this.confirmLabel,
    required this.onCancel,
    required this.onConfirm,
    required this.onDateError,
    this.errorText,
    this.isSubmitting = false,
    this.minDate,
    this.maxDate,
    this.emergencyReasons = const [],
  });

  bool get _isEmergency => selectedReason != null && emergencyReasons.contains(selectedReason);

  DateTime _minLeadDate() {
    final today = DateTime.now();
    final todayDateOnly = DateTime(today.year, today.month, today.day);
    return _isEmergency ? todayDateOnly : todayDateOnly.add(const Duration(days: 1));
  }

  Future<void> _pickDate(BuildContext context, bool isStart) async {
    final minLeadDate = _minLeadDate();

    final effectiveFirstDate = (minDate != null && minDate!.isAfter(minLeadDate))
        ? minDate!
        : minLeadDate;

    final effectiveLastDate = maxDate ?? DateTime(2100);

    if (effectiveLastDate.isBefore(effectiveFirstDate)) {
      onDateError('No valid dates are available to select.');
      return;
    }

    final rawInitial = (isStart ? startDate : endDate) ?? effectiveFirstDate;
    DateTime initial = rawInitial;
    if (initial.isBefore(effectiveFirstDate)) initial = effectiveFirstDate;
    if (initial.isAfter(effectiveLastDate)) initial = effectiveLastDate;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: effectiveFirstDate,
      lastDate: effectiveLastDate,
      locale: const Locale('en', 'GB'),
    );

    if (picked != null) {
      final purePicked = DateTime(picked.year, picked.month, picked.day);

      if (minDate != null && maxDate != null) {
        final pureMin = DateTime(minDate!.year, minDate!.month, minDate!.day);
        final pureMax = DateTime(maxDate!.year, maxDate!.month, maxDate!.day);

        if (purePicked.isBefore(pureMin) || purePicked.isAfter(pureMax)) {
          onDateError('Date must be within the subscription period (${_formatDate(minDate)} - ${_formatDate(maxDate)}).');
          return;
        }
      }

      if (!isStart && startDate != null) {
        final pureStart = DateTime(startDate!.year, startDate!.month, startDate!.day);
        if (purePicked.isBefore(pureStart)) {
          onDateError('End date cannot be before the start date.');
          return;
        }
      }

      isStart ? onStartDateChanged(picked) : onEndDateChanged(picked);
    }
  }

  void _handleConfirm() {
    if (startDate != null) {
      final pureStart = DateTime(startDate!.year, startDate!.month, startDate!.day);
      final minLeadDate = _minLeadDate();

      if (pureStart.isBefore(minLeadDate)) {
        onDateError(_isEmergency
            ? 'Start date cannot be before today.'
            : 'Exceptions must be requested at least 1 day in advance. '
            'Select an emergency reason if you need to request for today.');
        return;
      }
    }
    onConfirm();
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'dd/mm/yyyy';
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(dateRangeLabel,
            style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.greyText)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _DateField(label: _formatDate(startDate), onTap: () => _pickDate(context, true))),
            const SizedBox(width: 12),
            Expanded(child: _DateField(label: _formatDate(endDate), onTap: () => _pickDate(context, false))),
          ],
        ),
        const SizedBox(height: 20),
        const Text('Reason', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.greyText)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.lightYellow,
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: selectedReason,
              hint: const Text('Select a reason'),
              items: reasonOptions.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
              onChanged: onReasonChanged,
            ),
          ),
        ),
        if (emergencyReasons.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            'Same-day requests are only allowed for: ${emergencyReasons.join(', ')}.',
            style: const TextStyle(fontSize: 11, color: AppColors.greyText, fontStyle: FontStyle.italic),
          ),
        ],
        if (selectedReason == 'Others') ...[
          const SizedBox(height: 12),
          TextField(
            controller: customReasonController,
            maxLength: 250,
            maxLines: 4,
            minLines: 3,
            decoration: InputDecoration(
              hintText: 'Tell us why',
              filled: true,
              fillColor: AppColors.lightYellow,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: infoBoxColor, borderRadius: BorderRadius.circular(8)),
          child: Text(infoBoxText, style: TextStyle(color: infoBoxTextColor)),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Text(
              errorText!,
              style: TextStyle(color: Colors.red.shade700, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: isSubmitting ? null : onCancel,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: const BorderSide(color: AppColors.greyBorder),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Cancel', style: TextStyle(color: AppColors.greyText)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: BaseButton(
                text: isSubmitting ? 'Submitting...' : confirmLabel,
                onPressed: isSubmitting ? () {} : _handleConfirm,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _DateField({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(color: AppColors.lightYellow, borderRadius: BorderRadius.circular(8)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: AppColors.greyText)),
            const Icon(Icons.calendar_today, size: 16, color: AppColors.greyText),
          ],
        ),
      ),
    );
  }
}