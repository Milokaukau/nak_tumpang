import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nak_tumpang/core/components/base_button.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/features/payout/UI/components/claim_payout_dialog.dart';
import 'package:nak_tumpang/features/payout/UI/components/payout_history_detail_dialog.dart';
import 'package:nak_tumpang/features/payout/UI/components/trip_detail_dialog.dart';
import 'package:nak_tumpang/features/payout/view_models/payout_view_model.dart';

class DriverBalanceScreen extends StatelessWidget {
  const DriverBalanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => PayoutViewModel()..load(),
      child: const _DriverBalanceView(),
    );
  }
}

class _DriverBalanceView extends StatelessWidget {
  const _DriverBalanceView();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PayoutViewModel>();

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(title: const Text('My Earnings')),
      body: vm.isLoading
          ? const Center(child: CircularProgressIndicator())
          : vm.errorMessage != null
          ? Center(child: Text(vm.errorMessage!))
          : SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _WalletHistoryToggle(vm: vm),
            ),
            Expanded(
              child: vm.currentView == PayoutView.wallet
                  ? _WalletTab(vm: vm)
                  : _HistoryTab(vm: vm),
            ),
          ],
        ),
      ),
    );
  }
}

// toggle to wallet and history
class _WalletHistoryToggle extends StatelessWidget {
  final PayoutViewModel vm;
  const _WalletHistoryToggle({required this.vm});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.lightYellow,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ToggleTab(
              label: 'Wallet',
              selected: vm.currentView == PayoutView.wallet,
              onTap: () => vm.setView(PayoutView.wallet),
            ),
          ),
          Expanded(
            child: _ToggleTab(
              label: 'History',
              selected: vm.currentView == PayoutView.history,
              onTap: () => vm.setView(PayoutView.history),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ToggleTab({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryYellow : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: selected ? AppColors.black : AppColors.greyText,
          ),
        ),
      ),
    );
  }
}

class _WalletTab extends StatelessWidget {
  final PayoutViewModel vm;
  const _WalletTab({required this.vm});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BalanceCard(vm: vm),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatBox(
                  label: 'This month',
                  value: '+${vm.thisMonthPoints.toStringAsFixed(0)} pts',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatBox(
                  label: 'Trips this month',
                  value: '${vm.tripsCompletedCount}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            'Recent trips',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          if (vm.recentTrips.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('No completed trips yet.', style: TextStyle(color: AppColors.greyText)),
            )
          else
            ...vm.recentTrips.map((trip) => _RecentTripTile(
              trip: trip,
              onTap: () => showDialog(
                context: context,
                builder: (_) => TripDetailDialog(trip: trip),
              ),
            )),
          const SizedBox(height: 24),
          BaseButton(
            text: 'Claim payout',
            onPressed: () => _onClaimPayout(context, vm),
          ),
        ],
      ),
    );
  }

  void _onClaimPayout(BuildContext context, PayoutViewModel vm) {
    if (vm.availableBalance <= 0) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('You have no points to claim yet.')),
        );
      return;
    }

    // Reset any stale details from a previous attempt so the dialogs
    // start clean each time they're opened.
    vm.resetDetailsFields();
    showDialog(
      context: context,
      builder: (_) => ChangeNotifierProvider.value(
        value: vm,
        child: const ClaimPayoutDialog(),
      ),
    );
  }
}

/// "History" tab — every payout_history row for this driver, most
/// recent first, with its amount, destination and status.
class _HistoryTab extends StatelessWidget {
  final PayoutViewModel vm;
  const _HistoryTab({required this.vm});

  @override
  Widget build(BuildContext context) {
    if (vm.isHistoryLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (vm.historyError != null) {
      return Center(child: Text(vm.historyError!, style: const TextStyle(color: AppColors.greyText)));
    }
    if (vm.payoutHistory.isEmpty) {
      return const Center(
        child: Text('No payout history yet.', style: TextStyle(color: AppColors.greyText)),
      );
    }

    final filtered = vm.filteredPayoutHistory;

    return Column(
      children: [
        _MonthFilterChips(vm: vm),
        Expanded(
          child: filtered.isEmpty
              ? const Center(
            child: Text('No payouts in this month.', style: TextStyle(color: AppColors.greyText)),
          )
              : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: filtered.length,
            itemBuilder: (context, index) {
              final entry = filtered[index];
              return _PayoutHistoryTile(
                entry: entry,
                onTap: () => showDialog(
                  context: context,
                  builder: (_) => PayoutHistoryDetailDialog(entry: entry),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Row of "All" + one chip per month that appears in the driver's payout
/// history, newest first. Only shown when there's more than one month to
/// choose between.
class _MonthFilterChips extends StatelessWidget {
  final PayoutViewModel vm;
  const _MonthFilterChips({required this.vm});

  static const _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _label(DateTime month) => '${_monthNames[month.month - 1]} ${month.year}';

  @override
  Widget build(BuildContext context) {
    final months = vm.historyMonths;
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        itemCount: months.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == 0) {
            return ChoiceChip(
              label: const Text('All'),
              selected: vm.selectedHistoryMonth == null,
              onSelected: (_) => vm.selectHistoryMonth(null),
              selectedColor: AppColors.primaryYellow,
              labelStyle: TextStyle(
                fontWeight: FontWeight.w600,
                color: vm.selectedHistoryMonth == null ? AppColors.black : AppColors.greyText,
              ),
            );
          }
          final month = months[index - 1];
          final isSelected = vm.selectedHistoryMonth != null &&
              vm.selectedHistoryMonth!.year == month.year &&
              vm.selectedHistoryMonth!.month == month.month;
          return ChoiceChip(
            label: Text(_label(month)),
            selected: isSelected,
            onSelected: (_) => vm.selectHistoryMonth(month),
            selectedColor: AppColors.primaryYellow,
            labelStyle: TextStyle(
              fontWeight: FontWeight.w600,
              color: isSelected ? AppColors.black : AppColors.greyText,
            ),
          );
        },
      ),
    );
  }
}

class _PayoutHistoryTile extends StatelessWidget {
  final PayoutHistoryDisplay entry;
  final VoidCallback onTap;
  const _PayoutHistoryTile({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (entry.status) {
      'paid' => Colors.green,
      'processing' => Colors.orange,
      _ => AppColors.greyText,
    };
    final date = entry.requestedAt;
    final dateLabel = date == null
        ? '-'
        : '${date.day}/${date.month}/${date.year}';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.greyBorder),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              entry.isEwallet ? Icons.account_balance_wallet : Icons.account_balance,
              color: AppColors.primaryYellow,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.destinationLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(
                    '${entry.bankAccNo} · $dateLabel',
                    style: const TextStyle(color: AppColors.greyText, fontSize: 12),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'RM${entry.amount.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    entry.status[0].toUpperCase() + entry.status.substring(1),
                    style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: AppColors.greyText, size: 18),
          ],
        ),
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  final PayoutViewModel vm;
  const _BalanceCard({required this.vm});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.greyBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Available points', style: TextStyle(color: AppColors.greyText)),
          const SizedBox(height: 4),
          Text(
            '${vm.availableBalance.toStringAsFixed(0)} pts',
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          Text(
            '≈ RM${vm.availableBalance.toStringAsFixed(2)}',
            style: const TextStyle(color: AppColors.greyText),
          ),
        ],
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  const _StatBox({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.greyBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppColors.greyText, fontSize: 12)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ],
      ),
    );
  }
}

class _RecentTripTile extends StatelessWidget {
  final RecentTripDisplay trip;
  final VoidCallback onTap;
  const _RecentTripTile({required this.trip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.greyBorder),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(trip.passengerName, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(
                    '${trip.pickupName} → ${trip.dropoffName} · ${trip.monthLabel}',
                    style: const TextStyle(color: AppColors.greyText, fontSize: 12),
                  ),
                ],
              ),
            ),
            Text(
              '+${trip.points.toStringAsFixed(0)} pts',
              style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: AppColors.greyText, size: 18),
          ],
        ),
      ),
    );
  }
}