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
      // Registered globally so it survives navigation between screens, but
      // intentionally NOT fetched here: there's no signed-in user yet at
      // app startup (AuthGate hasn't resolved), and HomeScreen already
      // calls fetchCurrentUser() itself once it's actually mounted for a
      // logged-in user. Fetching here too caused a duplicate, hardcoded
      // call to race the real one and clobber its data.
      ChangeNotifierProvider(
        create: (_) => HomeViewModel(),
      ),
      // Registers the ViewModel globally so subscription list/detail screens share state
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
      // Future providers (e.g., AuthViewModel, MatchingViewModel) will go here
      ChangeNotifierProvider(create: (_) => MyTripsViewModel()),
    ];
  }
}