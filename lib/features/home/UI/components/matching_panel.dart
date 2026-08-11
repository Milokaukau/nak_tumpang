import 'package:flutter/material.dart';
import 'filter_options.dart';
import 'route_option_card.dart';

class MatchingPanel extends StatelessWidget {
  const MatchingPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.2,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 10,
                spreadRadius: 2,
              )
            ],
          ),
          child: Column(
            children: [
              // Drag Handle
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                height: 4,
                width: 40,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  children: const [
                    Text(
                      'Available options',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 16),

                    // Filter Chips (Direct vs Mixed)
                    FilterOptions(),

                    SizedBox(height: 24),

                    // Route Cards
                    RouteOptionCard(),

                    Divider(height: 40, thickness: 1, color: Color(0xFFEEEEEE)),

                    // Partial second card to match the image
                    RouteOptionCard(),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}