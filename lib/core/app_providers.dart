import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:nak_tumpang/features/home/view_models/home_view_model.dart';

class AppProviders {
  static List<SingleChildWidget> get providers {
    return [
      // Registers the ViewModel globally so any screen can access the user's data.
      // fetchCurrentUser() no-ops harmlessly if created before login (no
      // session yet) — HomeScreen.initState re-triggers it once a real
      // session exists.
      ChangeNotifierProvider(
        create: (_) => HomeViewModel()..fetchCurrentUser(),
      ),
      // Future providers (e.g., AuthViewModel, MatchingViewModel) will go here
    ];
  }
}