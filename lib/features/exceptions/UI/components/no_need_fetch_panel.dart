import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/core/components/base_profile_card.dart';
import 'package:nak_tumpang/core/components/exception_request_form.dart';
import 'package:nak_tumpang/features/exceptions/view_models/exception_view_model.dart';

class NoNeedFetchPanel extends StatelessWidget {
  final String tumpangSubscriptionId;
  final String passengerId;
  final String driverName;
  final String? driverImageUrl;
  final String pickupName;
  final String dropoffName;
  final String pickupTime;
  final String driverPhone;

  const NoNeedFetchPanel({
    super.key,
    required this.tumpangSubscriptionId,
    required this.passengerId,
    required this.driverName,
    this.driverImageUrl,
    required this.pickupName,
    required this.dropoffName,
    required this.pickupTime,
    required this.driverPhone,
  });

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ExceptionViewModel>();

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.2,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(color: Colors.black12, blurRadius: 10, spreadRadius: 2)
            ],
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
                  decoration: BoxDecoration(
                    color: AppColors.greyBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: BaseProfileCard(
                  profileImageUrl: driverImageUrl,
                  padding: const EdgeInsets.all(20), // was 16 (default) — more room overall
                  title: Text(driverName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)), // was 16
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
                startDate: vm.startDate,
                endDate: vm.endDate,
                onStartDateChanged: vm.setStartDate,
                onEndDateChanged: vm.setEndDate,
                reasonOptions: ExceptionViewModel.passengerReasons,
                selectedReason: vm.selectedReason,
                onReasonChanged: vm.setReason,
                customReasonController: vm.customReasonController,
                infoBoxColor: AppColors.successGreenBg,
                infoBoxTextColor: AppColors.successGreenText,
                infoBoxText:
                "$driverName will be notified immediately and won't count you in for pickup on these dates. You won't be charged for this period. Your regular tumpang schedule resumes automatically after.",
                confirmLabel: 'Confirm',
                isSubmitting: vm.isSubmitting,
                onCancel: () => Navigator.of(context).pop(),
                onConfirm: () async {
                  final success = await vm.submitException(
                    tumpangSubscriptionId: tumpangSubscriptionId,
                    initiatedBy: passengerId,
                  );
                  if (success && context.mounted) Navigator.of(context).pop();
                },
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }
}