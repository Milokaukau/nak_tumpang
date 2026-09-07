import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nak_tumpang/features/trips/data/services/trip_supabase_service.dart';

enum TripStatus { active, negotiating, none }

class MyTripsViewModel extends ChangeNotifier {
  final TripSupabaseService _tripService = TripSupabaseService();
  final GoTrueClient _auth = Supabase.instance.client.auth;

  bool isLoading = true;
  String currentUserRole = 'passenger';
  List<Map<String, dynamic>> myTrips = [];
  Set<String> activeSubbedTripIds = {};
  Set<String> negotiatingTripIds = {};

  int _loadId = 0;

  Future<void> loadMyTrips() async {
    final requestId = ++_loadId;
    isLoading = true;

    myTrips = [];
    activeSubbedTripIds = {};
    negotiatingTripIds = {};
    notifyListeners();

    final user = _auth.currentUser;
    if (user == null) {
      if (requestId == _loadId) {
        isLoading = false;
        notifyListeners();
      }
      return;
    }

    final role = await _tripService.getUserRole(user.id);
    if (requestId != _loadId) return;

    if (role == null) {
      isLoading = false;
      notifyListeners();
      return;
    }

    currentUserRole = role;

    final results = await Future.wait([
      _tripService.fetchMyTrips(user.id, role),
      _tripService.fetchActiveSubbedTripIds(user.id, role),
      _tripService.fetchNegotiatingTripIds(user.id, role),
    ]);
    if (requestId != _loadId) return;

    myTrips = results[0] as List<Map<String, dynamic>>;
    activeSubbedTripIds = results[1] as Set<String>;
    negotiatingTripIds = results[2] as Set<String>;

    isLoading = false;
    notifyListeners();
  }

  TripStatus getTripStatus(String tripId) {
    if (activeSubbedTripIds.contains(tripId)) return TripStatus.active;
    if (negotiatingTripIds.contains(tripId)) return TripStatus.negotiating;
    return TripStatus.none;
  }

  Future<bool> removeTrip(String tripId) async {
    try {
      await _tripService.deleteTrip(tripId, currentUserRole);
      // Remove locally to save an API call
      myTrips.removeWhere((trip) => trip['id'] == tripId);
      notifyListeners();
      return true;
    } catch (e) {
      print('⚠️ Error deleting trip: $e');
      return false;
    }
  }
}