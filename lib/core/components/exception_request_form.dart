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
    this.isSubmitting = false,
  });

  Future<void> _pickDate(BuildContext context, bool isStart) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: (isStart ? startDate : endDate) ?? now,
      firstDate: isStart ? now : (startDate ?? now),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) {
      isStart ? onStartDateChanged(picked) : onEndDateChanged(picked);
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'mm/dd/yyyy';
    return '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}/${date.year}';
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
                onPressed: isSubmitting ? () {} : onConfirm,
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