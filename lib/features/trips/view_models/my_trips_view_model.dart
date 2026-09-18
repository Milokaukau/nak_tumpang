import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nak_tumpang/features/trips/data/services/trip_supabase_service.dart';
import 'package:nak_tumpang/core/services/network_service.dart';
import 'package:nak_tumpang/features/home/data/services/home_local_service.dart';

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

    String? role;
    try {
      if (NetworkService.isOfflineNotifier.value) {
        role = await HomeLocalService().getUserRole(user.id);
      } else {
        role = await _tripService.getUserRole(user.id);
      }
    } catch (e) {
      debugPrint('⚠️ MyTrips role fetch error: $e');
      if (requestId == _loadId) {
        isLoading = false;
        notifyListeners();
      }
      return;
    }

    if (requestId != _loadId) return;

    if (role == null) {
      isLoading = false;
      notifyListeners();
      return;
    }

    currentUserRole = role;

    if (NetworkService.isOfflineNotifier.value) {
      try {
        final isPassenger = role == 'passenger';
        myTrips = await HomeLocalService().getCachedUserTrips(user.id, isForPassenger: isPassenger);
        final localSubs = await HomeLocalService().getCachedSubscriptions(user.id, isForPassenger: isPassenger);

        activeSubbedTripIds = localSubs.map((s) => (isPassenger ? s['passenger_trip_id'] : s['driver_trip_id']).toString()).toSet();
        negotiatingTripIds = {};
      } catch (e) {
        debugPrint('⚠️ SQLite MyTrips fetch error: $e');
      }
    } else {
      try {
        final results = await Future.wait([
          _tripService.fetchMyTrips(user.id, role),
          _tripService.fetchActiveSubbedTripIds(user.id, role),
          _tripService.fetchNegotiatingTripIds(user.id, role),
        ]);
        if (requestId != _loadId) return;

        myTrips = results[0] as List<Map<String, dynamic>>;
        activeSubbedTripIds = results[1] as Set<String>;
        negotiatingTripIds = results[2] as Set<String>;
      } catch (e) {
        debugPrint('⚠️ Supabase MyTrips fetch error: $e');
      }
    }

    if (requestId != _loadId) return;
    isLoading = false;
    notifyListeners();
  }

  TripStatus getTripStatus(String tripId) {
    if (activeSubbedTripIds.contains(tripId)) return TripStatus.active;
    if (negotiatingTripIds.contains(tripId)) return TripStatus.negotiating;
    return TripStatus.none;
  }

  Future<bool> removeTrip(String tripId) async {
    if (NetworkService.isOfflineNotifier.value) return false;

    try {
      await _tripService.deleteTrip(tripId, currentUserRole);
      myTrips.removeWhere((trip) => trip['id'] == tripId);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('⚠️ Error deleting trip: $e');
      return false;
    }
  }

  Future<String?> getNegotiatingRequestId(String tripId) async {
    if (NetworkService.isOfflineNotifier.value) return null;
    return _tripService.findNegotiatingRequestId(tripId);
  }

  Future<Map<String, dynamic>?> getActiveSubscription(String tripId, String role) async {
    if (NetworkService.isOfflineNotifier.value) return null;
    return _tripService.fetchActiveSubscriptionForTrip(tripId, role);
  }
}