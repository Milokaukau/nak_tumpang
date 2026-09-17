import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:nak_tumpang/features/home/view_models/home_view_model.dart';
import 'package:nak_tumpang/features/negotiation/view_models/negotiation_view_model.dart';
import 'package:nak_tumpang/features/payment/view_models/payment_view_model.dart';
import 'package:nak_tumpang/features/trips/view_models/my_trips_view_model.dart';
import 'package:nak_tumpang/features/subscriptions/view_models/subscription_view_model.dart';
import 'package:nak_tumpang/features/rewards/view_models/rewards_view_model.dart';

class AppProviders {
  static List<SingleChildWidget> get providers {
    return [
      ChangeNotifierProvider(
        create: (_) => HomeViewModel(),
      ),
      ChangeNotifierProvider(
        create: (_) => SubscriptionViewModel(),
      ),
      ChangeNotifierProvider(
        create: (_) => RewardsViewModel(),
      ),
      ChangeNotifierProvider(
        create: (_) => NegotiationViewModel(),
      ),
      ChangeNotifierProvider(
        create: (_) => PaymentViewModel(),
      ),
      ChangeNotifierProvider(create: (_) => MyTripsViewModel()),
    ];
  }
}