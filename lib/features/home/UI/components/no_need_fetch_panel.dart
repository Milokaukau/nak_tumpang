import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/core/components/base_profile_card.dart';
import 'package:nak_tumpang/features/home/UI/components/exception_request_form/exception_request_form.dart';
import 'package:nak_tumpang/features/home/view_models/home_view_model.dart';

class NoNeedFetchPanel extends StatelessWidget {
  final String tumpangSubscriptionId;
  final String passengerId;
  final String driverId;
  final String driverName;
  final String? driverImageUrl;
  final String pickupName;
  final String dropoffName;
  final String pickupTime;
  final String driverPhone;
  final DateTime? minDate;
  final DateTime? maxDate;
  final VoidCallback? onSubmitted;

  const NoNeedFetchPanel({
    super.key,
    required this.tumpangSubscriptionId,
    required this.passengerId,
    required this.driverId,
    required this.driverName,
    this.driverImageUrl,
    required this.pickupName,
    required this.dropoffName,
    required this.pickupTime,
    required this.driverPhone,
    required this.minDate,
    required this.maxDate,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<HomeViewModel>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: BaseProfileCard(
            profileImageUrl: driverImageUrl,
            padding: const EdgeInsets.all(20),
            title: Text(driverName,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            description: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(Icons.location_on, size: 14, color: AppColors.primaryYellow),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(pickupName, style: const TextStyle(color: AppColors.greyText)),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 4),
                            child: Icon(Icons.arrow_forward_ios, size: 10, color: AppColors.primaryYellow),
                          ),
                          Text(dropoffName, style: const TextStyle(color: AppColors.greyText)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.access_time, size: 14, color: AppColors.primaryYellow),
                    const SizedBox(width: 4),
                    Text(pickupTime, style: const TextStyle(color: AppColors.greyText)),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.phone, size: 14, color: AppColors.primaryYellow),
                    const SizedBox(width: 4),
                    Text(driverPhone, style: const TextStyle(color: AppColors.greyText)),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        RichText(
          text: TextSpan(
            style: const TextStyle(color: AppColors.black, fontSize: 16),
            children: [
              TextSpan(text: 'Let $driverName know you '),
              const TextSpan(
                text: "don't need a fetch",
                style: TextStyle(color: Colors.red),
              ),
              const TextSpan(text: ' for the dates below.'),
            ],
          ),
        ),
        const SizedBox(height: 20),
        ExceptionRequestForm(
          dateRangeLabel: 'Not needed from',
          startDate: vm.exceptionStartDate,
          endDate: vm.exceptionEndDate,
          onStartDateChanged: vm.setExceptionStartDate,
          onEndDateChanged: vm.setExceptionEndDate,
          reasonOptions: HomeViewModel.passengerReasons,
          selectedReason: vm.exceptionReason,
          onReasonChanged: vm.setExceptionReason,
          customReasonController: vm.exceptionCustomReasonController,
          infoBoxColor: AppColors.successGreenBg,
          infoBoxTextColor: AppColors.successGreenText,
          infoBoxText:
          "$driverName will be notified and won't count you in for pickup on these dates. Your regular tumpang schedule resumes automatically after.",
          confirmLabel: 'Confirm',
          isSubmitting: vm.isSubmittingException,
          minDate: minDate,
          maxDate: maxDate,
          onCancel: () => vm.closeExceptionPanel(),
          errorText: vm.exceptionFormError,
          onDateError: vm.setExceptionFormError,
          onConfirm: () async {
            final success = await vm.submitException(
              tumpangSubscriptionId: tumpangSubscriptionId,
              initiatedBy: passengerId,
              initiatedByRole: 'passenger',
            );
            if (success) {
              await vm.sendExceptionNotification(
                targetUserId: driverId,
                title: 'New Schedule Exception',
                message: 'Your passenger submitted a schedule exception request.',
                subscriptionId: tumpangSubscriptionId,
              );

              vm.closeExceptionPanel();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Submitted — driver will be notified.')),
                );
              }
              onSubmitted?.call();
            }
          },
        ),
      ],
    );
  }
}