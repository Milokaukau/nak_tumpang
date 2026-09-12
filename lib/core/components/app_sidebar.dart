import 'package:flutter/material.dart';
import 'package:nak_tumpang/features/home/view_models/home_view_model.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/core/services/network_service.dart';
import 'package:nak_tumpang/features/payout/UI/screens/driver_balance_screen.dart';
import 'package:nak_tumpang/features/payment/UI/screens/payment_screen.dart';
import 'package:nak_tumpang/features/payment/view_models/payment_view_model.dart';
import 'package:nak_tumpang/features/payment/data/services/payment_local_service.dart';
import 'package:nak_tumpang/features/negotiation/UI/screens/request_list_screen.dart';
import 'package:nak_tumpang/features/negotiation/view_models/negotiation_view_model.dart';
import 'package:nak_tumpang/features/negotiation/data/services/negotiation_local_service.dart';
import 'package:nak_tumpang/features/profile/UI/screens/profile_screen.dart';
import 'package:nak_tumpang/features/auth/UI/screens/login_screen.dart';
import 'package:nak_tumpang/features/trips/UI/my_trips_screen.dart';

class HamburgerButton extends StatelessWidget {
  const HamburgerButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      shape: const CircleBorder(),
      color: AppColors.white,
      child: IconButton(
        icon: const Icon(Icons.menu, color: AppColors.black),
        onPressed: () {
          Scaffold.of(context).openEndDrawer();
        },
      ),
    );
  }
}

class AppSidebar extends StatefulWidget {
  final String userName;
  final String userRole;
  final String? profileImageUrl;
  final int selectedIndex;

  /// Optional manual overrides for badge counts
  final int? pendingRequestsCount;
  final int? pendingPaymentsCount;

  const AppSidebar({
    super.key,
    this.userName = 'User',
    this.userRole = 'Driver',
    this.profileImageUrl,
    this.selectedIndex = -1,
    this.pendingRequestsCount,
    this.pendingPaymentsCount,
  });

  @override
  State<AppSidebar> createState() => _AppSidebarState();
}

class _AppSidebarState extends State<AppSidebar> {
  int _fallbackRequestsCount = 0;
  int _fallbackPaymentsCount = 0;

  bool get _isDriver => widget.userRole.toLowerCase().trim().contains('driver');

  @override
  void initState() {
    super.initState();
    _loadFallbackCounts();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        context.read<NegotiationViewModel?>()?.refreshRequests();
      } catch (_) {}
      try {
        context.read<PaymentViewModel?>()?.fetchAllPayments();
      } catch (_) {}
    });
  }

  Future<void> _loadFallbackCounts() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      // 1. Requests Badge (pending + negotiating)
      if (widget.pendingRequestsCount == null) {
        if (NetworkService.isOfflineNotifier.value) {
          final p = await NegotiationLocalService().getOfflineRequests('pending');
          final n = await NegotiationLocalService().getOfflineRequests('negotiating');
          if (mounted) setState(() => _fallbackRequestsCount = p.length + n.length);
        } else {
          final tripTable = _isDriver ? 'driver_trips' : 'passenger_trips';
          final tripIdColumn = _isDriver ? 'driver_trip_id' : 'passenger_trip_id';

          final trips = await Supabase.instance.client
              .from(tripTable)
              .select('id')
              .eq('user_id', user.id);
          final tripIds = (trips as List).map((t) => t['id'] as String).toList();

          if (tripIds.isNotEmpty) {
            final rows = await Supabase.instance.client
                .from('tumpang_request')
                .select('id')
                .inFilter(tripIdColumn, tripIds)
                .or('status.eq.pending,status.eq.negotiating');
            if (mounted) setState(() => _fallbackRequestsCount = (rows as List).length);
          }
        }
      }

      // 2. Payments Badge (unpaid invoices)
      if (widget.pendingPaymentsCount == null && !_isDriver) {
        if (NetworkService.isOfflineNotifier.value) {
          final pRows = await PaymentLocalService().getOfflinePayments(isCompleted: false);
          if (mounted) setState(() => _fallbackPaymentsCount = pRows.length);
        } else {
          final rows = await Supabase.instance.client
              .from('payments')
              .select('id, tumpang_subscription!inner(passenger_trip_id, passenger_trips!inner(user_id))')
              .eq('tumpang_subscription.passenger_trips.user_id', user.id)
              .isFilter('paid_at', null);

          if (mounted) setState(() => _fallbackPaymentsCount = (rows as List).length);
        }
      }
    } catch (e) {
      debugPrint('Sidebar count load notice: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    int requestsBadge = widget.pendingRequestsCount ?? _fallbackRequestsCount;
    int paymentsBadge = widget.pendingPaymentsCount ?? _fallbackPaymentsCount;

    // Reactively watch ViewModels if they exist in the Provider tree
    try {
      final negoVm = context.watch<NegotiationViewModel?>();
      if (negoVm != null) {
        requestsBadge = negoVm.pendingRequests.length;
      }
    } catch (_) {}

    try {
      final payVm = context.watch<PaymentViewModel?>();
      if (payVm != null) {
        paymentsBadge = payVm.pendingPayments.length;
      }
    } catch (_) {}

    return Drawer(
      width: MediaQuery.of(context).size.width * 0.72,
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.horizontal(
            left: Radius.circular(28),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            CircleAvatar(
              radius: 40,
              backgroundColor: AppColors.primaryYellow,
              backgroundImage: widget.profileImageUrl != null
                  ? NetworkImage(widget.profileImageUrl!)
                  : null,
              child: widget.profileImageUrl == null
                  ? const Icon(Icons.person, size: 50, color: AppColors.white)
                  : null,
            ),
            const SizedBox(height: 16),
            Text(
              widget.userName,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.black),
            ),
            Text(
              widget.userRole,
              style: const TextStyle(fontSize: 15, color: AppColors.greyText),
            ),
            const SizedBox(height: 16),
            const Divider(color: AppColors.greyBorder, thickness: 1),
            const SizedBox(height: 20),

            _buildMenuItem(context, index: 0, title: 'View Profile'),
            _buildMenuItem(context, index: 1, title: 'My Trips'),
            _buildMenuItem(context, index: 2, title: 'View Subscriptions'),
            _buildMenuItem(
              context,
              index: 3,
              title: 'View Requests',
              badgeCount: requestsBadge,
            ),
            _buildMenuItem(
              context,
              index: 4,
              title: _isDriver ? 'My Earnings' : 'Payment',
              badgeCount: _isDriver ? 0 : paymentsBadge,
            ),

            const SizedBox(height: 8),

            _buildMenuItem(
              context,
              index: 5,
              title: 'Sign Out',
              textColor: const Color(0xFFEF4444),
            ),
          ],
        ),
      ),
    );
  }

  void _handleItemTap(BuildContext context, int index) async {
    // --- FIXED: Capture the ViewModel BEFORE the drawer closes and destroys the context ---
    final homeViewModel = context.read<HomeViewModel>();

    Navigator.pop(context);

    if (index == widget.selectedIndex) return;

    if (index == 5) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
            (route) => false,
      );
      return;
    }

    Widget nextScreen;
    switch (index) {
      case 0:
        nextScreen = const ProfileScreen();
        break;
      case 1:
        nextScreen = const MyTripsScreen();
        break;
      case 2:
        nextScreen = const ProfileScreen();
        break;
      case 3:
        nextScreen = const RequestListScreen();
        break;
      case 4:
        nextScreen = _isDriver ? const DriverBalanceScreen() : const PaymentScreen();
        break;
      default:
        return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => nextScreen),
    );

    // --- FIXED: Safely refresh the Home screen using the captured ViewModel ---
    try {
      await homeViewModel.refreshHome();
    } catch (e) {
      debugPrint('Sidebar refresh error: $e');
    }
  }

  Widget _buildMenuItem(
      BuildContext context, {
        required int index,
        required String title,
        Color? textColor,
        int? badgeCount,
      }) {
    final isSelected = widget.selectedIndex == index;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: isSelected ? AppColors.primaryYellow : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () => _handleItemTap(context, index),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      color: textColor ?? AppColors.black,
                    ),
                  ),
                ),
                if (badgeCount != null && badgeCount > 0) ...[
                  const SizedBox(width: 8),
                  _buildBadge(badgeCount, isSelected: isSelected),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(int count, {bool isSelected = false}) {
    final label = count > 99 ? '99+' : count.toString();
    return Container(
      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.black : AppColors.primaryYellow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: isSelected ? AppColors.white : AppColors.black,
          ),
        ),
      ),
    );
  }
}