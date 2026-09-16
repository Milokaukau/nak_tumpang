import 'package:flutter/material.dart';
import 'package:nak_tumpang/core/components/base_button.dart';
import 'package:provider/provider.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/core/components/base_profile_card.dart';
import 'package:nak_tumpang/features/home/UI/components/exception_request_form/exception_request_form.dart';
import 'package:nak_tumpang/features/home/view_models/home_view_model.dart';

/// One driver leg's display + submission data for [NoNeedFetchPanel].
///
/// A trip with two drivers (first-mile + last-mile) is two separate
/// `tumpang_subscription` rows under the hood, each with its own driver
/// identity and its own subscription validity window -- this carries
/// exactly what one leg needs, without assuming there's only one.
class NoNeedFetchDriverInfo {
  final String tumpangSubscriptionId;
  final String driverId;
  final String driverName;
  final String? driverImageUrl;
  final String pickupName;
  final String dropoffName;
  final String pickupTime;
  final String driverPhone;
  final DateTime? minDate;
  final DateTime? maxDate;

  const NoNeedFetchDriverInfo({
    required this.tumpangSubscriptionId,
    required this.driverId,
    required this.driverName,
    this.driverImageUrl,
    required this.pickupName,
    required this.dropoffName,
    required this.pickupTime,
    required this.driverPhone,
    required this.minDate,
    required this.maxDate,
  });
}

class NoNeedFetchPanel extends StatelessWidget {
  final List<NoNeedFetchDriverInfo> drivers;
  final String passengerId;
  final VoidCallback? onSubmitted;

  const NoNeedFetchPanel({
    super.key,
    required this.drivers,
    required this.passengerId,
    this.onSubmitted,
  }) : assert(drivers.length > 0, 'NoNeedFetchPanel needs at least one driver leg');

  bool get _isMultiDriver => drivers.length > 1;

  /// One confirmation submits one date range for every leg, so the range
  /// offered can only be as wide as every leg's subscription allows --
  /// the latest of the individual start dates through the earliest of the
  /// individual end dates.
  DateTime? get _effectiveMinDate {
    final dates = drivers.map((d) => d.minDate).whereType<DateTime>().toList();
    if (dates.isEmpty) return null;
    return dates.reduce((a, b) => a.isAfter(b) ? a : b);
  }

  DateTime? get _effectiveMaxDate {
    final dates = drivers.map((d) => d.maxDate).whereType<DateTime>().toList();
    if (dates.isEmpty) return null;
    return dates.reduce((a, b) => a.isBefore(b) ? a : b);
  }

  String get _namesJoined {
    final names = drivers.map((d) => d.driverName).toList();
    if (names.length == 1) return names.first;
    if (names.length == 2) return '${names[0]} and ${names[1]}';
    return '${names.sublist(0, names.length - 1).join(', ')}, and ${names.last}';
  }

  Widget _buildDriverCard(NoNeedFetchDriverInfo driver) {
    return SizedBox(
      width: double.infinity,
      child: BaseProfileCard(
        profileImageUrl: driver.driverImageUrl,
        padding: const EdgeInsets.all(20),
        title: Text(driver.driverName,
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
                      Text(driver.pickupName, style: const TextStyle(color: AppColors.greyText)),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(Icons.arrow_forward_ios, size: 10, color: AppColors.primaryYellow),
                      ),
                      Text(driver.dropoffName, style: const TextStyle(color: AppColors.greyText)),
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
                Text(driver.pickupTime, style: const TextStyle(color: AppColors.greyText)),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.phone, size: 14, color: AppColors.primaryYellow),
                const SizedBox(width: 4),
                Text(driver.driverPhone, style: const TextStyle(color: AppColors.greyText)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<HomeViewModel>();

    final minD = _effectiveMinDate;
    final maxD = _effectiveMaxDate;
    // Check if the intersection of dates is mathematically valid
    final hasValidDateOverlap = minD == null || maxD == null || !minD.isAfter(maxD);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < drivers.length; i++) ...[
          _buildDriverCard(drivers[i]),
          if (i != drivers.length - 1) const SizedBox(height: 12),
        ],
        const SizedBox(height: 20),

        if (!hasValidDateOverlap) ...[
          // --- EDGE CASE FALLBACK UI ---
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: const Column(
              children: [
                Icon(Icons.error_outline, color: Colors.red, size: 32),
                SizedBox(height: 8),
                Text(
                  'Cannot submit exception',
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16),
                ),
                SizedBox(height: 4),
                Text(
                  'The active subscription dates for these drivers do not overlap, so a combined schedule change is not possible.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.red, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: BaseButton(
              text: 'Close',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ] else ...[
          // --- NORMAL FORM UI ---
          RichText(
            text: TextSpan(
              style: const TextStyle(color: AppColors.black, fontSize: 16),
              children: [
                TextSpan(text: 'Let $_namesJoined know you '),
                const TextSpan(
                  text: "don't need a fetch",
                  style: TextStyle(color: Colors.red),
                ),
                TextSpan(
                  text: _isMultiDriver
                      ? ' for the dates below. Both drivers will be notified together.'
                      : ' for the dates below.',
                ),
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
            emergencyReasons: const ['Personal emergency'],
            customReasonController: vm.exceptionCustomReasonController,
            infoBoxColor: AppColors.successGreenBg,
            infoBoxTextColor: AppColors.successGreenText,
            infoBoxText: _isMultiDriver
                ? "$_namesJoined will both be notified and won't count you in for pickup on these dates. Your regular tumpang schedule resumes automatically after."
                : "$_namesJoined will be notified and won't count you in for pickup on these dates. Your regular tumpang schedule resumes automatically after.",
            confirmLabel: 'Confirm',
            isSubmitting: vm.isSubmittingException,
            minDate: minD,
            maxDate: maxD,
            onCancel: () => vm.closeExceptionPanel(),
            errorText: vm.exceptionFormError,
            onDateError: vm.setExceptionFormError,
            onConfirm: () async {
              final success = _isMultiDriver
                  ? await vm.submitExceptionForTrip(
                tumpangSubscriptionIds: drivers.map((d) => d.tumpangSubscriptionId).toList(),
                initiatedBy: passengerId,
                initiatedByRole: 'passenger',
              )
                  : await vm.submitException(
                tumpangSubscriptionId: drivers.first.tumpangSubscriptionId,
                initiatedBy: passengerId,
                initiatedByRole: 'passenger',
              );

              if (success) {
                for (final driver in drivers) {
                  await vm.sendExceptionNotification(
                    targetUserId: driver.driverId,
                    title: 'New Schedule Exception',
                    message: 'Your passenger submitted a schedule exception request.',
                    subscriptionId: driver.tumpangSubscriptionId,
                  );
                }

                vm.closeExceptionPanel();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        _isMultiDriver
                            ? 'Submitted — both drivers will be notified.'
                            : 'Submitted — driver will be notified.',
                      ),
                    ),
                  );
                }
                onSubmitted?.call();
              }
            },
          ),
        ]
      ],
    );
  }
}