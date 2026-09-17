import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/core/services/goyang_detector.dart';
import 'package:nak_tumpang/features/rewards/view_models/rewards_view_model.dart';

class GoyangScreen extends StatefulWidget {
  final String userId;

  const GoyangScreen({super.key, required this.userId});

  @override
  State<GoyangScreen> createState() => _GoyangScreenState();
}

class _GoyangScreenState extends State<GoyangScreen> {
  GoyangDetector? _detector;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _detector = GoyangDetector(
      onGoyang: _handleGoyangTriggered,
    )..startListening();
  }

  @override
  void dispose() {
    _detector?.stopListening();
    super.dispose();
  }

  Future<void> _handleGoyangTriggered() async {
    if (_isPlaying) return;
    await _play();
  }

  Future<void> _play() async {
    if (!mounted) return;
    final vm = context.read<RewardsViewModel>();
    if (!vm.isGoyangAvailableToday || vm.isClaimingGoyang) return;

    setState(() => _isPlaying = true);
    HapticFeedback.mediumImpact();

    final result = await vm.playGoyang(widget.userId);

    if (!mounted) return;
    setState(() => _isPlaying = false);
    _showResultDialog(result);
  }

  void _showResultDialog(Map<String, dynamic> result) {
    String title;
    String message;

    switch (result['type']) {
      case 'points':
        title = '🎉 You won points!';
        message = 'You earned ${result['points']} points! Check Points History for the entry.';
        break;
      case 'voucher':
        title = '🎁 You won a voucher!';
        message = 'You won "${result['voucher_name']}"! Check My Rewards to view it.';
        break;
      case 'already_claimed':
        title = 'Already claimed';
        message = "You've already played Goyang N Win today. Come back tomorrow!";
        break;
      default:
        title = 'Oops!';
        message = 'Something went wrong. Please try again.';
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<RewardsViewModel>();
    final canPlay = vm.isGoyangAvailableToday && !vm.isClaimingGoyang && !_isPlaying;

    return Scaffold(
      backgroundColor: AppColors.primaryYellow,
      appBar: AppBar(
        backgroundColor: AppColors.primaryYellow,
        elevation: 0,
        foregroundColor: AppColors.black,
        title: const Text('Goyang N Win', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(),
              const Icon(Icons.card_giftcard, size: 100, color: AppColors.black),
              const SizedBox(height: 24),
              const Text(
                'GOYANG N WIN!',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: AppColors.black),
              ),
              const SizedBox(height: 16),
              Text(
                canPlay
                    ? 'Shake your phone to see if you win points or a voucher!'
                    : "You've already played today — come back tomorrow!",
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, color: AppColors.black, height: 1.4),
              ),
              const Spacer(),
              if (_isPlaying || vm.isClaimingGoyang)
                const CircularProgressIndicator(color: AppColors.black),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}