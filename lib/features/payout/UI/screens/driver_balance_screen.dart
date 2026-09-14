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

// informational banner for wallet notice (e.g. offline cache or failed refresh)
class _InlineNoticeBanner extends StatelessWidget {
  final String text;
  const _InlineNoticeBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.lightYellow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 18, color: AppColors.greyText),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: const TextStyle(color: AppColors.greyText, fontSize: 12)),
          ),
        ],
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
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: InkWell(
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
      ),
    );
  }
}

class _WalletTab extends StatelessWidget {
  final PayoutViewModel vm;
  const _WalletTab({required this.vm});

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: vm.refreshWallet,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
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
                    value: '+${pointsLabel(vm.thisMonthPoints)} pts',
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

    // reset all data so dialog appear clean each time
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

// all payout history for the specific driver, most recent first
class _HistoryTab extends StatelessWidget {
  final PayoutViewModel vm;
  const _HistoryTab({required this.vm});

  @override
  Widget build(BuildContext context) {
    if (vm.isHistoryLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (vm.historyError != null) {
      return RefreshIndicator(
        onRefresh: vm.refreshHistory,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: 300,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(vm.historyError!, style: const TextStyle(color: AppColors.greyText)),
                    const SizedBox(height: 12),
                    TextButton(onPressed: vm.refreshHistory, child: const Text('Retry')),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (!vm.hasAnyHistory) {
      return RefreshIndicator(
        onRefresh: vm.refreshHistory,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(
              height: 300,
              child: Center(
                child: Text('No payout history yet.', style: TextStyle(color: AppColors.greyText)),
              ),
            ),
          ],
        ),
      );
    }

    final filtered = vm.filteredPayoutHistory;

    return Column(
      children: [
        if (vm.historyNotice != null) _InlineNoticeBanner(text: vm.historyNotice!),
        _YearFilterChips(vm: vm),
        // month filter only appears after a year filter is applied
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: vm.selectedHistoryYear != null && vm.historyMonths.length > 1
              ? _MonthFilterChips(vm: vm)
              : const SizedBox(width: double.infinity),
        ),
        Expanded(
          child: filtered.isEmpty
              ? RefreshIndicator(
            onRefresh: vm.refreshHistory,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(
                  height: 300,
                  child: Center(
                    child: Text('No payouts in this month.', style: TextStyle(color: AppColors.greyText)),
                  ),
                ),
              ],
            ),
          )
              : RefreshIndicator(
            onRefresh: vm.refreshHistory,
            child: NotificationListener<ScrollNotification>(
              // loads next page before driver reaches the bottom so list feels continuous, instead of pausing
              onNotification: (notification) {
                if (notification.metrics.pixels >= notification.metrics.maxScrollExtent - 200) {
                  vm.loadMoreHistory();
                }
                return false;
              },
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                itemCount: filtered.length + (vm.hasMoreHistory ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index >= filtered.length) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: vm.isLoadingMoreHistory
                            ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                            : TextButton(
                          onPressed: vm.loadMoreHistory,
                          child: const Text('Load more'),
                        ),
                      ),
                    );
                  }
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
          ),
        ),
      ],
    );
  }
}

// row of all + one chip per year that appears in payout history
class _YearFilterChips extends StatelessWidget {
  final PayoutViewModel vm;
  const _YearFilterChips({required this.vm});

  @override
  Widget build(BuildContext context) {
    final years = vm.historyYears;
    if (years.length <= 1) return const SizedBox.shrink();
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        itemCount: years.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == 0) {
            return ChoiceChip(
              label: const Text('All'),
              selected: vm.selectedHistoryYear == null,
              onSelected: (_) => vm.selectHistoryYear(null),
              selectedColor: AppColors.primaryYellow,
              labelStyle: TextStyle(
                fontWeight: FontWeight.w600,
                color: vm.selectedHistoryYear == null ? AppColors.black : AppColors.greyText,
              ),
            );
          }
          final year = years[index - 1];
          final isSelected = vm.selectedHistoryYear == year;
          return ChoiceChip(
            label: Text('$year'),
            selected: isSelected,
            onSelected: (_) => vm.selectHistoryYear(year),
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


// row of all and one chip per month within the currently selected year
// only appears if a year is picked and there is more than one month in that year
class _MonthFilterChips extends StatelessWidget {
  final PayoutViewModel vm;
  const _MonthFilterChips({required this.vm});

  static const _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _label(DateTime month) => _monthNames[month.month - 1];

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
    final statusColor = payoutStatusColor(entry.status);
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
                    '${entry.maskedDestination} · $dateLabel',
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
                    payoutStatusLabel(entry.status),
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
            '${pointsLabel(vm.availableBalance)} pts',
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
              '+${pointsLabel(trip.points)} pts',
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