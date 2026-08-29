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

  final Map<String, Map<String, dynamic>> _userCache = {};
  Stream<List<TumpangRequest>>? pendingRequestsStream;

  Future<void> fetchActiveTripAndInitialize(String role, {String? fallbackUserId}) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      // 1. Get authenticated user ID from Auth session, or fallback if using custom IDs
      currentUserId = _supabase.auth.currentUser?.id ?? fallbackUserId ?? 'usr_driv_4412';
      currentUserRole = role;

      debugPrint('Initializing for User ID: $currentUserId as $role');

      // 2. Query driver_trips or passenger_trips for this user
      final tableName = role == 'driver' ? 'driver_trips' : 'passenger_trips';

      final dynamic tripData = await _supabase
          .from(tableName)
          .select('id')
          .eq('user_id', currentUserId!)
          .limit(1)
          .maybeSingle();

      debugPrint('Trip Query Result: $tripData');

      if (tripData != null && tripData['id'] != null) {
        currentTripId = tripData['id'] as String;
        debugPrint('Active Trip ID found: $currentTripId');

        // 3. Setup the real-time stream
        if (role == 'driver') {
          pendingRequestsStream = _service.streamRequestsForDriver(currentTripId!);
        } else {
          pendingRequestsStream = _service.streamRequestsForPassenger(currentTripId!);
        }
      } else {
        errorMessage = 'No active $role trip found for user $currentUserId';
        debugPrint(errorMessage);
      }
    } catch (e, stack) {
      errorMessage = 'Error loading trip: $e';
      debugPrint('Error: $e\n$stack');
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Stream<TumpangRequest?> singleRequestStream(String requestId) {
    return _service.streamSingleRequest(requestId);
  }

  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    if (_userCache.containsKey(userId)) return _userCache[userId];
    try {
      final data = await _supabase.from('users').select().eq('id', userId).maybeSingle();
      if (data != null) {
        _userCache[userId] = data;
        return data;
      }
    } catch (e) {
      debugPrint('Error fetching user: $e');
    }
    return null;
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
      debugPrint('Error fetching user by trip id: $e');
    }
    return null;
  }

  Future<void> acceptTerm(String requestId, String fieldPrefix) async {
    await _service.acceptNegotiationField(requestId: requestId, fieldPrefix: fieldPrefix);
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
  }

  Future<void> rejectEntireRequest(String requestId) async {
    await _service.rejectRequest(requestId);
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