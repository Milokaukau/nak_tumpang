import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nak_tumpang/core/utils/matching_utils.dart';
import 'package:nak_tumpang/core/services/ors_service.dart';
import 'package:nak_tumpang/features/home/data/services/home_supabase_service.dart';
import 'package:nak_tumpang/core/services/gtfs_service.dart';
import 'package:nak_tumpang/core/utils/transit_utils.dart';
import 'package:uuid/uuid.dart';
import 'package:nak_tumpang/features/home/data/services/home_local_service.dart';
import 'package:nak_tumpang/core/utils/format_utils.dart';
import 'package:nak_tumpang/core/services/network_service.dart';
import 'package:nak_tumpang/features/subscriptions/data/services/subscription_supabase_service.dart';

enum HomePanelMode { none, cantFetch, noNeedFetch }

class HomeViewModel extends ChangeNotifier {
  String selectedFilter = 'Direct';
  String currentUserRole = 'passenger';
  String? selectedSubscriptionId;
  String? get currentUserId => _auth.currentUser?.id;

  Map<String, dynamic>? currentUser;
  Map<String, dynamic>? currentSelectedTrip;

  List<Map<String, dynamic>> availableTrips = [];
  List<Map<String, dynamic>> activeSubscriptions = [];

  bool isScreenLoading = true;
  bool isDirectLoading = false;
  bool isMixedLoading = false;
  bool isRouteLoading = false;
  bool _isCompletingTrip = false;
  bool get isCompletingTrip => _isCompletingTrip;

  bool isDirectLoadingMore = false;
  bool isMixedLoadingMore = false;

  bool showMatchingUI = false;
  bool _isFirstLoad = true;
  int _matchingUiEpoch = 0;

  bool _hasFoundDirect = false;
  bool _hasFoundMixed = false;
  bool hasExceptedTripsToday = false;

  int _fetchId = 0;
  int _routeFetchId = 0;
  int _userFetchId = 0;
  String? _lastLoadedUserId;

  // --- CAPPED AT 4 ---
  int currentDirectLimit = 4;
  int currentMixedLimit = 4;
  bool hasMoreDirect = false;
  bool hasMoreMixed = false;

  final ORSService _orsService = ORSService();
  final HomeSupabaseService _homeService = HomeSupabaseService();
  final GoTrueClient _auth = Supabase.instance.client.auth;
  final SubscriptionSupabaseService _subscriptionService = SubscriptionSupabaseService();

  List<Map<String, dynamic>> matchedDrivers = [];
  List<Map<String, dynamic>> mixedMatchedRoutes = [];

  List<({List<LatLng> points, Color color, bool isTransit})> mapRoutes = [];
  List<({LatLng point, Color color, bool isSmallNode})> mapMarkers = [];

  final Map<String, List<LatLng>> _routeCache = {};

  HomePanelMode panelMode = HomePanelMode.none;

  DateTime? exceptionStartDate;
  DateTime? exceptionEndDate;
  String? exceptionReason;
  final TextEditingController exceptionCustomReasonController = TextEditingController();
  bool isSubmittingException = false;

  static const List<String> driverReasons = [
    'Sick / Not feeling well',
    'Vehicle issue',
    'Personal emergency',
    'Others',
  ];

  static const List<String> passengerReasons = [
    'Working from home',
    'On leave',
    'Personal emergency',
    'Others',
  ];

  Map<String, dynamic>? selectedSubscription;

  HomeViewModel() {
    NetworkService.isOfflineNotifier.addListener(_onNetworkChange);
  }

  @override
  void dispose() {
    exceptionCustomReasonController.dispose();
    NetworkService.isOfflineNotifier.removeListener(_onNetworkChange);
    super.dispose();
  }

  void openCantFetchPanel([Map<String, dynamic>? sub]) {
    selectedSubscription = sub;
    panelMode = HomePanelMode.cantFetch;
    _resetExceptionForm();
    notifyListeners();
  }

  void openNoNeedFetchPanel([Map<String, dynamic>? sub]) {
    selectedSubscription = sub;
    panelMode = HomePanelMode.noNeedFetch;
    _resetExceptionForm();
    notifyListeners();
  }

  void closeExceptionPanel() {
    selectedSubscription = null;
    panelMode = HomePanelMode.none;
    _resetExceptionForm();
    notifyListeners();
  }

  void _resetExceptionForm() {
    exceptionStartDate = null;
    exceptionEndDate = null;
    exceptionReason = null;
    exceptionCustomReasonController.clear();
  }

  void setExceptionStartDate(DateTime date) {
    exceptionStartDate = date;
    if (exceptionEndDate != null && exceptionEndDate!.isBefore(date)) {
      exceptionEndDate = date;
    }
    notifyListeners();
  }

  void setExceptionEndDate(DateTime date) {
    exceptionEndDate = date;
    notifyListeners();
  }

  void setExceptionReason(String? reason) {
    exceptionReason = reason;
    if (reason != 'Others') {
      exceptionCustomReasonController.clear();
    }
    notifyListeners();
  }

  Future<bool> submitException({
    required String tumpangSubscriptionId,
    required String initiatedBy,
    required String initiatedByRole,
  }) async {
    if (exceptionStartDate == null || exceptionEndDate == null || exceptionReason == null) {
      return false;
    }

    isSubmittingException = true;
    notifyListeners();

    final reasonText = exceptionReason == 'Others'
        ? exceptionCustomReasonController.text.trim()
        : exceptionReason!;

    try {
      final success = await _homeService.createException(
        tumpangSubscriptionId: tumpangSubscriptionId,
        initiatedBy: initiatedBy,
        initiatedByRole: initiatedByRole,
        startDate: exceptionStartDate!,
        endDate: exceptionEndDate!,
        reason: reasonText,
      );

      if (success) {
        closeExceptionPanel();
        await refreshHome();
      }

      return success;
    } catch (e) {
      debugPrint('⚠️ Error submitting exception: $e');
      return false;
    } finally {
      isSubmittingException = false;
      notifyListeners();
    }
  }

  void _onNetworkChange() {
    if (!NetworkService.isOfflineNotifier.value) {
      _hasFoundDirect = false;
      _hasFoundMixed = false;
      fetchCurrentUser();
    } else {
      updateMapRoute();
    }
    notifyListeners();
  }

  void loadMoreDirect() {
    if (isDirectLoadingMore) return;
    currentDirectLimit += 4; // CAPPED AT 4
    isDirectLoadingMore = true;
    notifyListeners();
    _findDirectDrivers();
  }

  void loadMoreMixed() {
    if (isMixedLoadingMore) return;
    currentMixedLimit += 4; // CAPPED AT 4
    isMixedLoadingMore = true;
    notifyListeners();
    _findMixedRoutes();
  }

  Future<bool> completeTrip({
    required String subscriptionId,
    required String driverId,
    required String passengerId,
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
  }) async {
    if (_isCompletingTrip) return false;

    _isCompletingTrip = true;
    notifyListeners();

    try {
      final success = await _homeService.completeTrip(
        subscriptionId: subscriptionId,
        driverId: driverId,
        passengerId: passengerId,
        pickupLat: pickupLat,
        pickupLng: pickupLng,
        dropoffLat: dropoffLat,
        dropoffLng: dropoffLng,
      );
      return success;
    } finally {
      _isCompletingTrip = false;
      notifyListeners();
    }
  }

  Future<String?> requestTumpang({
    required String driverTripId,
    required String passengerTripId,
    dynamic overridePickupLat,
    dynamic overridePickupLng,
    String? overridePickupName,
    dynamic overrideDropoffLat,
    dynamic overrideDropoffLng,
    String? overrideDropoffName,
    String? overridePickupTime,
  }) async {
    final authUser = _auth.currentUser;
    if (authUser == null || currentSelectedTrip == null) return null;

    final pickupLat = overridePickupLat ?? currentSelectedTrip!['pickup_lat'];
    final pickupLng = overridePickupLng ?? currentSelectedTrip!['pickup_lng'];
    final pickupName = overridePickupName ?? currentSelectedTrip!['pickup_name'];

    final dropoffLat = overrideDropoffLat ?? currentSelectedTrip!['dropoff_lat'];
    final dropoffLng = overrideDropoffLng ?? currentSelectedTrip!['dropoff_lng'];
    final dropoffName = overrideDropoffName ?? currentSelectedTrip!['dropoff_name'];

    final pickupTime = overridePickupTime ?? currentSelectedTrip!['desired_pickup_time'];
    final requestId = const Uuid().v4();

    final payload = {
      'id': requestId,
      'passenger_trip_id': passengerTripId,
      'driver_trip_id': driverTripId,
      'status': 'negotiating',
      'pickup_lat': pickupLat,
      'pickup_lng': pickupLng,
      'pickup_name': pickupName,
      'pickup_requested_by': authUser.id,
      'pickup_is_accepted': false,
      'dropoff_lat': dropoffLat,
      'dropoff_lng': dropoffLng,
      'dropoff_name': dropoffName,
      'dropoff_requested_by': authUser.id,
      'dropoff_is_accepted': false,
      'pickup_time': pickupTime,
      'pickup_time_requested_by': authUser.id,
      'pickup_time_is_accepted': false,
      'fee': 0.0,
      'fee_requested_by': authUser.id,
      'fee_is_accepted': false,
      'sub_start_date': null,
      'sub_start_requested_by': authUser.id,
      'sub_start_is_accepted': false,
      'sub_end_date': null,
      'sub_end_requested_by': authUser.id,
      'sub_end_is_accepted': false,
    };

    final success = await _homeService.createTumpangRequest(payload);
    return success ? requestId : null;
  }

  void markDriverRequestedGlobally(List<String> requestedDriverTripIds) {
    if (requestedDriverTripIds.isEmpty) return;

    for (var driver in matchedDrivers) {
      if (requestedDriverTripIds.contains(driver['trip_id'])) {
        driver['is_requested'] = true;
      }
    }

    for (var route in mixedMatchedRoutes) {
      if (requestedDriverTripIds.contains(route['driver_a_trip_id'])) {
        route['is_driver_a_requested'] = true;
      }
      if (requestedDriverTripIds.contains(route['driver_b_trip_id'])) {
        route['is_driver_b_requested'] = true;
      }

      bool hasDriverA = route['first_mile_type'] == 'Driver' && route['driver_a_trip_id'] != null;
      bool hasDriverB = route['last_mile_type'] == 'Driver' && route['driver_b_trip_id'] != null;
      bool isReqA = route['is_driver_a_requested'] ?? false;
      bool isReqB = route['is_driver_b_requested'] ?? false;

      if (hasDriverA && hasDriverB) {
        route['is_requested'] = isReqA && isReqB;
      } else if (hasDriverA) {
        route['is_requested'] = isReqA;
      } else if (hasDriverB) {
        route['is_requested'] = isReqB;
      }
    }
    notifyListeners();
  }

  void addOrUpdateLocalTrip(Map<String, dynamic> trip) {
    final index = availableTrips.indexWhere((t) => t['id'] == trip['id']);
    if (index != -1) {
      availableTrips[index] = trip;
    } else {
      availableTrips.add(trip);
    }

    if (currentSelectedTrip?['id'] == trip['id']) {
      currentSelectedTrip = trip;
      currentDirectLimit = 4;
      currentMixedLimit = 4;
      isDirectLoadingMore = false;
      isMixedLoadingMore = false;
      hasMoreDirect = false;
      hasMoreMixed = false;
      _hasFoundDirect = false;
      _hasFoundMixed = false;
      matchedDrivers.clear();
      mixedMatchedRoutes.clear();
      updateMapRoute();
      if (showMatchingUI) _matchCurrentRouteType();
    } else if (currentSelectedTrip == null && availableTrips.length == 1) {
      changeTrip(trip['id']);
    }
    notifyListeners();
  }

  void removeLocalTrip(String tripId) {
    availableTrips.removeWhere((t) => t['id'] == tripId);
    if (currentSelectedTrip?['id'] == tripId) {
      currentSelectedTrip = availableTrips.isNotEmpty ? availableTrips.first : null;
      currentDirectLimit = 4;
      currentMixedLimit = 4;
      isDirectLoadingMore = false;
      isMixedLoadingMore = false;
      hasMoreDirect = false;
      hasMoreMixed = false;
      _hasFoundDirect = false;
      _hasFoundMixed = false;
      matchedDrivers.clear();
      mixedMatchedRoutes.clear();
      updateMapRoute();
      if (showMatchingUI && currentSelectedTrip != null) _matchCurrentRouteType();
    }
    notifyListeners();
  }

  Future<List<LatLng>> _getCachedRoute(LatLng start, LatLng end, {String profile = 'driving-car'}) async {
    final cacheKey = '${profile}_${start.latitude},${start.longitude}-${end.latitude},${end.longitude}';
    if (_routeCache.containsKey(cacheKey)) return _routeCache[cacheKey]!;

    if (NetworkService.isOfflineNotifier.value) return [];

    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        final route = await _orsService.getRoute(start, end, profile: profile);

        if (route.isNotEmpty) {
          _routeCache[cacheKey] = route;
          return route;
        }
        debugPrint('⚠️ Route fetch empty for $profile (Attempt ${attempt + 1}/3)');
      } catch (e) {
        debugPrint('⚠️ Route fetch error for $profile: $e (Attempt ${attempt + 1}/3)');
      }

      if (attempt < 2) await Future.delayed(const Duration(milliseconds: 600));
    }

    debugPrint('❌ Max retries reached. Returning empty route to prevent inaccurate matches.');
    return [];
  }

  void toggleMatchingUI(bool show) {
    showMatchingUI = show;
    _matchingUiEpoch++;
    notifyListeners();
    updateMapRoute();
    if (show) _matchCurrentRouteType();
  }

  void setFilter(String option) {
    if (selectedFilter == option) return;
    selectedFilter = option;
    notifyListeners();
    if (showMatchingUI) _matchCurrentRouteType();
  }

  Future<void> fetchCurrentUser() async {
    final requestId = ++_userFetchId;
    final authUser = _auth.currentUser;

    if (authUser != null && _lastLoadedUserId != null && _lastLoadedUserId != authUser.id) {
      _resetForUserSwitch();
    }
    _lastLoadedUserId = authUser?.id;

    final matchingUiEpochAtStart = _matchingUiEpoch;

    if (_isFirstLoad) {
      isScreenLoading = true;
      notifyListeners();
    }

    if (authUser == null) {
      if (requestId == _userFetchId) {
        isScreenLoading = false;
        notifyListeners();
      }
      return;
    }

    final localRole = await HomeLocalService().getUserRole(authUser.id);
    if (localRole != null) currentUserRole = localRole;

    if (_isFirstLoad) {
      final isPassengerRole = currentUserRole == 'passenger';
      final cachedSubs = await HomeLocalService().getCachedSubscriptions(authUser.id, isForPassenger: isPassengerRole);
      final cachedTrips = await HomeLocalService().getCachedUserTrips(authUser.id, isForPassenger: isPassengerRole);

      if (cachedSubs.isNotEmpty) {
        activeSubscriptions = _mapSubscriptions(cachedSubs, isForPassenger: isPassengerRole);
        selectedSubscriptionId = activeSubscriptions.isEmpty ? null : activeSubscriptions.first['id'];
        showMatchingUI = activeSubscriptions.isEmpty;
      } else {
        showMatchingUI = true;
      }

      final subbedIds = cachedSubs.map((s) => s[isPassengerRole ? 'passenger_trip_id' : 'driver_trip_id']).toSet();
      availableTrips = cachedTrips.where((t) => !subbedIds.contains(t['id'])).toList();

      _validateCurrentSelectedTrip();

      isScreenLoading = false;
      if (requestId == _userFetchId) notifyListeners();
    }

    try {
      final profile = await _homeService.fetchUserProfile(authUser.id);
      if (requestId != _userFetchId) return;

      if (profile != null) {
        currentUser = profile;
        final role = profile['role'] as String?;
        if (role == 'driver' || role == 'passenger') {
          currentUserRole = role!;
        }
      }
    } catch (e) {
      debugPrint('⚠️ Profile fetch failed: $e');
    }

    if (currentUserRole == 'driver') {
      await _loadDriverData(authUser.id, requestId, matchingUiEpochAtStart);
    } else {
      await _loadPassengerData(authUser.id, requestId, matchingUiEpochAtStart);
    }

    if (requestId == _userFetchId) {
      isScreenLoading = false;
      _isFirstLoad = false;
      notifyListeners();
    }
  }

  void _resetForUserSwitch() {
    _isFirstLoad = true;
    currentUser = null;
    currentUserRole = 'passenger';
    currentSelectedTrip = null;
    availableTrips = [];
    activeSubscriptions = [];
    selectedSubscriptionId = null;
    showMatchingUI = false;
    selectedFilter = 'Direct';

    matchedDrivers.clear();
    mixedMatchedRoutes.clear();
    _hasFoundDirect = false;
    _hasFoundMixed = false;
    hasExceptedTripsToday = false;

    currentDirectLimit = 4;
    currentMixedLimit = 4;
    isDirectLoading = false;
    isMixedLoading = false;
    isDirectLoadingMore = false;
    isMixedLoadingMore = false;
    hasMoreDirect = false;
    hasMoreMixed = false;

    mapRoutes = [];
    mapMarkers = [];
    _routeCache.clear();

    _fetchId++;
    _routeFetchId++;
    notifyListeners();
  }

  Future<Set<String>> _getExceptedSubIds(List<Map<String, dynamic>> subs) async {
    if (subs.isEmpty || NetworkService.isOfflineNotifier.value) return {};
    try {
      final subIds = subs.map((s) => s['id']).toList();
      final today = DateTime.now();
      final todayStr = "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";

      final exceptions = await _auth.currentSession != null
          ? await Supabase.instance.client
          .from('tumpang_exception')
          .select('tumpang_subscription_id')
          .inFilter('tumpang_subscription_id', subIds)
          .eq('status', 'active')
          .lte('start_date', todayStr)
          .gte('end_date', todayStr)
          : [];

      return exceptions.map((e) => e['tumpang_subscription_id'].toString()).toSet();
    } catch (e) {
      debugPrint('Error fetching exceptions: $e');
      return {};
    }
  }

  Future<void> _loadDriverData(String userId, int requestId, int matchingUiEpochAtStart) async {
    List<Map<String, dynamic>> rawSubs = [];
    List<Map<String, dynamic>> allDriverTrips = [];
    List<Map<String, dynamic>> myTrips = [];

    if (NetworkService.isOfflineNotifier.value) {
      myTrips = await HomeLocalService().getCachedUserTrips(userId, isForPassenger: false);
      rawSubs = await HomeLocalService().getCachedSubscriptions(userId, isForPassenger: false);
      allDriverTrips = myTrips;
    } else {
      try {
        rawSubs = await _homeService.fetchDriverActiveSubscriptions(userId);
        allDriverTrips = await _homeService.fetchDriverTrips();
        myTrips = allDriverTrips.where((trip) => trip['user_id'] == userId).toList();

        await HomeLocalService().cacheHomeData(
          trips: myTrips,
          rawSubs: rawSubs,
          isForPassenger: false,
          currentUserId: userId,
        );
      } catch (e) {
        myTrips = await HomeLocalService().getCachedUserTrips(userId, isForPassenger: false);
        rawSubs = await HomeLocalService().getCachedSubscriptions(userId, isForPassenger: false);
        allDriverTrips = myTrips;
      }
    }

    if (requestId != _userFetchId) return;

    final exceptedSubIds = await _getExceptedSubIds(rawSubs);
    hasExceptedTripsToday = exceptedSubIds.isNotEmpty;
    final activeTodaySubs = rawSubs.where((s) => !exceptedSubIds.contains(s['id'])).toList();

    final previousSubCount = activeSubscriptions.length;
    activeSubscriptions = _mapSubscriptions(activeTodaySubs, isForPassenger: false);

    final allSubbedTripIds = rawSubs.map((s) => s['driver_trip_id']).toSet();
    availableTrips = myTrips.where((t) => !allSubbedTripIds.contains(t['id'])).toList();

    _validateCurrentSelectedTrip();

    if (activeSubscriptions.isNotEmpty) {
      selectedSubscriptionId ??= activeSubscriptions.first['id'];
      if (activeSubscriptions.length > previousSubCount || (_isFirstLoad && _matchingUiEpoch == matchingUiEpochAtStart)) {
        showMatchingUI = false;
        selectedSubscriptionId = activeSubscriptions.first['id'];
      }
    } else {
      showMatchingUI = true;
    }

    updateMapRoute();
  }

  Future<void> _loadPassengerData(String userId, int requestId, int matchingUiEpochAtStart) async {
    List<Map<String, dynamic>> rawSubs = [];
    List<Map<String, dynamic>> trips = [];

    if (NetworkService.isOfflineNotifier.value) {
      trips = await HomeLocalService().getCachedUserTrips(userId, isForPassenger: true);
      rawSubs = await HomeLocalService().getCachedSubscriptions(userId, isForPassenger: true);
    } else {
      try {
        trips = await _homeService.fetchPassengerTrips(userId);
        rawSubs = await _homeService.fetchAllPassengerSubscriptions(userId);

        await HomeLocalService().cacheHomeData(
          trips: trips,
          rawSubs: rawSubs,
          isForPassenger: true,
          currentUserId: userId,
        );
      } catch (e) {
        trips = await HomeLocalService().getCachedUserTrips(userId, isForPassenger: true);
        rawSubs = await HomeLocalService().getCachedSubscriptions(userId, isForPassenger: true);
      }
    }

    if (requestId != _userFetchId) return;

    for (var sub in rawSubs) {
      final pTripId = sub['passenger_trip_id'];
      final matchingTrip = trips.firstWhere((t) => t['id'] == pTripId, orElse: () => <String, dynamic>{});
      if (matchingTrip.isNotEmpty) {
        sub['passenger_trips'] = matchingTrip;
      }
    }

    final exceptedSubIds = await _getExceptedSubIds(rawSubs);
    hasExceptedTripsToday = exceptedSubIds.isNotEmpty;

    final exceptedPassengerTripIds = rawSubs
        .where((s) => exceptedSubIds.contains(s['id']))
        .map((s) => s['passenger_trip_id'])
        .toSet();

    final activeTodaySubs = rawSubs.where((s) => !exceptedPassengerTripIds.contains(s['passenger_trip_id'])).toList();

    final previousSubCount = activeSubscriptions.length;
    activeSubscriptions = _mapSubscriptions(activeTodaySubs, isForPassenger: true);

    final allSubbedTripIds = rawSubs.map((s) => s['passenger_trip_id']).toSet();
    availableTrips = trips.where((t) => !allSubbedTripIds.contains(t['id'])).toList();

    _validateCurrentSelectedTrip();

    if (activeSubscriptions.isNotEmpty) {
      selectedSubscriptionId ??= activeSubscriptions.first['id'];
      if (activeSubscriptions.length > previousSubCount || (_isFirstLoad && _matchingUiEpoch == matchingUiEpochAtStart)) {
        showMatchingUI = false;
        selectedSubscriptionId = activeSubscriptions.first['id'];
      }
    } else {
      showMatchingUI = true;
    }

    updateMapRoute();

    if (showMatchingUI && currentSelectedTrip != null && !NetworkService.isOfflineNotifier.value) {
      await _matchCurrentRouteType();
    }
  }

  Future<void> changeTrip(String tripId) async {
    try {
      final selected = availableTrips.firstWhere((t) => t['id'] == tripId);
      currentSelectedTrip = selected;

      currentDirectLimit = 4;
      currentMixedLimit = 4;
      isDirectLoadingMore = false;
      isMixedLoadingMore = false;
      hasMoreDirect = false;
      hasMoreMixed = false;
      _hasFoundDirect = false;
      _hasFoundMixed = false;
      matchedDrivers.clear();
      mixedMatchedRoutes.clear();

      updateMapRoute();

      if (showMatchingUI) {
        await _matchCurrentRouteType();
      }
    } catch (e) {
      print('⚠️ Error changing trip: $e');
    }
  }

  Future<void> _matchCurrentRouteType() async {
    if (selectedFilter == 'Direct' && !_hasFoundDirect) {
      await _findDirectDrivers();
    } else if (selectedFilter == 'Mixed' && !_hasFoundMixed) {
      await _findMixedRoutes();
    }
  }

  Future<void> _findDirectDrivers() async {
    if (currentSelectedTrip == null) return;
    final currentFetchId = ++_fetchId;

    if (!isDirectLoadingMore) {
      isDirectLoading = true;
      matchedDrivers.clear();
    }
    notifyListeners();

    try {
      final passDays = FormatUtils.extractActiveDays(currentSelectedTrip!);
      final passPick = FormatUtils.latLngFromMap(currentSelectedTrip!, 'pickup_lat', 'pickup_lng');
      final passDrop = FormatUtils.latLngFromMap(currentSelectedTrip!, 'dropoff_lat', 'dropoff_lng');
      final passTime = FormatUtils.sqlTimeToMinutes(currentSelectedTrip!['desired_pickup_time']);

      final driverTrips = await _homeService.fetchDriverTrips();
      if (_fetchId != currentFetchId) return;

      final existingReqIds = await _homeService.fetchRequestedDriverTripIds(currentSelectedTrip!['id']);
      if (_fetchId != currentFetchId) return;

      List<Map<String, dynamic>> tempMatchedDrivers = [];
      int matchCount = 0;
      bool moreAvailable = false;
      int orsFailuresThisRun = 0; // Track total full failures

      for (int i = 0; i < driverTrips.length; i++) {
        if (_fetchId != currentFetchId) return;
        var driverTrip = driverTrips[i];

        final driverName = driverTrip['users']?['name'] ?? 'Unknown Driver';
        final driverDays = FormatUtils.extractActiveDays(driverTrip);

        if (!MatchingUtils.hasOverlappingDays(passDays, driverDays)) continue;

        final drivTime = FormatUtils.sqlTimeToMinutes(driverTrip['depart_time']);
        if ((drivTime - passTime).abs() > 30) continue;

        final drivStart = FormatUtils.latLngFromMap(driverTrip, 'depart_lat', 'depart_lng');
        final drivEnd = FormatUtils.latLngFromMap(driverTrip, 'arrival_lat', 'arrival_lng');

        if (drivStart.latitude == 0 || drivEnd.latitude == 0) continue;

        final pickDist = MatchingUtils.calculateDistance(
          passPick.latitude, passPick.longitude, drivStart.latitude, drivStart.longitude,
        );
        final dropDist = MatchingUtils.calculateDistance(
          passDrop.latitude, passDrop.longitude, drivEnd.latitude, drivEnd.longitude,
        );

        if (pickDist > 15000 || dropDist > 15000) continue;

        try {
          final driverRoute = await _getCachedRoute(drivStart, drivEnd);
          if (_fetchId != currentFetchId) return;

          if (driverRoute.isEmpty) {
            orsFailuresThisRun++;
            if (orsFailuresThisRun >= 4) {
              debugPrint('🛑 Stopping search: ORS failed completely 4 times.');
              moreAvailable = true;
              break;
            }
            continue;
          }

          if (MatchingUtils.isRouteMatch(passPick, passDrop, driverRoute, 800)) {
            tempMatchedDrivers.add({
              'id': driverTrip['user_id'],
              'trip_id': driverTrip['id'],
              'name': driverName,
              'phone': driverTrip['users']?['phone'] ?? 'N/A',
              'profile_image_url': driverTrip['users']?['avatar_url'],
              'pickup_distance_km': pickDist / 1000,
              'is_requested': existingReqIds.contains(driverTrip['id']),
              'driver_profile': {
                'depart_time': FormatUtils.formatSqlTimeToUI(driverTrip['depart_time']),
              },
            });

            matchCount++;
            if (matchCount >= currentDirectLimit) {
              moreAvailable = i < driverTrips.length - 1;
              break;
            }
          }
        } catch (e) {
          if (e.toString().contains('Quota') || e.toString().contains('SocketException')) break;
          continue;
        }
      }

      if (_fetchId != currentFetchId) return;

      matchedDrivers = tempMatchedDrivers;
      hasMoreDirect = moreAvailable;
      _hasFoundDirect = true;

    } catch (e) {
      debugPrint('⚠️ Error fetching direct drivers: $e');
    } finally {
      if (_fetchId == currentFetchId) {
        isDirectLoading = false;
        isDirectLoadingMore = false;
        notifyListeners();
      }
    }
  }

  Future<void> _findMixedRoutes() async {
    if (currentSelectedTrip == null) return;
    final currentFetchId = ++_fetchId;

    if (!isMixedLoadingMore) {
      isMixedLoading = true;
      mixedMatchedRoutes.clear();
    }
    notifyListeners();

    try {
      final passDays = FormatUtils.extractActiveDays(currentSelectedTrip!);
      final passPick = FormatUtils.latLngFromMap(currentSelectedTrip!, 'pickup_lat', 'pickup_lng');
      final passDrop = FormatUtils.latLngFromMap(currentSelectedTrip!, 'dropoff_lat', 'dropoff_lng');
      final passTime = FormatUtils.sqlTimeToMinutes(currentSelectedTrip!['desired_pickup_time']);

      final driverTrips = await _homeService.fetchDriverTrips();
      if (_fetchId != currentFetchId) return;

      await GtfsService().initStations();
      if (_fetchId != currentFetchId) return;

      final existingReqIds = await _homeService.fetchRequestedDriverTripIds(currentSelectedTrip!['id']);
      if (_fetchId != currentFetchId) return;

      List<Map<String, dynamic>> tempMixedRoutes = [];
      bool moreAvailable = false;

      final pickStation = TransitUtils.findNearestStation(passPick);
      final dropStation = TransitUtils.findNearestStation(passDrop);

      if (pickStation == null || dropStation == null) {
        _hasFoundMixed = true;
        return;
      }

      final isInterchange = pickStation.lineId != dropStation.lineId;
      int trainDuration;

      if (isInterchange) {
        final transitDist = MatchingUtils.calculateDistance(
          pickStation.location.latitude, pickStation.location.longitude,
          dropStation.location.latitude, dropStation.location.longitude,
        );
        trainDuration = (transitDist / 660).ceil() + 10;
      } else {
        trainDuration = TransitUtils.calculateTrainDuration(pickStation, dropStation);
      }

      final pickWalkMetrics = await _orsService.getWalkingMetrics(passPick, pickStation.location);
      if (_fetchId != currentFetchId) return;

      final dropWalkMetrics = await _orsService.getWalkingMetrics(dropStation.location, passDrop);
      if (_fetchId != currentFetchId) return;

      final walkDistToStation = pickWalkMetrics['distance'];
      final walkDurationToStation = (pickWalkMetrics['duration'] / 60).ceil();
      final walkDistToDest = dropWalkMetrics['distance'];
      final walkDurationToDest = (dropWalkMetrics['duration'] / 60).ceil();

      final firstMileOptions = <Map<String, dynamic>>[];
      final lastMileOptions = <Map<String, dynamic>>[];

      if (walkDistToStation <= 1500) {
        firstMileOptions.add({
          'type': 'Walk',
          'arrival_at_board_station': passTime + walkDurationToStation,
        });
      }
      if (walkDistToDest <= 1500) {
        lastMileOptions.add({'type': 'Walk'});
      }

      int validDriversFound = 0;
      int orsFailuresThisRun = 0; // Track total full failures

      for (int i = 0; i < driverTrips.length; i++) {
        if (_fetchId != currentFetchId) return;
        var driverTrip = driverTrips[i];

        final driverDays = FormatUtils.extractActiveDays(driverTrip);
        if (!MatchingUtils.hasOverlappingDays(passDays, driverDays)) continue;

        final drivStart = LatLng(FormatUtils.parseDouble(driverTrip['depart_lat']), FormatUtils.parseDouble(driverTrip['depart_lng']));
        final drivEnd = LatLng(FormatUtils.parseDouble(driverTrip['arrival_lat']), FormatUtils.parseDouble(driverTrip['arrival_lng']));
        final drivTime = FormatUtils.sqlTimeToMinutes(driverTrip['depart_time']);
        final driverName = driverTrip['users']?['name'] ?? 'Unknown Driver';

        if (drivStart.latitude == 0 || drivEnd.latitude == 0) continue;
        bool foundAny = false;

        try {
          final pickDist = MatchingUtils.calculateDistance(passPick.latitude, passPick.longitude, drivStart.latitude, drivStart.longitude);
          final dropDistToStation = MatchingUtils.calculateDistance(pickStation.location.latitude, pickStation.location.longitude, drivEnd.latitude, drivEnd.longitude);
          final pickDistFromStation = MatchingUtils.calculateDistance(dropStation.location.latitude, dropStation.location.longitude, drivStart.latitude, drivStart.longitude);
          final dropDistToDest = MatchingUtils.calculateDistance(passDrop.latitude, passDrop.longitude, drivEnd.latitude, drivEnd.longitude);

          bool potentialFirstMile = ((drivTime - passTime).abs() <= 30) && (pickDist <= 15000 && dropDistToStation <= 15000);
          bool potentialLastMile = (drivTime > passTime) && (pickDistFromStation <= 15000 && dropDistToDest <= 15000);

          if (potentialFirstMile || potentialLastMile) {
            final driverRoute = await _getCachedRoute(drivStart, drivEnd);
            if (_fetchId != currentFetchId) return;

            if (driverRoute.isEmpty) {
              orsFailuresThisRun++;
              if (orsFailuresThisRun >= 4) {
                debugPrint('🛑 Stopping search: ORS failed completely 4 times.');
                moreAvailable = true;
                break;
              }
              continue;
            }

            if (potentialFirstMile && MatchingUtils.isRouteMatch(passPick, pickStation.location, driverRoute, 800)) {
              final routeDistToStation = MatchingUtils.calculateDistance(passPick.latitude, passPick.longitude, pickStation.location.latitude, pickStation.location.longitude);
              final driveMinsToStation = (routeDistToStation / 400).ceil();

              firstMileOptions.add({
                'type': 'Driver',
                'driver_id': driverTrip['user_id'],
                'trip_id': driverTrip['id'],
                'driver_name': driverName,
                'depart_time': FormatUtils.formatSqlTimeToUI(driverTrip['depart_time']),
                'depart_time_sql': driverTrip['depart_time'],
                'distance_km': pickDist / 1000,
                'arrival_at_board_station': drivTime + driveMinsToStation,
              });
              foundAny = true;
            }

            if (potentialLastMile && MatchingUtils.isRouteMatch(dropStation.location, passDrop, driverRoute, 800)) {
              lastMileOptions.add({
                'type': 'Driver',
                'driver_id': driverTrip['user_id'],
                'trip_id': driverTrip['id'],
                'driver_name': driverName,
                'depart_time': FormatUtils.formatSqlTimeToUI(driverTrip['depart_time']),
                'depart_time_sql': driverTrip['depart_time'],
                'depart_time_mins': drivTime,
                'distance_km': pickDistFromStation / 1000,
              });
              foundAny = true;
            }
          }

          if (foundAny) {
            validDriversFound++;
            if (validDriversFound >= currentMixedLimit * 2) {
              moreAvailable = i < driverTrips.length - 1;
              break;
            }
          }
        } catch (e) {
          if (e.toString().contains('Quota') || e.toString().contains('SocketException')) break;
          continue;
        }
      }

      for (var fm in firstMileOptions) {
        final arrivalAtDropStation = fm['arrival_at_board_station'] + trainDuration;
        for (var lm in lastMileOptions) {
          if (fm['type'] == 'Walk' && lm['type'] == 'Walk') continue;
          if (fm['type'] == 'Driver' && lm['type'] == 'Driver' && fm['driver_name'] == lm['driver_name']) continue;
          if (lm['type'] == 'Driver') {
            final lmDepart = lm['depart_time_mins'];
            if ((lmDepart - arrivalAtDropStation).abs() > 45) continue;
          }

          final driverAId = fm['trip_id'];
          final driverBId = lm['trip_id'];
          final bool isReqA = driverAId != null && existingReqIds.contains(driverAId);
          final bool isReqB = driverBId != null && existingReqIds.contains(driverBId);

          bool hasDriverA = fm['type'] == 'Driver' && driverAId != null;
          bool hasDriverB = lm['type'] == 'Driver' && driverBId != null;

          bool isRouteRequested = false;
          if (hasDriverA && hasDriverB) {
            isRouteRequested = isReqA && isReqB;
          } else if (hasDriverA) {
            isRouteRequested = isReqA;
          } else if (hasDriverB) {
            isRouteRequested = isReqB;
          }

          tempMixedRoutes.add({
            'first_mile_type': fm['type'],
            'driver_a_name': fm['driver_name'],
            'driver_a_id': fm['driver_id'],
            'driver_a_trip_id': fm['trip_id'],
            'driver_a_depart': fm['depart_time'],
            'driver_a_depart_sql': fm['depart_time_sql'],
            'pickup_distance_km': fm['distance_km'],
            'walk_to_station_meters': walkDistToStation,
            'walk_to_station_mins': walkDurationToStation,
            'board_station': pickStation.name,
            'board_station_lat': pickStation.location.latitude,
            'board_station_lng': pickStation.location.longitude,
            'alight_station': dropStation.name,
            'alight_station_lat': dropStation.location.latitude,
            'alight_station_lng': dropStation.location.longitude,
            'is_interchange': isInterchange,
            'board_line_name': pickStation.lineName,
            'board_line_short_name': pickStation.lineShortName,
            'board_line_color': pickStation.lineColor,
            'alight_line_name': dropStation.lineName,
            'alight_line_short_name': dropStation.lineShortName,
            'alight_line_color': dropStation.lineColor,
            'train_duration_mins': trainDuration,
            'last_mile_type': lm['type'],
            'driver_b_name': lm['driver_name'],
            'driver_b_id': lm['driver_id'],
            'driver_b_trip_id': lm['trip_id'],
            'driver_b_depart': lm['depart_time'],
            'driver_b_depart_sql': lm['depart_time_sql'],
            'dropoff_distance_km': lm['distance_km'],
            'walk_to_dest_meters': walkDistToDest,
            'walk_to_dest_mins': walkDurationToDest,
            'pickup_name': currentSelectedTrip?['pickup_name'] ?? 'Pickup',
            'destination_name': currentSelectedTrip?['dropoff_name'] ?? 'Destination',
            'is_driver_a_requested': isReqA,
            'is_driver_b_requested': isReqB,
            'is_requested': isRouteRequested,
          });
        }
      }

      if (_fetchId != currentFetchId) return;

      mixedMatchedRoutes = tempMixedRoutes.take(currentMixedLimit).toList();
      hasMoreMixed = moreAvailable || tempMixedRoutes.length > currentMixedLimit;
      _hasFoundMixed = true;

    } catch (e) {
      debugPrint('⚠️ Error fetching mixed routes: $e');
    } finally {
      if (_fetchId == currentFetchId) {
        isMixedLoading = false;
        isMixedLoadingMore = false;
        notifyListeners();
      }
    }
  }

  void selectSubscription(String subId) {
    if (selectedSubscriptionId == subId) return;
    selectedSubscriptionId = subId;
    notifyListeners();
    updateMapRoute();
  }

  void _clearMap() {
    _routeFetchId++;
    mapRoutes = [];
    mapMarkers = [];
    isRouteLoading = false;
    notifyListeners();
  }

  Future<void> updateMapRoute() async {
    if (NetworkService.isOfflineNotifier.value) {
      _clearMap();
      return;
    }

    final requestId = ++_routeFetchId;
    mapRoutes = [];
    mapMarkers = [];
    isRouteLoading = true;
    notifyListeners();

    try {
      if (currentUserRole == 'passenger') {
        LatLng? start, end;
        if (showMatchingUI) {
          if (currentSelectedTrip == null) return _clearMap();
          start = FormatUtils.latLngFromMap(currentSelectedTrip!, 'pickup_lat', 'pickup_lng');
          end = FormatUtils.latLngFromMap(currentSelectedTrip!, 'dropoff_lat', 'dropoff_lng');
          if (start.latitude == 0.0 || end.latitude == 0.0) return _clearMap();
          if (requestId != _routeFetchId) return;

          mapRoutes = [
            (points: _getCurvedRoute(start, end), color: Colors.indigo, isTransit: false),
          ];
          mapMarkers = [
            (point: start, color: Colors.green, isSmallNode: false),
            (point: end, color: Colors.red, isSmallNode: false),
          ];
        } else {
          if (selectedSubscriptionId == null || activeSubscriptions.isEmpty) return _clearMap();
          final sub = activeSubscriptions.firstWhere((s) => s['id'] == selectedSubscriptionId, orElse: () => <String, dynamic>{});
          if (sub.isEmpty) return _clearMap();

          final built = await _buildSubscriptionRoute(sub);
          if (requestId != _routeFetchId) return;
          if (built == null) return _clearMap();

          mapRoutes = built.routes;
          mapMarkers = built.markers;
        }
      } else if (currentUserRole == 'driver') {
        if (showMatchingUI) {
          if (currentSelectedTrip == null) return _clearMap();
          final depart = FormatUtils.latLngFromMap(currentSelectedTrip!, 'depart_lat', 'depart_lng');
          final arrival = FormatUtils.latLngFromMap(currentSelectedTrip!, 'arrival_lat', 'arrival_lng');
          if (depart.latitude == 0.0 || arrival.latitude == 0.0) return _clearMap();
          if (requestId != _routeFetchId) return;

          mapRoutes = [
            (points: _getCurvedRoute(depart, arrival), color: Colors.indigo, isTransit: false),
          ];
          mapMarkers = [
            (point: depart, color: Colors.blue, isSmallNode: false),
            (point: arrival, color: Colors.orange, isSmallNode: false),
          ];
        } else {
          if (selectedSubscriptionId == null || activeSubscriptions.isEmpty) return _clearMap();
          final sub = activeSubscriptions.firstWhere((s) => s['id'] == selectedSubscriptionId, orElse: () => <String, dynamic>{});
          if (sub.isEmpty) return _clearMap();

          final depart = FormatUtils.latLngFromMap(sub, 'driver_depart_lat', 'driver_depart_lng');
          final pickup = FormatUtils.latLngFromMap(sub, 'pickup_lat', 'pickup_lng');
          final dropoff = FormatUtils.latLngFromMap(sub, 'dropoff_lat', 'dropoff_lng');
          final arrival = FormatUtils.latLngFromMap(sub, 'driver_arrival_lat', 'driver_arrival_lng');

          final validDepart = depart.latitude != 0.0 && depart.longitude != 0.0;
          final validArrival = arrival.latitude != 0.0 && arrival.longitude != 0.0;

          final segments = await Future.wait([
            validDepart ? _getCachedRoute(depart, pickup) : Future.value(<LatLng>[]),
            _getCachedRoute(pickup, dropoff),
            validArrival ? _getCachedRoute(dropoff, arrival) : Future.value(<LatLng>[]),
          ]);
          if (requestId != _routeFetchId) return;

          mapRoutes = [
            if (validDepart) (points: [depart, ...segments[0], pickup], color: Colors.blue, isTransit: false),
            (points: [pickup, ...segments[1], dropoff], color: Colors.indigo, isTransit: false),
            if (validArrival) (points: [dropoff, ...segments[2], arrival], color: Colors.blue, isTransit: false),
          ];
          mapMarkers = [
            if (validDepart) (point: depart, color: Colors.blue, isSmallNode: false),
            (point: pickup, color: Colors.green, isSmallNode: false),
            (point: dropoff, color: Colors.red, isSmallNode: false),
            if (validArrival) (point: arrival, color: Colors.orange, isSmallNode: false),
          ];
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error updating map route: $e');
    } finally {
      if (requestId == _routeFetchId) {
        isRouteLoading = false;
        notifyListeners();
      }
    }
  }

  Future<({List<({List<LatLng> points, Color color, bool isTransit})> routes, List<({LatLng point, Color color, bool isSmallNode})> markers})?> _buildSubscriptionRoute(
      Map<String, dynamic> sub,
      ) async {
    final legs = (sub['legs'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    if (legs.isEmpty) return null;

    final isMultiDriver = legs.length > 1;
    final routes = <({List<LatLng> points, Color color, bool isTransit})>[];
    final markers = <({LatLng point, Color color, bool isSmallNode})>[];

    const originColor = Colors.green;
    const destinationColor = Colors.red;
    const transferColor = Colors.deepPurple;
    const transitColor = Colors.teal;
    const walkColor = Colors.blueGrey;
    const lastLegColor = Colors.indigo;

    await GtfsService().initStations();

    final passStart = FormatUtils.latLngFromMap(sub, 'pass_pickup_lat', 'pass_pickup_lng');
    final passEnd = FormatUtils.latLngFromMap(sub, 'pass_dropoff_lat', 'pass_dropoff_lng');
    final firstLegStart = FormatUtils.latLngFromMap(legs.first, 'pickup_lat', 'pickup_lng');
    final lastLegEnd = FormatUtils.latLngFromMap(legs.last, 'dropoff_lat', 'dropoff_lng');

    final startGapDist = (passStart.latitude != 0.0 && passStart.longitude != 0.0)
        ? MatchingUtils.calculateDistance(passStart.latitude, passStart.longitude, firstLegStart.latitude, firstLegStart.longitude)
        : 0.0;

    final endGapDist = (passEnd.latitude != 0.0 && passEnd.longitude != 0.0)
        ? MatchingUtils.calculateDistance(passEnd.latitude, passEnd.longitude, lastLegEnd.latitude, lastLegEnd.longitude)
        : 0.0;

    final isMixedRoute = isMultiDriver || startGapDist > 1500 || endGapDist > 1500;
    final firstLegColor = isMixedRoute ? Colors.blue : Colors.indigo;

    // 1. GAP AT START
    if (startGapDist > 100) {
      if (startGapDist > 1500) {
        final boardStation = TransitUtils.findNearestStation(passStart);
        if (boardStation != null) {
          final walkRoute = await _getCachedRoute(passStart, boardStation.location, profile: 'foot-walking');
          routes.add((points: [passStart, ...walkRoute, boardStation.location], color: walkColor, isTransit: false));
          routes.add((points: [boardStation.location, firstLegStart], color: transitColor, isTransit: true));

          markers.add((point: passStart, color: originColor, isSmallNode: false));
          markers.add((point: boardStation.location, color: transferColor, isSmallNode: true));
          markers.add((point: firstLegStart, color: transferColor, isSmallNode: true));
        }
      } else {
        final walkRoute = await _getCachedRoute(passStart, firstLegStart, profile: 'foot-walking');
        routes.add((points: [passStart, ...walkRoute, firstLegStart], color: walkColor, isTransit: false));
        markers.add((point: passStart, color: originColor, isSmallNode: false));
        markers.add((point: firstLegStart, color: transferColor, isSmallNode: true));
      }
    } else {
      markers.add((point: firstLegStart, color: originColor, isSmallNode: false));
    }

    // 2. DRIVER LEGS
    LatLng? previousEnd;
    for (int i = 0; i < legs.length; i++) {
      final legStart = FormatUtils.latLngFromMap(legs[i], 'pickup_lat', 'pickup_lng');
      final legEnd = FormatUtils.latLngFromMap(legs[i], 'dropoff_lat', 'dropoff_lng');

      if (previousEnd != null && MatchingUtils.calculateDistance(previousEnd.latitude, previousEnd.longitude, legStart.latitude, legStart.longitude) > 100) {
        routes.add((points: [previousEnd, legStart], color: transitColor, isTransit: true));
        markers.add((point: legStart, color: transferColor, isSmallNode: true));
      }

      final route = await _getCachedRoute(legStart, legEnd);
      routes.add((points: [legStart, ...route, legEnd], color: i == 0 ? firstLegColor : lastLegColor, isTransit: false));

      final isLastLeg = (i == legs.length - 1);
      if (isLastLeg) {
        if (endGapDist <= 100) {
          markers.add((point: legEnd, color: destinationColor, isSmallNode: false));
        } else {
          markers.add((point: legEnd, color: transferColor, isSmallNode: true));
        }
      } else {
        markers.add((point: legEnd, color: transferColor, isSmallNode: true));
      }
      previousEnd = legEnd;
    }

    // 3. GAP AT END
    if (endGapDist > 100 && previousEnd != null) {
      if (endGapDist > 1500) {
        final alightStation = TransitUtils.findNearestStation(passEnd);
        if (alightStation != null) {
          routes.add((points: [previousEnd, alightStation.location], color: transitColor, isTransit: true));
          final walkRoute = await _getCachedRoute(alightStation.location, passEnd, profile: 'foot-walking');
          routes.add((points: [alightStation.location, ...walkRoute, passEnd], color: walkColor, isTransit: false));

          markers.add((point: alightStation.location, color: transferColor, isSmallNode: true));
          markers.add((point: passEnd, color: destinationColor, isSmallNode: false));
        }
      } else {
        final walkRoute = await _getCachedRoute(previousEnd, passEnd, profile: 'foot-walking');
        routes.add((points: [previousEnd, ...walkRoute, passEnd], color: walkColor, isTransit: false));
        markers.add((point: passEnd, color: destinationColor, isSmallNode: false));
      }
    }

    return (routes: routes, markers: markers);
  }

  List<Map<String, dynamic>> _mapSubscriptions(List<Map<String, dynamic>> rawSubs, {required bool isForPassenger}) {
    final legs = rawSubs.map((sub) => _mapSubscriptionLeg(sub, isForPassenger: isForPassenger)).toList();

    if (!isForPassenger) {
      final sortedDriverLegs = legs.map((leg) => _wrapSubscriptionCard([leg])).toList();
      sortedDriverLegs.sort((a, b) {
        final dateA = DateTime.tryParse(a['created_at'] ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
        final dateB = DateTime.tryParse(b['created_at'] ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
        return dateB.compareTo(dateA);
      });
      return sortedDriverLegs;
    }

    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final leg in legs) {
      final key = (leg['passenger_trip_id'] ?? leg['sub_id']).toString();
      grouped.putIfAbsent(key, () => []).add(leg);
    }

    final result = grouped.values.map((groupLegs) {
      groupLegs.sort((a, b) => (a['pickup_time_minutes'] as int).compareTo(b['pickup_time_minutes'] as int));
      return _wrapSubscriptionCard(groupLegs);
    }).toList();

    result.sort((a, b) {
      final dateA = DateTime.tryParse(a['created_at'] ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
      final dateB = DateTime.tryParse(b['created_at'] ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
      return dateB.compareTo(dateA);
    });

    return result;
  }

  Map<String, dynamic> _mapSubscriptionLeg(Map<String, dynamic> sub, {required bool isForPassenger}) {
    final tripKey = isForPassenger ? 'driver_trips' : 'passenger_trips';
    final myTripKey = isForPassenger ? 'passenger_trips' : 'driver_trips';
    final defaultName = isForPassenger ? 'Unknown Driver' : 'Unknown Passenger';
    final trip = sub[tripKey] ?? {};
    final myTrip = sub[myTripKey] ?? {};
    final user = trip['users'] ?? {};
    final driverTrip = isForPassenger ? trip : (sub['driver_trips'] ?? {});

    final driverId = sub['driver_id'] ?? (isForPassenger ? user['id'] : myTrip['user_id']);
    final passengerId = sub['passenger_id'] ?? (isForPassenger ? myTrip['user_id'] : user['id']);

    return {
      'sub_id': sub['id'],
      'created_at': sub['created_at'],
      'is_completed_today': sub['is_completed_today'] ?? false,
      'trip_name': myTrip['trip_name'] ?? 'My Trip',
      'passenger_trip_id': sub['passenger_trip_id'],
      'driver_trip_id': sub['driver_trip_id'],
      'driver_id': driverId,
      'passenger_id': passengerId,
      'pickup_lat': sub['pickup_lat'],
      'pickup_lng': sub['pickup_lng'],
      'dropoff_lat': sub['dropoff_lat'],
      'dropoff_lng': sub['dropoff_lng'],
      'pass_pickup_lat': myTrip['pickup_lat'],
      'pass_pickup_lng': myTrip['pickup_lng'],
      'pass_dropoff_lat': myTrip['dropoff_lat'],
      'pass_dropoff_lng': myTrip['dropoff_lng'],
      'driver_depart_lat': driverTrip['depart_lat'],
      'driver_depart_lng': driverTrip['depart_lng'],
      'driver_arrival_lat': driverTrip['arrival_lat'],
      'driver_arrival_lng': driverTrip['arrival_lng'],
      'name': user['name'] ?? defaultName,
      'phone': user['phone'] ?? 'N/A',
      'imageUrl': user['avatar_url'],
      'pickup_location': sub['pickup_location'] ?? 'Unknown',
      'dropoff_location': sub['dropoff_location'] ?? 'Unknown',
      'pickup_time': sub['pickup_time'] != null ? FormatUtils.formatSqlTimeToUI(sub['pickup_time']) : 'TBD',
      'pickup_time_minutes': _safeSqlTimeToMinutes(sub['pickup_time']),
    };
  }

  int _safeSqlTimeToMinutes(dynamic sqlTime) {
    if (sqlTime == null) return 1 << 30; // unknown time sorts last
    try {
      return FormatUtils.sqlTimeToMinutes(sqlTime);
    } catch (_) {
      return 1 << 30;
    }
  }

  Map<String, dynamic> _wrapSubscriptionCard(List<Map<String, dynamic>> legs) {
    final first = legs.first;
    final last = legs.last;
    final isMixed = legs.length > 1;

    return {
      'id': isMixed ? first['passenger_trip_id'].toString() : first['sub_id'],
      'sub_ids': legs.map((l) => l['sub_id']).toList(),
      'passenger_trip_id': first['passenger_trip_id'],
      'trip_name': first['trip_name'],
      'is_mixed': isMixed,
      'pickup_location': first['pickup_location'],
      'dropoff_location': last['dropoff_location'],
      'pickup_time': first['pickup_time'],
      'pass_pickup_lat': first['pass_pickup_lat'],
      'pass_pickup_lng': first['pass_pickup_lng'],
      'pass_dropoff_lat': first['pass_dropoff_lat'],
      'pass_dropoff_lng': first['pass_dropoff_lng'],
      'legs': legs,
      if (!isMixed) ...{
        'driver_trip_id': first['driver_trip_id'],
        'pickup_lat': first['pickup_lat'],
        'pickup_lng': first['pickup_lng'],
        'dropoff_lat': first['dropoff_lat'],
        'dropoff_lng': first['dropoff_lng'],
        'driver_depart_lat': first['driver_depart_lat'],
        'driver_depart_lng': first['driver_depart_lng'],
        'driver_arrival_lat': first['driver_arrival_lat'],
        'driver_arrival_lng': first['driver_arrival_lng'],
        'name': first['name'],
        'phone': first['phone'],
        'imageUrl': first['imageUrl'],
      },
    };
  }

  List<LatLng> _getCurvedRoute(LatLng start, LatLng end, {int segments = 60}) {
    final double midLat = (start.latitude + end.latitude) / 2;
    final double midLng = (start.longitude + end.longitude) / 2;
    final double dLat = end.latitude - start.latitude;
    final double dLng = end.longitude - start.longitude;
    const double offset = -0.6;
    final double ctrlLat = midLat - dLng * offset;
    final double ctrlLng = midLng + dLat * offset;

    List<LatLng> points = [];
    for (int i = 0; i <= segments; i++) {
      double t = i / segments;
      double lat = (1 - t) * (1 - t) * start.latitude + 2 * (1 - t) * t * ctrlLat + t * t * end.latitude;
      double lng = (1 - t) * (1 - t) * start.longitude + 2 * (1 - t) * t * ctrlLng + t * t * end.longitude;
      points.add(LatLng(lat, lng));
    }
    return points;
  }

  void _validateCurrentSelectedTrip() {
    if (availableTrips.isNotEmpty) {
      if (currentSelectedTrip == null || !availableTrips.any((t) => t['id'] == currentSelectedTrip!['id'])) {
        currentSelectedTrip = availableTrips.first;
      }
    } else {
      currentSelectedTrip = null;
    }
  }

  Future<void> refreshHome() async {
    showMatchingUI = false;
    selectedSubscriptionId = null;
    _matchingUiEpoch++;

    _hasFoundDirect = false;
    _hasFoundMixed = false;
    matchedDrivers.clear();
    mixedMatchedRoutes.clear();

    await fetchCurrentUser();
  }

  Future<Map<String, dynamic>?> fetchSubscriptionForNotification(
      String subscriptionId,
      String role,
      ) {
    return _subscriptionService.fetchSubscriptionForNotification(subscriptionId, role);
  }
}