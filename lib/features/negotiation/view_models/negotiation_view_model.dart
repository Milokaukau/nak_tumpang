import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nak_tumpang/core/entities/tumpang_request.dart';
import 'package:nak_tumpang/features/negotiation/data/services/negotiation_supabase_service.dart';
import 'package:nak_tumpang/features/negotiation/utils/date_range_rules.dart';
import 'package:nak_tumpang/features/negotiation/utils/negotiation_error.dart';

class NegotiationViewModel extends ChangeNotifier {
  final NegotiationSupabaseService _service = NegotiationSupabaseService();
  final SupabaseClient _supabase = Supabase.instance.client;

  String? currentUserId;
  String? currentUserRole;
  String? currentTripId;

  bool isLoading = false;
  String? errorMessage;
  List<TumpangRequest> pendingRequests = [];
  List<TumpangRequest> completedRequests = [];

  final Map<String, Map<String, dynamic>> _userCache = {};
  late final StreamSubscription<AuthState> _authSubscription;

  NegotiationViewModel() {
    _initSession();
    _authSubscription = _supabase.auth.onAuthStateChange.listen((data) {
      _initSession();
    });
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
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
      if (currentUserId == null) {
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
        currentUserRole = userData?['role']?.toString().replaceAll("'", "") ?? 'passenger';
      }

      final isDriver = currentUserRole == 'driver';
      final tripTable = isDriver ? 'driver_trips' : 'passenger_trips';
      final tripIdColumn = isDriver ? 'driver_trip_id' : 'passenger_trip_id';

      final List<dynamic> trips = await _supabase
          .from(tripTable)
          .select('id')
          .eq('user_id', currentUserId!);

      final tripIds = trips.map((t) => t['id'] as String).toList();

      if (tripIds.isEmpty) {
        pendingRequests = [];
        completedRequests = [];
        isLoading = false;
        notifyListeners();
        return;
      }

      currentTripId = tripIds.first;

      final List<dynamic> rows = await _supabase
          .from('tumpang_request')
          .select()
          .inFilter(tripIdColumn, tripIds)
          .or('status.eq.pending,status.eq.negotiating,status.eq.completed');

      final allRequests = rows.map((row) {
        try {
          return TumpangRequest.fromJson(row);
        } catch (err, stack) {
          debugPrint('Error parsing row into TumpangRequest: $err\nRow: $row\n$stack');
          rethrow;
        }
      }).toList();

      pendingRequests = allRequests.where((r) => r.status != 'completed').toList();
      completedRequests = allRequests.where((r) => r.status == 'completed').toList();

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

  Future<void> acceptTerm(String requestId, String fieldPrefix) {
    return runNegotiationAction(() async {
      await _service.acceptNegotiationField(requestId: requestId, fieldPrefix: fieldPrefix);
      await refreshRequests();
    });
  }

  Future<void> proposeNewTerm({
    required String requestId,
    required String fieldPrefix,
    dynamic value,
    double? lat,
    double? lng,
  }) {
    if (currentUserId == null) return Future.value();

    return runNegotiationAction(() async {
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
    });
  }

  Future<void> proposeTumpangDateRange({
    required String requestId,
    required String startDate,
    required String endDate,
  }) {
    if (currentUserId == null) return Future.value();

    return runNegotiationAction(() async {
      final start = DateTime.tryParse(startDate);
      final end = DateTime.tryParse(endDate);
      if (start == null || end == null) {
        throw NegotiationException('Please choose a valid date range.');
      }

      final validationError = DateRangeRules.validate(start, end);
      if (validationError != null) {
        throw NegotiationException(validationError);
      }

      await _service.proposeTumpangDates(
        requestId: requestId,
        startDate: startDate,
        endDate: endDate,
        requestedById: currentUserId!,
      );
      await refreshRequests();
    });
  }

  Future<void> acceptTumpangDateRange(String requestId) {
    return runNegotiationAction(() async {
      await _service.acceptTumpangDates(requestId: requestId);
      await refreshRequests();
    });
  }

  Future<void> rejectEntireRequest(String requestId) {
    return runNegotiationAction(() async {
      await _service.rejectRequest(requestId);
      await refreshRequests();
    },
      fallbackMessage: "Couldn't reject the request. Please check your connection and try again.",
    );
  }

  /// Starts a "date only" extension: the driver just needs to accept a
  /// new end date, nothing else changes, no new deposit is charged.
  /// Returns the id of the new extension request.
  Future<String> requestDateOnlyExtension({
    required String subscriptionId,
    required DateTime newEndDate,
  }) {
    return runNegotiationAction(() async {
      if (currentUserId == null) {
        throw NegotiationException('You must be signed in to extend a subscription.');
      }
      final sub = await _fetchSubscriptionOrThrow(subscriptionId);
      final newRequestId = await _service.createExtensionRequest(
        subscription: sub,
        requestedById: currentUserId!,
        newEndDate: newEndDate,
        extensionType: 'date_only',
      );
      await refreshRequests();
      return newRequestId;
    });
  }

  /// Starts an "extend + renegotiate" request. Creates the extension with
  /// just a new end date to begin with — the passenger can then use the
  /// normal "Edit" flow on the resulting request to change pickup,
  /// dropoff, time, or fee, same as any other negotiation. Returns the id
  /// of the new extension request.
  Future<String> requestRenegotiatedExtension({
    required String subscriptionId,
    required DateTime newEndDate,
  }) {
    return runNegotiationAction(() async {
      if (currentUserId == null) {
        throw NegotiationException('You must be signed in to extend a subscription.');
      }
      final sub = await _fetchSubscriptionOrThrow(subscriptionId);
      final newRequestId = await _service.createExtensionRequest(
        subscription: sub,
        requestedById: currentUserId!,
        newEndDate: newEndDate,
        extensionType: 'renegotiate',
      );
      await refreshRequests();
      return newRequestId;
    });
  }

  /// Applies an extension request's agreed terms to the real subscription,
  /// once [TumpangRequest.isFullyAgreed] is true for it (i.e. the driver
  /// has accepted). Call this from the extension request's own
  /// NegotiationScreen once fully agreed, instead of routing through
  /// TumpangSummaryScreen — no new deposit/payment is involved.
  Future<void> finalizeExtension(String extensionRequestId) {
    return runNegotiationAction(() async {
      await _service.finalizeExtension(extensionRequestId);
      await refreshRequests();
    },
      fallbackMessage: "Couldn't finalize the extension. Please check your connection and try again.",
    );
  }

  Future<Map<String, dynamic>> _fetchSubscriptionOrThrow(String subscriptionId) async {
    final sub = await _supabase
        .from('tumpang_subscription')
        .select()
        .eq('id', subscriptionId)
        .maybeSingle();
    if (sub == null) {
      throw NegotiationException('Subscription not found.');
    }
    if (sub['status'] != 'active') {
      throw NegotiationException('This subscription is no longer active and cannot be extended.');
    }
    return sub;
  }

  /// Cancels an active subscription and marks its deposit for refund.
  /// (Refund processing itself - e.g. a Stripe refund call - happens
  /// wherever your payments/refund flow actually issues it; this just
  /// updates the subscription's own status/flag.)
  Future<void> cancelSubscription(String subscriptionId) {
    return runNegotiationAction(() async {
      await _supabase.from('tumpang_subscription').update({
        'status': 'completed',
        'deposit_refunded': false, // flips to true once the refund is actually issued
      }).eq('id', subscriptionId);
      await refreshRequests();
    },
      fallbackMessage: "Couldn't cancel the subscription. Please check your connection and try again.",
    );
  }
}