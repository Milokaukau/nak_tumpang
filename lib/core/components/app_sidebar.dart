import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/features/profile/UI/screens/profile_screen.dart';
import 'package:nak_tumpang/features/auth/UI/screens/login_screen.dart';
import 'package:nak_tumpang/features/negotiation/UI/screens/request_list_screen.dart';
import 'package:nak_tumpang/features/payment/UI/screens/payment_screen.dart';

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

class AppSidebar extends StatelessWidget {
  final String userName;
  final String userRole;
  final String? profileImageUrl;
  final int selectedIndex;

  const AppSidebar({
    super.key,
    this.userName = 'John Cena',
    this.userRole = 'Driver',
    this.profileImageUrl,
    this.selectedIndex = -1,
  });

  @override
  Widget build(BuildContext context) {
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
              backgroundImage: profileImageUrl != null
                  ? NetworkImage(profileImageUrl!)
                  : null,
              child: profileImageUrl == null
                  ? const Icon(Icons.person, size: 50, color: AppColors.white)
                  : null,
            ),
            const SizedBox(height: 16),
            Text(
              userName,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.black),
            ),
            Text(
              userRole,
              style: const TextStyle(fontSize: 15, color: AppColors.greyText),
            ),
            const SizedBox(height: 16),
            const Divider(color: AppColors.greyBorder, thickness: 1),
            const SizedBox(height: 20),

            // Navigation Items
            _buildMenuItem(context, index: 0, title: 'View Profile'),
            _buildMenuItem(context, index: 1, title: 'View Subscriptions'),
            _buildMenuItem(context, index: 2, title: 'View Requests'),
            _buildMenuItem(context, index: 3, title: 'Payment / My Earnings'),

            const SizedBox(height: 8), // Slight extra gap before Sign Out

            // Sign Out Option (using the reusable component)
            _buildMenuItem(
              context,
              index: 4,
              title: 'Sign Out',
              textColor: const Color(0xFFEF4444),
            ),
          ],
        ),
      ),
    );
  }

  // Handle routing internally
  void _handleItemTap(BuildContext context, int index) async { // <-- Add 'async' here
    Navigator.pop(context);

    if (index == selectedIndex) return;

    if (index == 4) {
      // 1. Actually kill the Supabase session
      await Supabase.instance.client.auth.signOut();

      // 2. Route to Login and DESTROY the navigation history
      if (context.mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
              (route) => false,
        );
      }
      return;
    }

    Widget nextScreen;
    switch (index) {
      case 0:
        nextScreen = const ProfileScreen();
        break;
      case 1:
      // Updates routing to the "My Tumpangs" / Subscriptions List
      // Replace MyTumpangsScreen() with whatever you named the file for Figma Page 11
        nextScreen = const Scaffold(body: Center(child: Text('My Tumpangs Screen'))); // const MyTumpangsScreen();
        break;
      case 2:
      // Updates routing to the Request List we built
        nextScreen = const RequestListScreen();
        break;
      case 3:
        nextScreen = const PaymentScreen(); // Keep as placeholder for now
        break;
      default:
        return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => nextScreen),
    );
  }

  // Added optional textColor parameter
  Widget _buildMenuItem(BuildContext context, {required int index, required String title, Color? textColor}) {
    final isSelected = selectedIndex == index;

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
            child: Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                // Use the custom color if provided, otherwise default to black
                color: textColor ?? AppColors.black,
              ),
            ),
          ),
        ),
      ),
    );
  }
}