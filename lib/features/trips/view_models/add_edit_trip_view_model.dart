import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:nak_tumpang/core/entities/geocoded_place.dart';
import 'package:nak_tumpang/features/trips/data/services/trip_supabase_service.dart';

class AddEditTripViewModel extends ChangeNotifier {
  final TripSupabaseService _tripService = TripSupabaseService();
  final String role;

  AddEditTripViewModel(this.role);

  final nameController = TextEditingController();
  final fromController = TextEditingController();
  final toController = TextEditingController();

  GeocodedPlace? fromPlace;
  GeocodedPlace? toPlace;

  int fromDay = 1; // Monday
  int toDay = 5;   // Friday

  TimeOfDay departTime = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay arriveTime = const TimeOfDay(hour: 9, minute: 0);

  bool isSubmitting = false;
  String? errorMessage;

  String? nameError;
  String? fromError;
  String? toError;
  String? timeError;
  String? dayError;

  int _minutesOf(TimeOfDay t) => t.hour * 60 + t.minute;

  void setFromPlace(GeocodedPlace place) {
    fromPlace = place;
    fromError = null;
    notifyListeners();
  }

  void clearFromPlace() {
    if (fromPlace == null) return;
    fromPlace = null;
    notifyListeners();
  }

  void setToPlace(GeocodedPlace place) {
    toPlace = place;
    toError = null;
    notifyListeners();
  }

  void clearToPlace() {
    if (toPlace == null) return;
    toPlace = null;
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
    notifyListeners();
  }

  void setArriveTime(TimeOfDay time) {
    arriveTime = time;
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

    if (_minutesOf(departTime) == _minutesOf(arriveTime)) {
      timeError = 'Depart and arrival time cannot be exactly the same';
      isValid = false;
    }

    notifyListeners();
    return isValid;
  }

  Future<bool> submit() async {
    if (!_validate()) return false;

    isSubmitting = true;
    errorMessage = null;
    notifyListeners();

    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;
      final tripId = const Uuid().v4();

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
        'id': tripId,
        'user_id': userId,
        'trip_name': nameController.text.trim(),
        ...activeDaysMap,
      };

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

      await _tripService.insertTrip(payload, role);

      isSubmitting = false;
      notifyListeners();
      return true;

    } on PostgrestException catch (e) {
      isSubmitting = false;
      errorMessage = e.message;
      notifyListeners();
      return false;
    } catch (e) {
      isSubmitting = false;
      errorMessage = 'An error occurred. Please try again.';
      notifyListeners();
      return false;
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