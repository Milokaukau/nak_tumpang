import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import 'filter_options.dart';
import 'route_option_card.dart';

class HomePanel extends StatelessWidget {
  const HomePanel({super.key});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.2,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(color: Colors.black12, blurRadius: 10, spreadRadius: 2)
            ],
          ),
          // Putting the drag handle inside the ListView ensures it won't break constraints
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            children: [
              // Drag Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(bottom: 24),
                  height: 4,
                  width: 40,
                  decoration: BoxDecoration(
                    color: AppColors.greyBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              const Text(
                'Available options',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),

              const FilterOptions(),
              const SizedBox(height: 24),

              const RouteOptionCard(),

              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Divider(height: 1, thickness: 1, color: AppColors.greyBorder),
              ),

              // Second dummy card to simulate scrolling
              const RouteOptionCard(),
            ],
          ),
        );
      },
    );
  }
}