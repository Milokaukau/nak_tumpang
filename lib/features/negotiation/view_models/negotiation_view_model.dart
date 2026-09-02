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

  NegotiationViewModel() {
    _initSession();
    _supabase.auth.onAuthStateChange.listen((data) {
      _initSession();
    });
  }

  Future<void> _initSession() async {
    final user = _supabase.auth.currentUser;
    if (user != null) {
      currentUserId = user.id;
      try {
        final userData = await _supabase
            .from('users')
            .select('role')
            .eq('id', currentUserId!)
            .maybeSingle();

        currentUserRole = userData?['role']?.toString().replaceAll("'", "") ?? 'passenger';
        await fetchRequests();
      } catch (e) {
        debugPrint('Error initializing session: $e');
      }
    }
  }

  Future<void> fetchRequests() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      currentUserId = _supabase.auth.currentUser?.id;
      debugPrint('DEBUG[1] currentUserId = $currentUserId');
      if (currentUserId == null) {
        debugPrint('DEBUG[1a] Bailing out early: no authenticated user.');
        isLoading = false;
        notifyListeners();
        return;
      }

      if (currentUserRole == null) {
        final userData = await _supabase
            .from('users')
            .select('role')
            .eq('id', currentUserId!)
            .maybeSingle();
        debugPrint('DEBUG[2] users row for role lookup = $userData');
        currentUserRole = userData?['role']?.toString().replaceAll("'", "") ?? 'passenger';
      }
      debugPrint('DEBUG[3] currentUserRole (final) = $currentUserRole');

      final isDriver = currentUserRole == 'driver';
      final tripTable = isDriver ? 'driver_trips' : 'passenger_trips';
      final tripIdColumn = isDriver ? 'driver_trip_id' : 'passenger_trip_id';
      debugPrint('DEBUG[4] isDriver=$isDriver tripTable=$tripTable tripIdColumn=$tripIdColumn');

      // 1. Fetch all trip IDs belonging to current user
      final List<dynamic> trips = await _supabase
          .from(tripTable)
          .select('id')
          .eq('user_id', currentUserId!);

      debugPrint('DEBUG[5] raw trips for user in $tripTable = $trips');

      final tripIds = trips.map((t) => t['id'] as String).toList();
      debugPrint('DEBUG[6] tripIds = $tripIds');

      if (tripIds.isEmpty) {
        debugPrint('DEBUG[6a] Bailing out early: user has zero rows in $tripTable.');
        pendingRequests = [];
        isLoading = false;
        notifyListeners();
        return;
      }

      currentTripId = tripIds.first;

      // 2. Fetch all requests matching any of the user's trips with inFilter
      final List<dynamic> rows = await _supabase
          .from('tumpang_request')
          .select()
          .inFilter(tripIdColumn, tripIds)
          .or('status.eq.pending,status.eq.negotiating');

      debugPrint('==== FETCHED ${rows.length} ROWS FROM SUPABASE: $rows ====');

      pendingRequests = rows.map((row) {
        try {
          return TumpangRequest.fromJson(row);
        } catch (err, stack) {
          debugPrint('Error parsing row into TumpangRequest: $err\nRow: $row\n$stack');
          rethrow;
        }
      }).toList();

      errorMessage = null;
    } catch (e, stack) {
      debugPrint('Error fetching requests: $e\n$stack');
      errorMessage = 'Failed to load requests: $e';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshRequests() async {
    await fetchRequests();
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