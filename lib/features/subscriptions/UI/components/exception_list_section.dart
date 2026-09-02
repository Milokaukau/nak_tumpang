import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/core/components/base_button.dart';
import 'package:nak_tumpang/core/utils/refund_utils.dart';
import 'package:nak_tumpang/features/subscriptions/view_models/subscription_view_model.dart';
import 'package:nak_tumpang/features/subscriptions/UI/components/edit_exception_sheet.dart';

class ExceptionListSection extends StatefulWidget {
  final String subscriptionId;
  final String currentUserRole;
  final double? fee; // daily fee
  final bool isActive;
  final DateTime? minDate;
  final DateTime? maxDate;

  const ExceptionListSection({
    super.key,
    required this.subscriptionId,
    required this.currentUserRole,
    this.fee,
    required this.isActive,
    this.minDate,
    this.maxDate,
  });

  @override
  State<ExceptionListSection> createState() => _ExceptionListSectionState();
}

class _ExceptionListSectionState extends State<ExceptionListSection> {
  List<Map<String, dynamic>> exceptions = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final vm = context.read<SubscriptionViewModel>();
    final result = await vm.fetchExceptions(widget.subscriptionId);
    setState(() {
      exceptions = result;
      isLoading = false;
    });
  }

  Future<void> _cancel(String exceptionId) async {
    final vm = context.read<SubscriptionViewModel>();
    final success = await vm.cancelException(exceptionId);
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request withdrawn. Schedule notified again.')),
      );
      _load();
    }
  }

  Widget _buildExceptionCard(Map<String, dynamic> ex, {required bool canEdit}) {
    final isDriverInitiated = ex['initiated_by_role'] == 'driver';
    final bgColor = isDriverInitiated ? AppColors.warningAmberBg : AppColors.successGreenBg;
    final textColor = isDriverInitiated ? AppColors.warningAmberText : AppColors.successGreenText;
    final actionLabel = isDriverInitiated ? "can't fetch" : 'no need to fetch';

    double? refund;
    if (isDriverInitiated && widget.fee != null) {
      final start = DateTime.tryParse(ex['start_date'] ?? '');
      final end = DateTime.tryParse(ex['end_date'] ?? '');
      if (start != null && end != null) {
        refund = RefundUtils.calculateRefund(
          dailyFee: widget.fee!,
          exceptionStart: start,
          exceptionEnd: end,
        );
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${ex['start_date']} → ${ex['end_date']}: $actionLabel',
              style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
          const SizedBox(height: 4),
          Text('Reason: ${ex['reason']}', style: TextStyle(color: textColor)),
          if (refund != null) ...[
            const SizedBox(height: 4),
            Text('Estimated refund: RM ${refund.toStringAsFixed(2)}',
                style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
          ],
          if (canEdit) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: 100,
              child: BaseButton(text: 'Edit', isFullWidth: false, onPressed: () => _openEdit(ex)),
            ),
          ],
        ],
      ),
    );
  }

  void _openEdit(Map<String, dynamic> ex) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => EditExceptionSheet(
        exception: ex,
        onChanged: _load,
        minDate: widget.minDate,
        maxDate: widget.maxDate,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primaryYellow));
    }

    final ownExceptions =
    exceptions.where((ex) => ex['initiated_by_role'] == widget.currentUserRole).toList();
    final otherRole = widget.currentUserRole == 'passenger' ? 'driver' : 'passenger';
    final otherExceptions =
    exceptions.where((ex) => ex['initiated_by_role'] == otherRole).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Your requests', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 8),
        if (ownExceptions.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Text('No requests submitted.', style: TextStyle(color: AppColors.greyText)),
          )
        else
          ...ownExceptions.map((ex) => _buildExceptionCard(ex, canEdit: widget.isActive)),

        const SizedBox(height: 16),
        Text('${otherRole[0].toUpperCase()}${otherRole.substring(1)}\'s updates',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 8),
        if (otherExceptions.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Text('No updates.', style: TextStyle(color: AppColors.greyText)),
          )
        else
          ...otherExceptions.map((ex) => _buildExceptionCard(ex, canEdit: false)),
      ],
    );
  }
}