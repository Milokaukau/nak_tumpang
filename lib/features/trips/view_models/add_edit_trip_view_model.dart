import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:nak_tumpang/core/entities/geocoded_place.dart';
import 'package:nak_tumpang/features/trips/data/services/trip_supabase_service.dart';

class AddEditTripViewModel extends ChangeNotifier {
  final TripSupabaseService _tripService = TripSupabaseService();
  final String role;
  final Map<String, dynamic>? existingTrip;

  final nameController = TextEditingController();
  final fromController = TextEditingController();
  final toController = TextEditingController();

  GeocodedPlace? fromPlace;
  GeocodedPlace? toPlace;

  int fromDay = 1;
  int toDay = 5;

  TimeOfDay departTime = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay arriveTime = const TimeOfDay(hour: 9, minute: 0);

  bool isSubmitting = false;
  String? errorMessage;
  String? nameError;
  String? fromError;
  String? toError;
  String? timeError;
  String? dayError;

  AddEditTripViewModel(this.role, {this.existingTrip}) {
    if (existingTrip != null) {
      _initFromExistingTrip();
    }
  }

  int _minutesOf(TimeOfDay t) => t.hour * 60 + t.minute;

  /// Shared by setFromPlace/setToPlace (live, as soon as both places are
  /// picked) and _validate() (final check before submit) — one place
  /// for this rule instead of two copies that could drift apart.
  void _revalidateLocations() {
    if (fromPlace == null || toPlace == null) return;
    final samePlace =
        fromPlace!.latitude == toPlace!.latitude && fromPlace!.longitude == toPlace!.longitude;
    if (samePlace) {
      toError = "Pickup and drop-off can't be the same location";
    } else if (toError == "Pickup and drop-off can't be the same location") {
      toError = null;
    }
  }

  /// Shared by setDepartTime/setArriveTime (live) and _validate() (final
  /// check) — arrival has to be chronologically after departure, not
  /// just "not exactly equal" (the old check let e.g. an 8am arrival
  /// with a 5pm departure through).
  void _revalidateTime() {
    if (_minutesOf(arriveTime) <= _minutesOf(departTime)) {
      timeError = 'Arrival time must be after departure time';
    } else {
      timeError = null;
    }
  }

  void _initFromExistingTrip() {
    nameController.text = existingTrip!['trip_name'] ?? '';

    final rawDepart = role == 'driver' ? existingTrip!['depart_time'] : existingTrip!['desired_pickup_time'];
    final rawArrive = role == 'driver' ? existingTrip!['arrival_time'] : existingTrip!['desired_dropoff_time'];
    if (rawDepart != null) departTime = _parseTime(rawDepart);
    if (rawArrive != null) arriveTime = _parseTime(rawArrive);

    fromDay = _findFirstActiveDay(existingTrip!);
    toDay = _findLastActiveDay(existingTrip!);

    final startName = role == 'driver' ? existingTrip!['depart_name'] : existingTrip!['pickup_name'];
    final endName = role == 'driver' ? existingTrip!['arrival_name'] : existingTrip!['dropoff_name'];

    final startLat = role == 'driver' ? existingTrip!['depart_lat'] : existingTrip!['pickup_lat'];
    final startLng = role == 'driver' ? existingTrip!['depart_lng'] : existingTrip!['pickup_lng'];

    final endLat = role == 'driver' ? existingTrip!['arrival_lat'] : existingTrip!['dropoff_lat'];
    final endLng = role == 'driver' ? existingTrip!['arrival_lng'] : existingTrip!['dropoff_lng'];

    if (startName != null && startLat != null && startLng != null) {
      fromController.text = startName;
      fromPlace = GeocodedPlace(
        label: startName,
        latitude: double.parse(startLat.toString()),
        longitude: double.parse(startLng.toString()),
      );
    }

    if (endName != null && endLat != null && endLng != null) {
      toController.text = endName;
      toPlace = GeocodedPlace(
        label: endName,
        latitude: double.parse(endLat.toString()),
        longitude: double.parse(endLng.toString()),
      );
    }
  }

  TimeOfDay _parseTime(String sqlTime) {
    try {
      final parts = sqlTime.split(':');
      return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    } catch (e) {
      return const TimeOfDay(hour: 8, minute: 0);
    }
  }

  int _findFirstActiveDay(Map<String, dynamic> trip) {
    final days = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];
    for (int i = 0; i < days.length; i++) {
      if (trip['active_${days[i]}'] == true) return i + 1;
    }
    return 1;
  }

  int _findLastActiveDay(Map<String, dynamic> trip) {
    final days = ['sunday', 'saturday', 'friday', 'thursday', 'wednesday', 'tuesday', 'monday'];
    for (int i = 0; i < days.length; i++) {
      if (trip['active_${days[i]}'] == true) return 7 - i;
    }
    return 5;
  }

  void setFromPlace(GeocodedPlace place) {
    fromPlace = place;
    fromError = null;
    _revalidateLocations();
    notifyListeners();
  }

  void clearFromPlace() {
    if (fromPlace == null) return;
    fromPlace = null;
    // _revalidateLocations() early-returns once either place is null, so
    // it can never clear this itself — the same-location conflict is
    // moot with only one place picked, but any other toError (e.g. "pick
    // a valid destination") is still real and stays.
    if (toError == "Pickup and drop-off can't be the same location") {
      toError = null;
    }
    notifyListeners();
  }

  void setToPlace(GeocodedPlace place) {
    toPlace = place;
    toError = null;
    _revalidateLocations();
    notifyListeners();
  }

  void clearToPlace() {
    if (toPlace == null) return;
    toPlace = null;
    // Same reasoning as clearFromPlace — the same-location conflict no
    // longer applies once toPlace is unset, but leave any other toError
    // (e.g. "pick a valid destination") alone.
    if (toError == "Pickup and drop-off can't be the same location") {
      toError = null;
    }
    notifyListeners();
  }

  void setFromDay(int day) {
    fromDay = day;
    notifyListeners();
  }

  void setToDay(int day) {
    toDay = day;
    notifyListeners();
  }

  void setDepartTime(TimeOfDay time) {
    departTime = time;
    _revalidateTime();
    notifyListeners();
  }

  void setArriveTime(TimeOfDay time) {
    arriveTime = time;
    _revalidateTime();
    notifyListeners();
  }

  bool _validate() {
    bool isValid = true;
    nameError = null;
    fromError = null;
    toError = null;
    timeError = null;

    if (nameController.text.trim().isEmpty) {
      nameError = 'Trip name is required';
      isValid = false;
    }

    if (fromPlace == null) {
      fromError = 'Please select a valid start location from the dropdown';
      isValid = false;
    }

    if (toPlace == null) {
      toError = 'Please select a valid destination from the dropdown';
      isValid = false;
    }

    _revalidateLocations();
    if (toError != null) isValid = false;

    _revalidateTime();
    if (timeError != null) isValid = false;

    notifyListeners();
    return isValid;
  }

  // --- RETURN PAYLOAD INSTEAD OF BOOL ---
  Future<Map<String, dynamic>?> submit() async {
    if (!_validate()) return null;

    isSubmitting = true;
    errorMessage = null;
    notifyListeners();

    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;

      final isEditing = existingTrip != null;
      final tripId = isEditing ? existingTrip!['id'] : const Uuid().v4();

      String formatTime(TimeOfDay t) {
        return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';
      }

      final departStr = formatTime(departTime);
      final arriveStr = formatTime(arriveTime);

      final days = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];
      final activeDaysMap = { for (var d in days) 'active_$d': false };

      int current = fromDay;
      while (true) {
        activeDaysMap['active_${days[current - 1]}'] = true;
        if (current == toDay) break;
        current++;
        if (current > 7) current = 1;
      }

      final payload = <String, dynamic>{
        'user_id': userId,
        'trip_name': nameController.text.trim(),
        ...activeDaysMap,
      };

      // Only attach Primary Key directly for NEW inserts
      if (!isEditing) {
        payload['id'] = tripId;
      }

      if (role == 'driver') {
        payload['depart_time'] = departStr;
        payload['arrival_time'] = arriveStr;
        payload['depart_name'] = fromPlace!.label;
        payload['arrival_name'] = toPlace!.label;
        payload['depart_lat'] = fromPlace!.latitude;
        payload['depart_lng'] = fromPlace!.longitude;
        payload['arrival_lat'] = toPlace!.latitude;
        payload['arrival_lng'] = toPlace!.longitude;
      } else {
        payload['desired_pickup_time'] = departStr;
        payload['desired_dropoff_time'] = arriveStr;
        payload['pickup_name'] = fromPlace!.label;
        payload['dropoff_name'] = toPlace!.label;
        payload['pickup_lat'] = fromPlace!.latitude;
        payload['pickup_lng'] = fromPlace!.longitude;
        payload['dropoff_lat'] = toPlace!.latitude;
        payload['dropoff_lng'] = toPlace!.longitude;
      }

      if (isEditing) {
        await _tripService.updateTrip(tripId, payload, role);
        payload['id'] = tripId; // <--- Re-inject the ID so the local state tracker can find it!
      } else {
        await _tripService.insertTrip(payload, role);
      }

      isSubmitting = false;
      notifyListeners();
      return payload; // Return the saved payload!

    } on PostgrestException catch (e) {
      isSubmitting = false;
      errorMessage = e.message;
      notifyListeners();
      return null;
    } catch (e) {
      isSubmitting = false;
      errorMessage = 'An error occurred. Please try again.';
      notifyListeners();
      return null;
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    fromController.dispose();
    toController.dispose();
    super.dispose();
  }
}