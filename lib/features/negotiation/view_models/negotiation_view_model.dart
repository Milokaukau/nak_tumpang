// lib/features/negotiation/view_models/negotiation_view_model.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nak_tumpang/core/entities/tumpang_request.dart';
import 'package:nak_tumpang/features/negotiation/data/services/negotiation_supabase_service.dart';

class NegotiationViewModel extends ChangeNotifier {
  final NegotiationSupabaseService _service = NegotiationSupabaseService();
  final SupabaseClient _supabase = Supabase.instance.client;

  String? currentUserId;
  String? currentUserRole;
  String? currentTripId;

  bool isLoading = false;
  String? errorMessage;
  List<TumpangRequest> pendingRequests = [];

  final Map<String, Map<String, dynamic>> _userCache = {};

  Future<void> fetchActiveTripAndInitialize(String role, {String? fallbackUserId}) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      currentUserId = _supabase.auth.currentUser?.id ?? fallbackUserId ?? 'usr_driv_4412';
      currentUserRole = role;

      final tableName = role == 'driver' ? 'driver_trips' : 'passenger_trips';
      final dynamic tripData = await _supabase
          .from(tableName)
          .select('id')
          .eq('user_id', currentUserId!)
          .limit(1)
          .maybeSingle();

      if (tripData != null && tripData['id'] != null) {
        currentTripId = tripData['id'] as String;
        await refreshRequests();
      } else {
        errorMessage = 'No active $role trip found for user $currentUserId';
      }
    } catch (e) {
      errorMessage = 'Error loading trip: $e';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  // Pull-to-refresh action
  Future<void> refreshRequests() async {
    if (currentTripId == null || currentUserRole == null) return;
    try {
      if (currentUserRole == 'driver') {
        pendingRequests = await _service.fetchRequestsForDriver(currentTripId!);
      } else {
        pendingRequests = await _service.fetchRequestsForPassenger(currentTripId!);
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error refreshing requests: $e');
    }
  }

  Future<TumpangRequest?> getSingleRequest(String requestId) async {
    return _service.fetchSingleRequest(requestId);
  }

  Future<Map<String, dynamic>?> getUserProfileByTripId(String tripId, {required bool isDriverTrip}) async {
    if (_userCache.containsKey(tripId)) return _userCache[tripId];

    final tableName = isDriverTrip ? 'driver_trips' : 'passenger_trips';
    try {
      final res = await _supabase.from(tableName).select('users(*)').eq('id', tripId).maybeSingle();
      if (res != null && res['users'] != null) {
        final user = res['users'] as Map<String, dynamic>;
        _userCache[tripId] = user;
        return user;
      }
    } catch (e) {
      debugPrint('Error fetching user profile: $e');
    }
    return null;
  }

  Future<void> acceptTerm(String requestId, String fieldPrefix) async {
    await _service.acceptNegotiationField(requestId: requestId, fieldPrefix: fieldPrefix);
    await refreshRequests();
  }

  Future<void> proposeNewTerm({
    required String requestId,
    required String fieldPrefix,
    dynamic value,
    double? lat,
    double? lng,
  }) async {
    if (currentUserId == null) return;

    await _service.updateNegotiationField(
      requestId: requestId,
      fieldPrefix: fieldPrefix,
      value: value,
      lat: lat,
      lng: lng,
      requestedById: currentUserId!,
      isAccepted: false,
    );
    await refreshRequests();
  }

  Future<void> rejectEntireRequest(String requestId) async {
    await _service.rejectRequest(requestId);
    await refreshRequests();
  }

  Future<bool> finalizeAgreement(TumpangRequest request) async {
    return request.fee.isAccepted &&
        request.pickupTime.isAccepted &&
        request.pickupLocation.isAccepted &&
        request.dropoffLocation.isAccepted &&
        request.subscriptionStartDate.isAccepted &&
        request.subscriptionEndDate.isAccepted;
  }
}