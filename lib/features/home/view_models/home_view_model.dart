import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:nak_tumpang/core/utils/matching_utils.dart';
import 'package:nak_tumpang/core/services/ors_service.dart';
import 'package:nak_tumpang/features/home/data/services/home_supabase_service.dart';

enum HomePanelMode { schedule, cantFetch, noNeedFetch }

class HomeViewModel extends ChangeNotifier {
  String selectedFilter = 'Direct';
  Map<String, dynamic>? currentPassenger;
  Map<String, dynamic>? currentPassengerTrip;
  bool isLoading = true;

  final ORSService _orsService = ORSService();
  final HomeSupabaseService _homeService = HomeSupabaseService();

  List<Map<String, dynamic>> matchedDrivers = [];

  // --- Exception panel state ---
  HomePanelMode panelMode = HomePanelMode.schedule;
  DateTime? exceptionStartDate;
  DateTime? exceptionEndDate;
  String? exceptionReason;
  final TextEditingController exceptionCustomReasonController = TextEditingController();
  bool isSubmittingException = false;
  String? exceptionError;

  static const List<String> passengerReasons = [
    'Medical leave', 'Public holiday', 'Emergency', 'Personal reasons', 'Others',
  ];
  static const List<String> driverReasons = [
    'Medical leave', 'Public holiday', 'Emergency', 'Vehicle issue', 'Personal reasons', 'Others',
  ];

  void setFilter(String option) {
    selectedFilter = option;
    notifyListeners();
  }

  Future<void> fetchMockPassenger() async {
    isLoading = true;
    notifyListeners();

    final trip = await _homeService.fetchPassengerTrip('31db9203-05d0-42af-8641-50e48e9c163a');

    if (trip != null) {
      currentPassengerTrip = trip;
      currentPassenger = trip['users'];
      await _findAvailableDrivers();
    } else {
      print('❌ Failed to fetch passenger trip.');
    }

    isLoading = false;
    notifyListeners();
  }

  Future<void> _findAvailableDrivers() async {
    if (currentPassengerTrip == null) {
      print('❌ Passenger trip is null. Aborting.');
      return;
    }

    final passDays = _extractActiveDays(currentPassengerTrip!);

    final passPick = LatLng(
        _parseDouble(currentPassengerTrip!['pickup_lat']),
        _parseDouble(currentPassengerTrip!['pickup_lng'])
    );
    final passDrop = LatLng(
        _parseDouble(currentPassengerTrip!['dropoff_lat']),
        _parseDouble(currentPassengerTrip!['dropoff_lng'])
    );

    final passTime = _sqlTimeToMinutes(currentPassengerTrip!['desired_pickup_time']);

    matchedDrivers.clear();
    notifyListeners();

    final driverTrips = await _homeService.fetchDriverTrips();
    print('🔍 Found ${driverTrips.length} drivers in Supabase.');

    for (var driverTrip in driverTrips) {
      final driverName = driverTrip['users']?['name'] ?? 'Unknown Driver';
      print('\n🚗 Evaluating Driver: $driverName');

      final driverDays = _extractActiveDays(driverTrip);

      if (!MatchingUtils.hasOverlappingDays(passDays, driverDays)) {
        print('   -> ❌ Failed Day Filter');
        continue;
      }

      final drivTime = _sqlTimeToMinutes(driverTrip['depart_time']);
      if ((drivTime - passTime).abs() > 30) {
        print('   -> ❌ Failed Time Filter (Pass: $passTime mins, Driv: $drivTime mins)');
        continue;
      }

      final drivStart = LatLng(
          _parseDouble(driverTrip['depart_lat']),
          _parseDouble(driverTrip['depart_lng'])
      );

      final drivEnd = LatLng(
          _parseDouble(driverTrip['arrival_lat']),
          _parseDouble(driverTrip['arrival_lng'])
      );

      if (drivStart.latitude == 0 || drivEnd.latitude == 0) {
        print('   -> ❌ Failed: Missing or Null coordinates for this driver.');
        continue;
      }

      final pickDist = MatchingUtils.calculateDistance(
          passPick.latitude, passPick.longitude,
          drivStart.latitude, drivStart.longitude
      );
      final dropDist = MatchingUtils.calculateDistance(
          passDrop.latitude, passDrop.longitude,
          drivEnd.latitude, drivEnd.longitude
      );

      if (pickDist > 15000 || dropDist > 15000) {
        print('   -> ❌ Failed Radius Filter (Pick: ${pickDist.toStringAsFixed(0)}m, Drop: ${dropDist.toStringAsFixed(0)}m)');
        continue;
      }

      try {
        final driverRoute = await _orsService.getRoute(drivStart, drivEnd);
        bool isMatch = MatchingUtils.isRouteMatch(passPick, passDrop, driverRoute, 800);

        if (isMatch) {
          print('   -> ✅ PERFECT MATCH!');
          matchedDrivers.add({
            'id': driverTrip['user_id'],
            'name': driverName,
            'pickup_distance_km': pickDist / 1000,
            'driver_profile': {
              'depart_time': _formatSqlTimeToUI(driverTrip['depart_time']),
            }
          });
        } else {
          print('   -> ❌ Failed ORS Route Match (Detour too far)');
        }
      } catch (e) {
        print('   -> ⚠️ ORS Route Error: $e');
        continue;
      }
    }

    print('\n🏁 Matching Complete. Found ${matchedDrivers.length} suitable drivers.');
    notifyListeners();
  }

  // --- Exception panel logic ---

  void openCantFetchPanel() {
    panelMode = HomePanelMode.cantFetch;
    notifyListeners();
  }

  void openNoNeedFetchPanel() {
    panelMode = HomePanelMode.noNeedFetch;
    notifyListeners();
  }

  void closeExceptionPanel() {
    panelMode = HomePanelMode.schedule;
    exceptionStartDate = null;
    exceptionEndDate = null;
    exceptionReason = null;
    exceptionCustomReasonController.clear();
    notifyListeners();
  }

  void setExceptionStartDate(DateTime date) {
    exceptionStartDate = date;
    if (exceptionEndDate != null && exceptionEndDate!.isBefore(date)) exceptionEndDate = null;
    notifyListeners();
  }

  void setExceptionEndDate(DateTime date) {
    if (exceptionStartDate != null && date.isBefore(exceptionStartDate!)) return;
    exceptionEndDate = date;
    notifyListeners();
  }

  void setExceptionReason(String? reason) {
    exceptionReason = reason;
    notifyListeners();
  }

  Future<bool> submitException({
    required String tumpangSubscriptionId,
    required String initiatedBy,
    required String initiatedByRole,
  }) async {
    if (exceptionStartDate == null || exceptionEndDate == null || exceptionReason == null) return false;
    if (exceptionReason == 'Others' && exceptionCustomReasonController.text.trim().isEmpty) return false;

    isSubmittingException = true;
    notifyListeners();

    final reasonText = exceptionReason == 'Others'
        ? exceptionCustomReasonController.text.trim()
        : exceptionReason!;

    final success = await _homeService.submitException(
      tumpangSubscriptionId: tumpangSubscriptionId,
      initiatedBy: initiatedBy,
      initiatedByRole: initiatedByRole,
      startDate: exceptionStartDate!,
      endDate: exceptionEndDate!,
      reason: reasonText,
    );

    isSubmittingException = false;
    if (!success) exceptionError = 'Failed to submit exception.';
    notifyListeners();
    return success;
  }

  // --- Helpers ---

  double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }

  int _sqlTimeToMinutes(String sqlTime) {
    final parts = sqlTime.split(':');
    final hours = int.parse(parts[0]);
    final minutes = int.parse(parts[1]);
    return (hours * 60) + minutes;
  }

  String _formatSqlTimeToUI(String sqlTime) {
    final parts = sqlTime.split(':');
    int hours = int.parse(parts[0]);
    final minutes = parts[1];

    final period = hours >= 12 ? 'PM' : 'AM';
    if (hours > 12) hours -= 12;
    if (hours == 0) hours = 12;

    final hoursStr = hours.toString().padLeft(2, '0');
    return '$hoursStr:$minutes $period';
  }

  Map<String, bool> _extractActiveDays(Map<String, dynamic> row) {
    return {
      'monday': row['active_monday'] ?? false,
      'tuesday': row['active_tuesday'] ?? false,
      'wednesday': row['active_wednesday'] ?? false,
      'thursday': row['active_thursday'] ?? false,
      'friday': row['active_friday'] ?? false,
      'saturday': row['active_saturday'] ?? false,
      'sunday': row['active_sunday'] ?? false,
    };
  }

  @override
  void dispose() {
    exceptionCustomReasonController.dispose();
    super.dispose();
  }
}