import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nak_tumpang/core/utils/matching_utils.dart';
import 'package:nak_tumpang/core/services/ors_service.dart';
import 'package:nak_tumpang/features/home/data/services/home_supabase_service.dart';
import 'package:nak_tumpang/core/services/gtfs_service.dart';
import 'package:nak_tumpang/core/utils/transit_utils.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:uuid/uuid.dart';
import 'package:nak_tumpang/features/home/data/services/home_local_service.dart';
import 'package:nak_tumpang/core/utils/format_utils.dart';
import 'package:nak_tumpang/core/services/network_service.dart';

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

  // --- NEW: Separate loading states for pagination ---
  bool isDirectLoadingMore = false;
  bool isMixedLoadingMore = false;

  bool showMatchingUI = false;
  bool _hasFoundDirect = false;
  bool _hasFoundMixed = false;

  int _fetchId = 0;
  int _routeFetchId = 0;
  int _userFetchId = 0;

  int currentDirectLimit = 5;
  int currentMixedLimit = 5;
  bool hasMoreDirect = false;
  bool hasMoreMixed = false;

  final ORSService _orsService = ORSService();
  final HomeSupabaseService _homeService = HomeSupabaseService();
  final GoTrueClient _auth = Supabase.instance.client.auth;

  List<Map<String, dynamic>> matchedDrivers = [];
  List<Map<String, dynamic>> mixedMatchedRoutes = [];

  // ==========================================
  // EXCEPTION PANEL (can't fetch / no need fetch)
  // ==========================================

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

  // Add selected subscription state
  Map<String, dynamic>? selectedSubscription;

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
    // keep end date valid if it's now before the new start date
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
      return success;
    } catch (e) {
      print('⚠️ Error submitting exception: $e');
      return false;
    } finally {
      isSubmittingException = false;
      notifyListeners();
    }
  }



  @override
  void dispose() {
    exceptionCustomReasonController.dispose();
    super.dispose();
  }

  List<({List<LatLng> points, Color color})> mapRoutes = [];
  List<({LatLng point, Color color})> mapMarkers = [];

  final Map<String, List<LatLng>> _routeCache = {};

  HomeViewModel() {
    // Listen for network changes to auto-refresh
    NetworkService.isOfflineNotifier.addListener(_onNetworkChange);
  }

  @override
  void dispose() {
    NetworkService.isOfflineNotifier.removeListener(_onNetworkChange);
    super.dispose();
  }

  void _onNetworkChange() {
    notifyListeners(); // Tells the UI to hide/show the map tiles
    if (!NetworkService.isOfflineNotifier.value) {
      // Internet is back! Refresh data from Supabase.
      fetchCurrentUser();
    }
  }

  // --- UPDATED: Directly call the fetcher instead of resetting the whole screen state ---
  void loadMoreDirect() {
    if (isDirectLoadingMore) return;
    currentDirectLimit += 5;
    isDirectLoadingMore = true;
    notifyListeners();
    _findDirectDrivers();
  }

  void loadMoreMixed() {
    if (isMixedLoadingMore) return;
    currentMixedLimit += 5;
    isMixedLoadingMore = true;
    notifyListeners();
    _findMixedRoutes();
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
      currentDirectLimit = 5;
      currentMixedLimit = 5;
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
        _matchCurrentRouteType();
      }
    } else if (currentSelectedTrip == null && availableTrips.length == 1) {
      changeTrip(trip['id']);
    }
    notifyListeners();
  }

  void removeLocalTrip(String tripId) {
    availableTrips.removeWhere((t) => t['id'] == tripId);

    if (currentSelectedTrip?['id'] == tripId) {
      currentSelectedTrip = availableTrips.isNotEmpty ? availableTrips.first : null;
      currentDirectLimit = 5;
      currentMixedLimit = 5;
      isDirectLoadingMore = false;
      isMixedLoadingMore = false;
      hasMoreDirect = false;
      hasMoreMixed = false;
      _hasFoundDirect = false;
      _hasFoundMixed = false;
      matchedDrivers.clear();
      mixedMatchedRoutes.clear();
      updateMapRoute();
      if (showMatchingUI && currentSelectedTrip != null) {
        _matchCurrentRouteType();
      }
    }
    notifyListeners();
  }

  Future<List<LatLng>> _getCachedRoute(LatLng start, LatLng end) async {
    final cacheKey = '${start.latitude},${start.longitude}-${end.latitude},${end.longitude}';

    if (_routeCache.containsKey(cacheKey)) {
      return _routeCache[cacheKey]!;
    }

    final route = await _orsService.getRoute(start, end);
    _routeCache[cacheKey] = route;
    return route;
  }

  void toggleMatchingUI(bool show) {
    showMatchingUI = show;
    notifyListeners();
    updateMapRoute();
    if (show) {
      _matchCurrentRouteType();
    }
  }

  void setFilter(String option) {
    if (selectedFilter == option) return;
    selectedFilter = option;
    notifyListeners();

    if (showMatchingUI) {
      _matchCurrentRouteType();
    }
  }

  Future<void> fetchCurrentUser() async {
    final requestId = ++_userFetchId;
    isScreenLoading = true;

    _routeCache.clear();

    currentUserRole = 'passenger';
    currentUser = null;
    currentSelectedTrip = null;
    availableTrips = [];
    activeSubscriptions = [];
    selectedSubscriptionId = null;
    showMatchingUI = false;

    currentDirectLimit = 5;
    currentMixedLimit = 5;
    isDirectLoadingMore = false;
    isMixedLoadingMore = false;
    hasMoreDirect = false;
    hasMoreMixed = false;
    _hasFoundDirect = false;
    _hasFoundMixed = false;
    matchedDrivers = [];
    mixedMatchedRoutes = [];
    mapRoutes = [];
    mapMarkers = [];
    isRouteLoading = false;
    notifyListeners();

    final authUser = _auth.currentUser;

    // --- Fix #1: Clear loading state before returning unauthenticated ---
    if (authUser == null) {
      if (requestId == _userFetchId) {
        isScreenLoading = false;
        notifyListeners();
      }
      return;
    }

    final localRole = await HomeLocalService().getUserRole(authUser.id);
    currentUserRole = localRole ?? 'passenger';

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
      debugPrint('⚠️ Profile fetch failed, proceeding with local role ($currentUserRole): $e');
    }

    if (currentUserRole == 'driver') {
      await _loadDriverData(authUser.id, requestId);
    } else {
      await _loadPassengerData(authUser.id, requestId);
    }

    if (requestId == _userFetchId) {
      isScreenLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadDriverData(String userId, int requestId) async {
    List<Map<String, dynamic>> rawSubs = [];
    List<Map<String, dynamic>> allDriverTrips = [];
    List<Map<String, dynamic>> myTrips = []; // Track only current user's trips locally

    if (NetworkService.isOfflineNotifier.value) {
      myTrips = await HomeLocalService().getCachedUserTrips(userId, isForPassenger: false);
      rawSubs = await HomeLocalService().getCachedSubscriptions(userId, isForPassenger: false);
      allDriverTrips = myTrips;
    } else {
      try {
        rawSubs = await _homeService.fetchDriverActiveSubscriptions(userId);
        allDriverTrips = await _homeService.fetchDriverTrips();

        // --- Fix #2: Filter only current user's driver trips before caching ---
        myTrips = allDriverTrips.where((trip) => trip['user_id'] == userId).toList();

        // --- Fix #3: Save both using the atomic transaction ---
        await HomeLocalService().cacheHomeData(
          trips: myTrips,
          rawSubs: rawSubs,
          isForPassenger: false,
          currentUserId: userId,
        );
      } catch (e) {
        debugPrint('⚠️ Network error, falling back to SQLite cache (Driver): $e');
        myTrips = await HomeLocalService().getCachedUserTrips(userId, isForPassenger: false);
        rawSubs = await HomeLocalService().getCachedSubscriptions(userId, isForPassenger: false);
        allDriverTrips = myTrips;
      }
    }

    if (requestId != _userFetchId) return;

    activeSubscriptions = _mapSubscriptions(rawSubs, isForPassenger: false);
    final subbedTripIds = activeSubscriptions.map((s) => s['driver_trip_id']).toSet();
    availableTrips = myTrips.where((t) => !subbedTripIds.contains(t['id'])).toList();

    if (availableTrips.isNotEmpty) {
      currentSelectedTrip = availableTrips.first;
    }

    if (activeSubscriptions.isNotEmpty) {
      selectedSubscriptionId = activeSubscriptions.first['id'];
    }

    showMatchingUI = activeSubscriptions.isEmpty;
    updateMapRoute();
  }

  Future<void> _loadPassengerData(String userId, int requestId) async {
    List<Map<String, dynamic>> rawSubs = [];
    List<Map<String, dynamic>> trips = [];

    if (NetworkService.isOfflineNotifier.value) {
      trips = await HomeLocalService().getCachedUserTrips(userId, isForPassenger: true);
      rawSubs = await HomeLocalService().getCachedSubscriptions(userId, isForPassenger: true);
    } else {
      try {
        trips = await _homeService.fetchPassengerTrips(userId);
        rawSubs = await _homeService.fetchAllPassengerSubscriptions(userId);

        // --- Fix #3: Save both using the atomic transaction ---
        await HomeLocalService().cacheHomeData(
          trips: trips,
          rawSubs: rawSubs,
          isForPassenger: true,
          currentUserId: userId,
        );
      } catch (e) {
        debugPrint('⚠️ Network error, falling back to SQLite cache (Passenger): $e');
        trips = await HomeLocalService().getCachedUserTrips(userId, isForPassenger: true);
        rawSubs = await HomeLocalService().getCachedSubscriptions(userId, isForPassenger: true);
      }
    }

    if (requestId != _userFetchId) return;

    activeSubscriptions = _mapSubscriptions(rawSubs, isForPassenger: true);
    final subbedTripIds = activeSubscriptions.map((s) => s['passenger_trip_id']).toSet();
    availableTrips = trips.where((t) => !subbedTripIds.contains(t['id'])).toList();

    if (availableTrips.isNotEmpty) {
      currentSelectedTrip = availableTrips.first;
    }

    if (activeSubscriptions.isNotEmpty) {
      selectedSubscriptionId = activeSubscriptions.first['id'];
    }

    showMatchingUI = activeSubscriptions.isEmpty;
    updateMapRoute();

    if (showMatchingUI && currentSelectedTrip != null) {
      await _matchCurrentRouteType();
    }
  }

  Future<void> changeTrip(String tripId) async {
    try {
      final selected = availableTrips.firstWhere((t) => t['id'] == tripId);
      currentSelectedTrip = selected;

      currentDirectLimit = 5;
      currentMixedLimit = 5;
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

    // --- UPDATED: Only wipe the list and show big spinner if it is a fresh load ---
    if (!isDirectLoadingMore) {
      isDirectLoading = true;
      matchedDrivers.clear();
    }
    notifyListeners();

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
    isDirectLoading = false;
    isDirectLoadingMore = false; // Turn off bottom spinner
    notifyListeners();
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
    // Prevent duplicate concurrent requests
    if (_isCompletingTrip) return false;

    _isCompletingTrip = true;
    notifyListeners(); // Disables UI immediately

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


  Future<void> _findMixedRoutes() async {
    if (currentSelectedTrip == null) return;

    final currentFetchId = ++_fetchId;

    // --- UPDATED: Only wipe the list and show big spinner if it is a fresh load ---
    if (!isMixedLoadingMore) {
      isMixedLoading = true;
      mixedMatchedRoutes.clear();
    }
    notifyListeners();

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

    try {
      final pickStation = TransitUtils.findNearestStation(passPick);
      final dropStation = TransitUtils.findNearestStation(passDrop);

      if (pickStation == null || dropStation == null) {
        _hasFoundMixed = true;
        isMixedLoading = false;
        isMixedLoadingMore = false;
        notifyListeners();
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
          if ((drivTime - passTime).abs() <= 30) {
            final pickDist = MatchingUtils.calculateDistance(
              passPick.latitude, passPick.longitude, drivStart.latitude, drivStart.longitude,
            );
            final dropDistToStation = MatchingUtils.calculateDistance(
              pickStation.location.latitude, pickStation.location.longitude, drivEnd.latitude, drivEnd.longitude,
            );

            if (pickDist <= 15000 && dropDistToStation <= 15000) {
              final driverRoute = await _getCachedRoute(drivStart, drivEnd);
              if (_fetchId != currentFetchId) return;

              if (MatchingUtils.isRouteMatch(passPick, pickStation.location, driverRoute, 800)) {
                final routeDistToStation = MatchingUtils.calculateDistance(
                  passPick.latitude, passPick.longitude, pickStation.location.latitude, pickStation.location.longitude,
                );
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
            }
          }

          if (drivTime > passTime) {
            final pickDistFromStation = MatchingUtils.calculateDistance(
              dropStation.location.latitude, dropStation.location.longitude, drivStart.latitude, drivStart.longitude,
            );
            final dropDistToDest = MatchingUtils.calculateDistance(
              passDrop.latitude, passDrop.longitude, drivEnd.latitude, drivEnd.longitude,
            );

            if (pickDistFromStation <= 15000 && dropDistToDest <= 15000) {
              final driverRoute = await _getCachedRoute(drivStart, drivEnd);
              if (_fetchId != currentFetchId) return;

              if (MatchingUtils.isRouteMatch(dropStation.location, passDrop, driverRoute, 800)) {
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
          if (fm['type'] == 'Walk' && lm['type'] == 'Walk') {
            continue;
          }

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
    } catch (e) {
      print('Error generating mixed routes: $e');
    }

    if (_fetchId != currentFetchId) return;

    mixedMatchedRoutes = tempMixedRoutes.take(currentMixedLimit).toList();
    hasMoreMixed = moreAvailable || tempMixedRoutes.length > currentMixedLimit;

    _hasFoundMixed = true;
    isMixedLoading = false;
    isMixedLoadingMore = false; // Turn off bottom spinner
    notifyListeners();
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
        } else {
          if (selectedSubscriptionId == null || activeSubscriptions.isEmpty) return _clearMap();
          final sub = activeSubscriptions.firstWhere((s) => s['id'] == selectedSubscriptionId, orElse: () => <String, dynamic>{});
          if (sub.isEmpty) return _clearMap();

          start = FormatUtils.latLngFromMap(sub, 'pickup_lat', 'pickup_lng');
          end = FormatUtils.latLngFromMap(sub, 'dropoff_lat', 'dropoff_lng');
        }

        if (start.latitude == 0.0 || end.latitude == 0.0) return _clearMap();

        final route = await _getCachedRoute(start, end);
        if (requestId != _routeFetchId) return;

        mapRoutes = [
          // Changed from blueAccent to indigo
          (points: [start, ...route, end], color: Colors.indigo),
        ];
        mapMarkers = [
          (point: start, color: Colors.green),
          (point: end, color: Colors.red),
        ];
      }
      else if (currentUserRole == 'driver') {
        if (showMatchingUI) {
          if (currentSelectedTrip == null) return _clearMap();
          final depart = FormatUtils.latLngFromMap(currentSelectedTrip!, 'depart_lat', 'depart_lng');
          final arrival = FormatUtils.latLngFromMap(currentSelectedTrip!, 'arrival_lat', 'arrival_lng');

          if (depart.latitude == 0.0 || arrival.latitude == 0.0) return _clearMap();

          final route = await _getCachedRoute(depart, arrival);
          if (requestId != _routeFetchId) return;

          mapRoutes = [
            // Changed from blueAccent to indigo
            (points: [depart, ...route, arrival], color: Colors.indigo),
          ];
          mapMarkers = [
            (point: depart, color: Colors.blue),
            (point: arrival, color: Colors.orange),
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
            if (validDepart) (points: [depart, ...segments[0], pickup], color: AppColors.primaryYellow),
            // Changed from blueAccent to indigo
            (points: [pickup, ...segments[1], dropoff], color: Colors.indigo),
            if (validArrival) (points: [dropoff, ...segments[2], arrival], color: AppColors.primaryYellow),
          ];

          mapMarkers = [
            if (validDepart) (point: depart, color: Colors.blue),
            (point: pickup, color: Colors.green),
            (point: dropoff, color: Colors.red),
            if (validArrival) (point: arrival, color: Colors.orange),
          ];
        }
      }
    } catch (e) {
      print('⚠️ Error updating map route: $e');
    } finally {
      if (requestId == _routeFetchId) {
        isRouteLoading = false;
        notifyListeners();
      }
    }
  }

  List<Map<String, dynamic>> _mapSubscriptions(List<Map<String, dynamic>> rawSubs, {required bool isForPassenger}) {
    return rawSubs.map((sub) {
      final tripKey = isForPassenger ? 'driver_trips' : 'passenger_trips';
      final myTripKey = isForPassenger ? 'passenger_trips' : 'driver_trips'; // Added
      final defaultName = isForPassenger ? 'Unknown Driver' : 'Unknown Passenger';

      final trip = sub[tripKey] ?? {};
      final myTrip = sub[myTripKey] ?? {}; // Added
      final user = trip['users'] ?? {};
      final driverTrip = isForPassenger ? trip : (sub['driver_trips'] ?? {});
      final driverId = isForPassenger ? (user['id'] ?? '') : (currentUserId ?? '');
      final passengerId = isForPassenger ? (currentUserId ?? '') : (user['id'] ?? '');



      return {
        'id': sub['id'],
        'trip_name': myTrip['trip_name'] ?? 'My Trip', // Added
        'driver_id': driverId,
        'passenger_id': passengerId,
        'other_party_id': user['id'],
        'passenger_trip_id': sub['passenger_trip_id'],
        'driver_trip_id': sub['driver_trip_id'],
        'pickup_lat': sub['pickup_lat'],
        'pickup_lng': sub['pickup_lng'],
        'dropoff_lat': sub['dropoff_lat'],
        'dropoff_lng': sub['dropoff_lng'],

        'driver_depart_lat': driverTrip['depart_lat'],
        'driver_depart_lng': driverTrip['depart_lng'],
        'driver_arrival_lat': driverTrip['arrival_lat'],
        'driver_arrival_lng': driverTrip['arrival_lng'],

        'name': user['name'] ?? defaultName,
        'phone': user['phone'] ?? 'N/A',
        'imageUrl': user['avatar_url'],
        'pickup_location': sub['pickup_location'] ?? 'Unknown',
        'dropoff_location': sub['dropoff_location'] ?? 'Unknown',
        'pickup_time': sub['pickup_time'] != null ? _formatSqlTimeToUI(sub['pickup_time']) : 'TBD',
        'subscription_start_date': sub['subscription_start_date'],
        'subscription_end_date': sub['subscription_end_date'],
        'fee': sub['fee'],
        'status': sub['status'] ?? 'active',
        'is_completed_today': sub['is_completed_today'] ?? false,
        'deposit': sub['deposit'],
        'deposit_refunded': sub['deposit_refunded'],
        'ended_by': sub['ended_by'],
        'pickup_time': sub['pickup_time'] != null
            ? FormatUtils.formatSqlTimeToUI(sub['pickup_time'])
            : 'TBD',
      };
    }).toList();
  }
}