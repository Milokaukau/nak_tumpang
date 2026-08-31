import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/core/components/base_button.dart';
import 'package:nak_tumpang/features/home/view_models/home_view_model.dart';
import 'cant_fetch_panel.dart';
import 'no_need_fetch_panel.dart';

class ExceptionTestPanel extends StatelessWidget {
  const ExceptionTestPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<HomeViewModel>();

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
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            children: [
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
              if (viewModel.panelMode == HomePanelMode.cantFetch)
                const CantFetchPanel(
                  tumpangSubscriptionId: 'sub_8829kxP',
                  driverId: 'ccf6036f-0097-4369-b94f-0a22ee7987de',
                  passengerName: 'Chong Fun',
                  pickupName: 'PV13 Platinum Lake Condominium, Setapak',
                  dropoffName: 'TAR UMT Arena, Kuala Lumpur',
                  pickupTime: '07:55 AM',
                  passengerPhone: '+60123456789',
                )
              else if (viewModel.panelMode == HomePanelMode.noNeedFetch)
                const NoNeedFetchPanel(
                  tumpangSubscriptionId: 'sub_8829kxP',
                  passengerId: '31db9203-05d0-42af-8641-50e48e9c163a',
                  driverName: 'Supaidol',
                  pickupName: 'PV13 Platinum Lake Condominium, Setapak',
                  dropoffName: 'TAR UMT Arena, Kuala Lumpur',
                  pickupTime: '07:55 AM',
                  driverPhone: '+60198765432',
                )
              else ...[
                  const Text('Exception Module Test',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: BaseButton(
                          text: "Can't fetch",
                          onPressed: () => viewModel.openCantFetchPanel(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: BaseButton(
                          text: 'No need fetch',
                          onPressed: () => viewModel.openNoNeedFetchPanel(),
                        ),
                      ),
                    ],
                  ),
                ],
            ],
          ),
        );
      },
    );
  }
}