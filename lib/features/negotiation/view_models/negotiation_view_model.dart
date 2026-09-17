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

  // SQLITE: All offline reads/writes for negotiation requests go through this
  // service, which wraps the on-device SQLite database (via LocalDbService)
  // and operates on a single table: `tumpang_request`. See
  // negotiation_local_service.dart for the actual queries.
  final NegotiationLocalService _localService = NegotiationLocalService();

  // SHARED PREFERENCES: key prefix used to cache the current user's role
  // ('driver' / 'passenger') in on-device key-value storage (shared_preferences
  // package), so the app still knows the role instantly on next launch/offline
  // without waiting on a Supabase round trip. Actual key looks like
  // "nak_tumpang_cached_role_<userId>" - see _persistRole() / _readCachedRole().
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
  final Map<String, Map<String, dynamic>> _scheduleCache = {};

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
        _scheduleCache.clear();
        currentUserRole = null;
        currentUserId = null;
        isLoading = false;
        notifyListeners();

        try {
          // SQLITE: wipes every row of the local `tumpang_request` table so
          // the previous account's cached requests can't leak into the new
          // session. See NegotiationLocalService.clearRequestsCache().
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
    _scheduleCache.clear();
    currentUserRole = null;
    currentUserId = null;
    isLoading = false;
    notifyListeners();

    try {
      // SQLITE: same table wipe as above, called explicitly from the
      // logout flow as an extra safeguard (doesn't wait for the
      // onAuthStateChange listener to fire first).
      await _localService.clearRequestsCache();
    } catch (e) {
      debugPrint('Failed to clear local negotiation cache on logout: $e');
    }
  }

  // SHARED PREFERENCES (write): stores the resolved role for [userId] under
  // key "nak_tumpang_cached_role_<userId>" in the device's shared_preferences
  // store, so _readCachedRole() can restore it instantly on the next app
  // launch or while offline, without hitting Supabase.
  Future<void> _persistRole(String userId, String role) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_roleCacheKeyPrefix$userId', role);
    } catch (e) {
      debugPrint('Could not persist local role cache: $e');
    }
  }

  // SHARED PREFERENCES (read): retrieves the role previously saved by
  // _persistRole() for [userId] from the same "nak_tumpang_cached_role_<userId>"
  // key, so the app remembers the user's role across restarts and while offline.
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
      // SHARED PREFERENCES: fast local read so the UI has a role to show
      // immediately, before/without the Supabase round trip below.
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
        // SHARED PREFERENCES: refresh the cached role now that we have the
        // authoritative value from Supabase.
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
        // SHARED PREFERENCES: role not in memory yet - try the local cache
        // before falling back to a network call further down.
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
          // SHARED PREFERENCES: persist so the next cold start / offline
          // session can skip this network call entirely.
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
        // SQLITE: no network - read every status bucket straight out of the
        // local `tumpang_request` table (via NegotiationLocalService /
        // LocalDbService's readOnlyDatabase) instead of hitting Supabase.
        // sessionUserId scopes the query to `WHERE owner_id = ?` so cached
        // rows from a different account on the same device aren't returned.
        // FIX: Passed sessionUserId to local calls
        final p = await _localService.getOfflineRequests('pending', sessionUserId);
        final n = await _localService.getOfflineRequests('negotiating', sessionUserId);
        final c = await _localService.getOfflineRequests('completed', sessionUserId);
        final r = await _localService.getOfflineRequests('rejected', sessionUserId);
        final x = await _localService.getOfflineRequests('cancelled', sessionUserId);

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
          // SQLITE: mirror what we just fetched from Supabase into the local
          // `tumpang_request` table (upsert/replace) so the same data is
          // available next time the app is offline. sessionUserId is stored
          // as `owner_id` on each row for the account-scoping described above.
          // FIX: Passed sessionUserId to local calls
          await _localService.cacheTumpangRequests(rows.cast<Map<String, dynamic>>(), sessionUserId);
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

      // FIX: Require the active user ID to fetch from offline cache safely
      final activeUserId = _supabase.auth.currentUser?.id ?? currentUserId;
      if (activeUserId != null) {
        // SQLITE: in-memory lists above were empty/missed - fall back to a
        // direct single-row lookup in the local `tumpang_request` table
        // (`WHERE id = ? AND owner_id = ?`), so a deep link / notification
        // opened straight into this screen still works offline even before
        // fetchRequests() has populated the in-memory lists.
        final row = await _localService.getOfflineRequestById(requestId, activeUserId);
        if (row != null) {
          return TumpangRequest.fromJson(row);
        }
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

  Future<Map<String, dynamic>?> getPassengerSchedule(String passengerTripId) async {
    if (_scheduleCache.containsKey(passengerTripId)) return _scheduleCache[passengerTripId];
    if (isOffline) return null;

    try {
      final row = await _supabase
          .from('passenger_trips')
          .select('active_monday, active_tuesday, active_wednesday, active_thursday, active_friday, active_saturday, active_sunday')
          .eq('id', passengerTripId)
          .maybeSingle();

      if (row != null) {
        _scheduleCache[passengerTripId] = row;
        return row;
      }
    } catch (e) {
      debugPrint('Error fetching passenger schedule: $e');
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

    Map<String, dynamic>? schedule;
    if (!isOffline) {
      try {
        final trip = await _supabase
            .from('passenger_trips')
            .select('active_monday, active_tuesday, active_wednesday, active_thursday, active_friday, active_saturday, active_sunday')
            .eq('id', req.passengerTripId)
            .maybeSingle();
        if (trip != null) schedule = trip;
      } catch (e) {
        debugPrint('Error fetching passenger schedule for summary: $e');
      }
    }

    return {
      'request': req,
      'schedule': schedule,
    };
  }

  Future<void> finalizeExtensionRequest({
    required String extensionRequestId,
    required double additionalDeposit,
    required String paymentIntentId,
  }) {
    if (isOffline) throw NegotiationException('You cannot finalize an extension while offline.');
    // NOTE: additionalDeposit is intentionally not forwarded to the service -
    // the server derives the real amount from the PaymentIntent itself. It's
    // kept as a parameter here only so callers can still validate/display
    // the amount they expect to be charged before calling this.
    return runNegotiationAction(() async {
      await _service.finalizeExtension(
        extensionRequestId,
        paymentIntentId: paymentIntentId,
      );
      await refreshRequests();
    });
  }

  static bool isDayActive(DateTime date, Map<String, dynamic> schedule) {
    switch (date.weekday) {
      case DateTime.monday:
        return schedule['active_monday'] == true;
      case DateTime.tuesday:
        return schedule['active_tuesday'] == true;
      case DateTime.wednesday:
        return schedule['active_wednesday'] == true;
      case DateTime.thursday:
        return schedule['active_thursday'] == true;
      case DateTime.friday:
        return schedule['active_friday'] == true;
      case DateTime.saturday:
        return schedule['active_saturday'] == true;
      case DateTime.sunday:
        return schedule['active_sunday'] == true;
      default:
        return false;
    }
  }

  Future<Map<String, dynamic>> createDepositPaymentIntent({
    required String requestId,
  }) async {
    if (isOffline) throw NegotiationException('You cannot process a payment while offline.');

    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      return await _service.createDepositPaymentIntent(requestId: requestId);
    } catch (e) {
      errorMessage = 'Unable to prepare the deposit payment.';
      rethrow;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> createSubscriptionAfterDeposit({
    required TumpangRequest request,
    required double deposit,
    required String paymentIntentId,
  }) async {
    if (deposit <= 0) throw NegotiationException('Deposit amount must be greater than RM 0.');
    if (isOffline) throw NegotiationException('You cannot complete a subscription while offline.');

    // NOTE: deposit is validated above but intentionally not forwarded to
    // the service - the server derives the real amount from the
    // PaymentIntent itself rather than trusting a client-supplied figure.
    await runNegotiationAction(() async {
      await _service.createSubscriptionAfterDeposit(
        request: request,
        paymentIntentId: paymentIntentId,
      );
      await refreshRequests();
    });
  }

  static int countActiveDays(
      DateTime start,
      DateTime end,
      Map<String, dynamic> schedule,
      ) {
    if (end.isBefore(start)) return 0;

    var count = 0;
    for (var date = DateTime(start.year, start.month, start.day);
    !date.isAfter(end);
    date = DateTime(date.year, date.month, date.day + 1)) {
      if (isDayActive(date, schedule)) count++;
    }
    return count;
  }

  static List<Map<String, dynamic>> calculateInvoicePeriods({
    required DateTime startDate,
    required DateTime endDate,
    required double dailyFee,
    required Map<String, dynamic> schedule,
    int depositDays = 60,
    int invoiceCycleDays = 30,
  }) {
    final periods = <Map<String, dynamic>>[];
    if (endDate.isBefore(startDate)) return periods;

    var cycleStart = DateTime(startDate.year, startDate.month, startDate.day + depositDays);

    while (!cycleStart.isAfter(endDate)) {
      final potentialEnd = DateTime(cycleStart.year, cycleStart.month, cycleStart.day + invoiceCycleDays - 1);
      final cycleEnd = potentialEnd.isAfter(endDate) ? endDate : potentialEnd;

      final activeDays = countActiveDays(cycleStart, cycleEnd, schedule);
      periods.add({
        'startDay': cycleStart.difference(startDate).inDays + 1,
        'endDay': cycleEnd.difference(startDate).inDays + 1,
        'days': activeDays,
        'amount': dailyFee * activeDays,
      });

      cycleStart = DateTime(cycleEnd.year, cycleEnd.month, cycleEnd.day + 1);
    }
    return periods;
  }
}