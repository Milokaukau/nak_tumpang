import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nak_tumpang/core/components/base_button.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/features/payout/UI/screens/payout_method_screen.dart';
import 'package:nak_tumpang/features/payout/view_models/payout_view_model.dart';

/// "Wallet" screen — driver's points balance, this-month/trips stats,
/// and a Recent trips list, with a Claim payout button that starts the
/// payout flow.
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
      appBar: AppBar(title: const Text('Wallet')),
      body: vm.isLoading
          ? const Center(child: CircularProgressIndicator())
          : vm.errorMessage != null
          ? Center(child: Text(vm.errorMessage!))
          : SafeArea(
        child: SingleChildScrollView(
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
                      label: 'Trips completed',
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
                ...vm.recentTrips.map((trip) => _RecentTripTile(trip: trip)),
              const SizedBox(height: 24),
              BaseButton(
                text: 'Claim payout',
                onPressed: vm.availableBalance <= 0
                    ? () {}
                    : () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChangeNotifierProvider.value(
                      value: vm,
                      child: const PayoutMethodScreen(),
                    ),
                  ),
                ),
              ),
            ],
          ),
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
  const _RecentTripTile({required this.trip});

  @override
  Widget build(BuildContext context) {
    return Container(
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
        ],
      ),
    );
  }
}
