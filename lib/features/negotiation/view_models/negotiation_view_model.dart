import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nak_tumpang/core/entities/tumpang_request.dart';
import 'package:nak_tumpang/features/negotiation/data/services/negotiation_supabase_service.dart';
import 'package:nak_tumpang/features/negotiation/utils/date_range_rules.dart';
import 'package:nak_tumpang/features/negotiation/utils/negotiation_error.dart';
import 'package:nak_tumpang/core/services/network_service.dart';
import 'package:nak_tumpang/features/negotiation/data/services/negotiation_local_service.dart';

class NegotiationViewModel extends ChangeNotifier {
  final NegotiationSupabaseService _service = NegotiationSupabaseService();
  final SupabaseClient _supabase = Supabase.instance.client;
  final NegotiationLocalService _localService = NegotiationLocalService();

  String? currentUserId;
  String? currentUserRole;
  String? currentTripId;

  bool isLoading = false;
  String? errorMessage;
  List<TumpangRequest> pendingRequests = [];
  List<TumpangRequest> completedRequests = [];

  final Map<String, Map<String, dynamic>> _userCache = {};
  late final StreamSubscription<AuthState> _authSubscription;

  bool get isOffline => NetworkService.isOfflineNotifier.value;

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

      List<dynamic> rows;

      if (isOffline) {
        // Read from SQLite Cache
        final p = await _localService.getOfflineRequests('pending');
        final n = await _localService.getOfflineRequests('negotiating');
        final c = await _localService.getOfflineRequests('completed');
        final r = await _localService.getOfflineRequests('rejected');
        final x = await _localService.getOfflineRequests('cancelled');
        rows = [...p, ...n, ...c, ...r, ...x];

        // Mock a tripId so the UI doesn't break
        if (rows.isNotEmpty) {
          currentTripId = isDriver ? rows.first['driver_trip_id'] : rows.first['passenger_trip_id'];
        }
      } else {
        // Fetch from Supabase
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

        rows = await _supabase
            .from('tumpang_request')
            .select()
            .inFilter(tripIdColumn, tripIds)
            .or('status.eq.pending,status.eq.negotiating,status.eq.completed,status.eq.rejected,status.eq.cancelled');

        // Safely attempt to cache without crashing the UI
        try {
          await _localService.cacheTumpangRequests(rows.cast<Map<String, dynamic>>());
        } catch (e) {
          debugPrint('Could not cache request offline due to strict foreign keys: $e');
        }
      } // <-- The missing bracket has been restored here!

      final allRequests = rows.map((row) {
        try {
          return TumpangRequest.fromJson(row);
        } catch (err, stack) {
          debugPrint('Error parsing row into TumpangRequest: $err\nRow: $row\n$stack');
          rethrow;
        }
      }).toList();

      pendingRequests = allRequests
          .where((r) => r.status == 'pending' || r.status == 'negotiating')
          .toList();

      completedRequests = allRequests
          .where((r) => r.status == 'completed' || r.status == 'rejected' || r.status == 'cancelled')
          .toList();

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
    if (isOffline) {
      final all = [...pendingRequests, ...completedRequests];
      return all.firstWhere((r) => r.id == requestId);
    }
    return _service.fetchSingleRequest(requestId);
  }

  Future<Map<String, dynamic>?> getUserProfileByTripId(String tripId, {required bool isDriverTrip}) async {
    if (_userCache.containsKey(tripId)) return _userCache[tripId];
    if (isOffline) return null; // Can't fetch new profiles offline

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
    if (isOffline) throw NegotiationException('You cannot accept terms while offline.');
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
    if (isOffline) throw NegotiationException('You cannot propose terms while offline.');
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
    if (isOffline) throw NegotiationException('You cannot propose terms while offline.');
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
    if (isOffline) throw NegotiationException('You cannot accept dates while offline.');
    return runNegotiationAction(() async {
      await _service.acceptTumpangDates(requestId: requestId);
      await refreshRequests();
    });
  }

  Future<void> rejectEntireRequest(String requestId) {
    if (isOffline) throw NegotiationException('You cannot reject requests while offline.');
    return runNegotiationAction(() async {
      await _service.rejectRequest(requestId);
      await refreshRequests();
    },
      fallbackMessage: "Couldn't reject the request. Please check your connection and try again.",
    );
  }

  Future<void> cancelRequest(String requestId) {
    if (isOffline) throw NegotiationException('You cannot cancel requests while offline.');
    return runNegotiationAction(() async {
      await _supabase.from('tumpang_request').update({
        'status': 'cancelled',
      }).eq('id', requestId);
      await refreshRequests();
    },
      fallbackMessage: "Couldn't cancel the request. Please check your connection and try again.",
    );
  }

  Future<void> extendSubscription({
    required String subscriptionId,
    required DateTime newEndDate,
    required double monthlyFee,
  }) async {
    if (isOffline) throw NegotiationException('You cannot extend subscriptions while offline.');
    await _supabase.from('tumpang_subscription').update({
      'subscription_end_date': newEndDate.toIso8601String().split('T').first,
      'status': 'active',
    }).eq('id', subscriptionId);

    final paymentId = 'pay_${DateTime.now().millisecondsSinceEpoch}';
    await _supabase.from('payments').insert({
      'id': paymentId,
      'tumpang_subscription_id': subscriptionId,
      'month': newEndDate.month,
      'year': newEndDate.year,
      'due_date': DateTime.now().toIso8601String(),
      'paid_at': null,
      'amount': monthlyFee,
    });

    notifyListeners();
  }

  Future<void> endSubscription(String subscriptionId) async {
    if (isOffline) throw NegotiationException('You cannot end subscriptions while offline.');
    await _supabase.from('tumpang_subscription').update({
      'status': 'completed',
      'deposit_status': 'refunded',
    }).eq('id', subscriptionId);

    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> getOpenInvoices(String subscriptionId) async {
    if (isOffline) return [];
    final rows = await _supabase
        .from('payments')
        .select()
        .eq('tumpang_subscription_id', subscriptionId)
        .filter('paid_at', 'is', null);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  Future<void> reportCannotFetchDay({
    required String subscriptionId,
    required DateTime date,
    String? reason,
  }) async {
    throw UnimplementedError();
  }

  static List<Map<String, dynamic>> calculateInvoicePeriods({
    required int subscriptionDays,
    required double dailyFee,
    int depositDays = 60,
    int invoiceCycleDays = 30,
  }) {
    final periods = <Map<String, dynamic>>[];
    int remaining = subscriptionDays - depositDays;
    int cursor = depositDays;
    while (remaining > 0) {
      final periodDays = remaining >= invoiceCycleDays ? invoiceCycleDays : remaining;
      periods.add({
        'startDay': cursor,
        'endDay': cursor + periodDays,
        'days': periodDays,
        'amount': dailyFee * periodDays,
      });
      cursor += periodDays;
      remaining -= periodDays;
    }
    return periods;
  }
}