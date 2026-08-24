import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:nak_tumpang/features/home/view_models/home_view_model.dart';

class AppProviders {
  static List<SingleChildWidget> get providers {
    return [
      // Registers the ViewModel globally so any screen can access the Passenger data
      ChangeNotifierProvider(
        create: (_) => HomeViewModel()..fetchMockPassenger(),
      ),
      // Future providers (e.g., AuthViewModel, MatchingViewModel) will go here
    ];
  }
}