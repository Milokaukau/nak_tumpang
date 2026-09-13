import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  static const String _roleCacheKeyPrefix = 'nak_tumpang_cached_role_';

  String? currentUserId;
  String? currentUserRole;
  String? currentTripId;

  int _sessionGeneration = 0;

  bool isLoading = false;
  String? errorMessage;
  List<TumpangRequest> pendingRequests = [];
  List<TumpangRequest> completedRequests = [];

  final Map<String, Map<String, dynamic>> _userCache = {};
  final Map<String, String> _tripNameCache = {};
  late final StreamSubscription<AuthState> _authSubscription;

  bool get isOffline => NetworkService.isOfflineNotifier.value;

  NegotiationViewModel() {
    _initSession();
    _authSubscription = _supabase.auth.onAuthStateChange.listen((data) async {
      final newUserId = data.session?.user.id;

      final isAccountChange = data.event == AuthChangeEvent.signedOut ||
          (data.event == AuthChangeEvent.signedIn && currentUserId != null && newUserId != currentUserId);

      if (isAccountChange) {
        _sessionGeneration++;
        pendingRequests.clear();
        completedRequests.clear();
        _userCache.clear();
        _tripNameCache.clear();
        currentUserRole = null;
        currentUserId = null;
        isLoading = false;
        notifyListeners();

        try {
          await _localService.clearRequestsCache();
        } catch (e) {
          debugPrint('Failed to clear local negotiation cache on account change: $e');
        }
      }

      await _initSession();
    });
  }

  Future<void> clearLocalCacheOnLogout() async {
    _sessionGeneration++;
    pendingRequests.clear();
    completedRequests.clear();
    _userCache.clear();
    _tripNameCache.clear();
    currentUserRole = null;
    currentUserId = null;
    isLoading = false;
    notifyListeners();

    try {
      await _localService.clearRequestsCache();
    } catch (e) {
      debugPrint('Failed to clear local negotiation cache on logout: $e');
    }
  }

  Future<void> _persistRole(String userId, String role) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_roleCacheKeyPrefix$userId', role);
    } catch (e) {
      debugPrint('Could not persist local role cache: $e');
    }
  }

  Future<String?> _readCachedRole(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('$_roleCacheKeyPrefix$userId');
    } catch (e) {
      debugPrint('Could not read local role cache: $e');
      return null;
    }
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }

  Future<void> _initSession() async {
    final generation = _sessionGeneration;
    final user = _supabase.auth.currentUser;
    final sessionUserId = user?.id;
    currentUserId = sessionUserId;

    if (user != null && sessionUserId != null) {
      final cachedRole = await _readCachedRole(sessionUserId);

      if (generation != _sessionGeneration || _supabase.auth.currentUser?.id != sessionUserId) return;
      currentUserRole ??= cachedRole;

      try {
        final userData = await _supabase
            .from('users')
            .select('role')
            .eq('id', sessionUserId)
            .maybeSingle();

        if (generation != _sessionGeneration || _supabase.auth.currentUser?.id != sessionUserId) return;

        final remoteRole = userData?['role']?.toString().replaceAll("'", "") ?? 'passenger';
        currentUserRole = remoteRole;
        await _persistRole(sessionUserId, remoteRole);
      } catch (e) {
        debugPrint('Error refreshing role from Supabase: $e');
      }

      if (generation != _sessionGeneration || _supabase.auth.currentUser?.id != sessionUserId) return;

      currentUserRole ??= 'passenger';
      await fetchRequests();
    } else {
      currentUserRole = null;
      pendingRequests.clear();
      completedRequests.clear();
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchRequests() async {
    final generation = _sessionGeneration;
    final user = _supabase.auth.currentUser;
    final sessionUserId = user?.id;

    if (sessionUserId == null) {
      currentUserId = null;
      isLoading = false;
      notifyListeners();
      return;
    }

    currentUserId = sessionUserId;
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    bool isCurrentSessionValid() {
      return generation == _sessionGeneration && _supabase.auth.currentUser?.id == sessionUserId;
    }

    try {
      if (currentUserRole == null) {
        final cachedRole = await _readCachedRole(sessionUserId);
        if (!isCurrentSessionValid()) return;
        currentUserRole = cachedRole;
      }

      if (currentUserRole == null && !isOffline) {
        try {
          final userData = await _supabase
              .from('users')
              .select('role')
              .eq('id', sessionUserId)
              .maybeSingle();

          if (!isCurrentSessionValid()) return;

          currentUserRole = userData?['role']?.toString().replaceAll("'", "") ?? 'passenger';
          await _persistRole(sessionUserId, currentUserRole!);
        } catch (e) {
          debugPrint('Error fetching role in fetchRequests(): $e');
        }
      }

      if (!isCurrentSessionValid()) return;
      currentUserRole ??= 'passenger';

      final isDriver = currentUserRole == 'driver';
      final tripTable = isDriver ? 'driver_trips' : 'passenger_trips';
      final tripIdColumn = isDriver ? 'driver_trip_id' : 'passenger_trip_id';

      List<dynamic> rows;

      if (isOffline) {
        final p = await _localService.getOfflineRequests('pending');
        final n = await _localService.getOfflineRequests('negotiating');
        final c = await _localService.getOfflineRequests('completed');
        final r = await _localService.getOfflineRequests('rejected');
        final x = await _localService.getOfflineRequests('cancelled');

        if (!isCurrentSessionValid()) return;
        rows = [...p, ...n, ...c, ...r, ...x];

        if (rows.isNotEmpty) {
          currentTripId = isDriver ? rows.first['driver_trip_id'] : rows.first['passenger_trip_id'];
        }
      } else {
        final List<dynamic> trips = await _supabase
            .from(tripTable)
            .select()
            .eq('user_id', sessionUserId);

        if (!isCurrentSessionValid()) return;

        for (final t in trips) {
          final id = t['id']?.toString();
          final name = t['trip_name'] ?? t['name'] ?? t['title'];
          if (id != null && name != null) {
            _tripNameCache[id] = name.toString();
          }
        }

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

        if (!isCurrentSessionValid()) return;

        try {
          await _localService.cacheTumpangRequests(rows.cast<Map<String, dynamic>>());
        } catch (e) {
          debugPrint('Could not cache request offline due to strict foreign keys: $e');
        }
      }

      final allRequests = rows.map((row) {
        try {
          return TumpangRequest.fromJson(row);
        } catch (err, stack) {
          debugPrint('Error parsing row into TumpangRequest: $err\nRow: $row\n$stack');
          rethrow;
        }
      }).toList();

      if (!isCurrentSessionValid()) return;

      pendingRequests = allRequests
          .where((r) => r.status == 'pending' || r.status == 'negotiating')
          .toList();

      completedRequests = allRequests
          .where((r) => r.status == 'completed' || r.status == 'rejected' || r.status == 'cancelled')
          .toList();

      errorMessage = null;
    } catch (e, stack) {
      if (!isCurrentSessionValid()) return;
      debugPrint('Error fetching requests: $e\n$stack');
      errorMessage = 'Failed to load requests: $e';
    } finally {
      if (isCurrentSessionValid()) {
        isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> refreshRequests() async {
    await fetchRequests();
  }

  Future<TumpangRequest?> getSingleRequest(String requestId) async {
    if (isOffline) {
      final all = [...pendingRequests, ...completedRequests];
      for (final r in all) {
        if (r.id == requestId) return r;
      }
      return null;
    }

    final activeUser = _supabase.auth.currentUser;
    if (activeUser == null) return null;

    return _service.fetchSingleRequest(requestId);
  }

  Future<Map<String, dynamic>?> getUserProfileByTripId(String tripId, {required bool isDriverTrip}) async {
    if (_userCache.containsKey(tripId)) return _userCache[tripId];
    if (isOffline) return null;

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

  String getCachedTripName(String tripId) {
    if (_tripNameCache.containsKey(tripId) && _tripNameCache[tripId]!.isNotEmpty) {
      return _tripNameCache[tripId]!;
    }
    if (_userCache.containsKey(tripId)) {
      final cachedData = _userCache[tripId];
      if (cachedData != null && cachedData['trip_name'] != null) {
        return cachedData['trip_name'].toString();
      }
    }
    return 'Your Trip';
  }

  Future<T> runNegotiationAction<T>(
      Future<T> Function() action, {
        String fallbackMessage = 'An error occurred during negotiation.',
      }) async {
    final startGeneration = _sessionGeneration;
    final startUserId = currentUserId;

    try {
      final result = await action();

      if (startGeneration != _sessionGeneration || startUserId != currentUserId) {
        throw NegotiationException('Session changed. Request discarded.');
      }

      return result;
    } on PostgrestException catch (e) {
      throw NegotiationException(e.message);
    } catch (e) {
      if (e is NegotiationException) rethrow;
      throw NegotiationException(fallbackMessage);
    }
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
    final activeUserId = _supabase.auth.currentUser?.id;
    if (activeUserId == null) throw NegotiationException('You must be signed in to propose terms.');

    return runNegotiationAction(() async {
      await _service.updateNegotiationField(
        requestId: requestId,
        fieldPrefix: fieldPrefix,
        value: value,
        lat: lat,
        lng: lng,
        requestedById: activeUserId,
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
    final activeUserId = _supabase.auth.currentUser?.id;
    if (activeUserId == null) throw NegotiationException('You must be signed in to propose dates.');

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
        requestedById: activeUserId,
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

  Future<Map<String, dynamic>?> getSubscriptionById(String subscriptionId) async {
    if (isOffline) return null;
    try {
      final row = await _supabase
          .from('tumpang_subscription')
          .select()
          .eq('id', subscriptionId)
          .maybeSingle();
      return row;
    } catch (e) {
      debugPrint('Error fetching subscription $subscriptionId: $e');
      return null;
    }
  }

  Future<String> submitExtensionRequest({
    required Map<String, dynamic> subscription,
    required DateTime newEndDate,
    required String extensionType,
    String? overridePickupName,
    double? overridePickupLat,
    double? overridePickupLng,
    String? overrideDropoffName,
    double? overrideDropoffLat,
    double? overrideDropoffLng,
    String? overridePickupTime,
    double? overrideFee,
  }) {
    if (isOffline) throw NegotiationException('You cannot request an extension while offline.');

    final liveUserId = _supabase.auth.currentUser?.id ?? currentUserId;
    if (liveUserId == null) throw NegotiationException('You must be signed in to request an extension.');

    return runNegotiationAction<String>(
          () async {
        final requestId = await _service.createExtensionRequest(
          subscription: subscription,
          requestedById: liveUserId,
          newEndDate: newEndDate,
          extensionType: extensionType,
          overridePickupName: overridePickupName,
          overridePickupLat: overridePickupLat,
          overridePickupLng: overridePickupLng,
          overrideDropoffName: overrideDropoffName,
          overrideDropoffLat: overrideDropoffLat,
          overrideDropoffLng: overrideDropoffLng,
          overridePickupTime: overridePickupTime,
          overrideFee: overrideFee,
        );
        await refreshRequests();
        return requestId;
      },
      fallbackMessage: "Couldn't submit the extension request. Please check your connection and try again.",
    );
  }

  Future<Map<String, dynamic>?> getSummaryData(String requestId) async {
    final req = await getSingleRequest(requestId);
    if (req == null) return null;

    double oldDeposit = 0.0;
    if (req.isExtension && req.extendsSubscriptionId != null) {
      final oldSub = await getSubscriptionById(req.extendsSubscriptionId!);
      oldDeposit = double.tryParse(oldSub?['deposit']?.toString() ?? '') ?? 0.0;
    }

    return {
      'request': req,
      'oldDeposit': oldDeposit,
    };
  }

  Future<void> finalizeExtensionRequest({
    required String extensionRequestId,
    required double additionalDeposit,
  }) {
    if (isOffline) throw NegotiationException('You cannot finalize an extension while offline.');
    return runNegotiationAction(() async {
      await _service.finalizeExtension(extensionRequestId, additionalDeposit: additionalDeposit);
      await refreshRequests();
    });
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