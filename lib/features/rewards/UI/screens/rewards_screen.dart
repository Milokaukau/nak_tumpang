import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/features/rewards/view_models/rewards_view_model.dart';
import 'package:nak_tumpang/features/rewards/UI/components/points_summary_card.dart';
import 'package:nak_tumpang/features/rewards/UI/components/voucher_card.dart';
import 'voucher_detail_screen.dart';
import 'my_reward_detail_screen.dart';

class RewardsScreen extends StatefulWidget {
  final String userId;

  const RewardsScreen({super.key, required this.userId});

  @override
  State<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends State<RewardsScreen> {
  int selectedTab = 2;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => context.read<RewardsViewModel>().loadAll(widget.userId));
  }

  bool _isExpired(DateTime? expiredAt) {
    if (expiredAt == null) return false;
    return DateTime.now().isAfter(expiredAt);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<RewardsViewModel>();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primaryYellow,
        elevation: 0,
        foregroundColor: AppColors.black,
        title: const Text('My Rewards', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: vm.isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primaryYellow))
          : RefreshIndicator(
        color: AppColors.primaryYellow,
        onRefresh: () => vm.loadAll(widget.userId),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            PointsSummaryCard(
              availablePoints: vm.summary['available_points'] ?? 0,
              usedPoints: vm.summary['used_points'] ?? 0,
              voucherCount: vm.summary['voucher_count'] ?? 0,
              nearestExpiry: vm.summary['nearest_expiry'],
            ),
            const SizedBox(height: 20),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _tabButton('Points\nHistory', 0)),
                  const SizedBox(width: 8),
                  Expanded(child: _tabButton('Reward\nRedemption', 1)),
                  const SizedBox(width: 8),
                  Expanded(child: _tabButton('My\nRewards', 2)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (selectedTab == 0) ..._buildHistoryTab(vm),
            if (selectedTab == 1) ..._buildRedemptionTab(vm),
            if (selectedTab == 2) ..._buildMyRewardsTab(vm),
          ],
        ),
      ),
    );
  }

  Widget _tabButton(String label, int index) {
    final isSelected = selectedTab == index;
    return GestureDetector(
      onTap: () => setState(() => selectedTab = index),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryYellow : AppColors.lightYellow,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, height: 1.3)),
      ),
    );
  }

  List<Widget> _buildHistoryTab(RewardsViewModel vm) {
    if (vm.pointsHistory.isEmpty) {
      return [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Center(child: Text('No history yet.', style: TextStyle(color: AppColors.greyText))),
        )
      ];
    }
    return vm.pointsHistory.map((entry) {
      final isEarn = (entry['change_amount'] as num) > 0;
      final date = DateTime.tryParse(entry['created_at'] ?? '');
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.greyBorder),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(isEarn ? Icons.arrow_upward : Icons.arrow_downward,
                color: isEarn ? AppColors.successGreenText : AppColors.inactiveRedText, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry['description'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  if (date != null)
                    Text('${date.day}/${date.month}/${date.year}',
                        style: const TextStyle(fontSize: 11, color: AppColors.greyText)),
                ],
              ),
            ),
            Text('${isEarn ? '+' : ''}${entry['change_amount']} pts',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isEarn ? AppColors.successGreenText : AppColors.inactiveRedText)),
          ],
        ),
      );
    }).toList();
  }

  List<Widget> _buildRedemptionTab(RewardsViewModel vm) {
    if (vm.availableVouchers.isEmpty) {
      return [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Center(child: Text('No vouchers available.', style: TextStyle(color: AppColors.greyText))),
        )
      ];
    }
    final available = vm.summary['available_points'] ?? 0;
    return vm.availableVouchers.map((voucher) {
      final reqPoints = (voucher['req_points'] as num).toInt();
      final canRedeem = available >= reqPoints;
      return VoucherCard(
        captionText: 'Point Voucher',
        title: voucher['name'] ?? '',
        subtitle: 'Redeem with $reqPoints points',
        statusBadge: Text(
          canRedeem ? 'Tap to redeem' : 'Need ${reqPoints - available} more pts',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: canRedeem ? AppColors.successGreenText : AppColors.warningAmberText,
          ),
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => VoucherDetailScreen(
                voucher: voucher,
                userId: widget.userId,
                availablePoints: available,
              ),
            ),
          );
        },
      );
    }).toList();
  }

  List<Widget> _buildMyRewardsTab(RewardsViewModel vm) {
    if (vm.myVouchers.isEmpty) {
      return [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Center(child: Text('No rewards redeemed yet.', style: TextStyle(color: AppColors.greyText))),
        )
      ];
    }
    return vm.myVouchers.map((uv) {
      final voucher = uv['vouchers'] ?? {};
      final isUsed = uv['used_at'] != null;
      final expiredAt = DateTime.tryParse(uv['expired_at'] ?? '');
      final isExpired = !isUsed && _isExpired(expiredAt);

      String badgeText;
      Color badgeBg, badgeText_;
      if (isUsed) {
        badgeText = 'USED';
        badgeBg = AppColors.inactiveRedBg;
        badgeText_ = AppColors.inactiveRedText;
      } else if (isExpired) {
        badgeText = 'EXPIRED';
        badgeBg = AppColors.inactiveRedBg;
        badgeText_ = AppColors.inactiveRedText;
      } else {
        badgeText = 'ACTIVE';
        badgeBg = AppColors.successGreenBg;
        badgeText_ = AppColors.successGreenText;
      }

      return VoucherCard(
        captionText: 'Surprise for you!',
        title: voucher['name'] ?? '',
        subtitle: isUsed
            ? 'Used'
            : isExpired
            ? 'Expired'
            : 'Tap to view QR code',
        isDisabled: isUsed || isExpired,
        statusBadge: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(20)),
          child: Text(badgeText,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: badgeText_)),
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => MyRewardDetailScreen(userVoucher: uv)),
          );
        },
      );
    }).toList();
  }
}