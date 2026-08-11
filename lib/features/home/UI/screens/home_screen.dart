import 'package:flutter/material.dart';
import 'package:nak_tumpang/core/components/app_sidebar.dart';
import 'package:nak_tumpang/features/home/UI/components/home_panel.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      endDrawer: const AppSidebar(
        userName: 'John Cena',
        userRole: 'Driver',
        selectedIndex: -1,
        // No callbacks needed here anymore!
      ),
      body: Stack(
        children: [
          Container(
            width: double.infinity,
            height: double.infinity,
            color: Colors.blueGrey[50],
            child: const Center(
              child: Text(
                'Map View Placeholder',
                style: TextStyle(color: Colors.black54),
              ),
            ),
          ),
          const Positioned(
            top: 50,
            right: 16,
            child: HamburgerButton(),
          ),
          const HomePanel(),
        ],
      ),
    );
  }
}