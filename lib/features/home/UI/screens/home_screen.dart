import 'package:flutter/material.dart';
import '../components/home_panel.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Map Background Placeholder
          Container(
            width: double.infinity,
            height: double.infinity,
            color: Colors.blueGrey[50], // Slightly lighter dummy map bg
            child: const Center(
              child: Text(
                'Map View Placeholder',
                style: TextStyle(color: Colors.black54),
              ),
            ),
          ),

          // Floating Menu Button
          Positioned(
            top: 50,
            right: 16,
            child: Material(
              elevation: 4,
              shape: const CircleBorder(),
              color: Colors.white,
              child: IconButton(
                icon: const Icon(Icons.menu, color: Colors.black87),
                onPressed: () {},
              ),
            ),
          ),

          // Sliding Panel
          const HomePanel(),
        ],
      ),
    );
  }
}