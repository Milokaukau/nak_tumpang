import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:nak_tumpang/core/entities/geocoded_place.dart';

class PostSignupDriverViewModel extends ChangeNotifier {
  final fromController = TextEditingController();
  final toController = TextEditingController();

  // set when user selects a geocoding suggestion
  GeocodedPlace? fromPlace;
  GeocodedPlace? toPlace;
  String? fromError;
  String? toError;

  int fromDay = DateTime.monday;
  int toDay = DateTime.friday;

  TimeOfDay departTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay arriveTime = const TimeOfDay(hour: 10, minute: 0);

  bool isSubmitting = false;
  String? errorMessage;
  String? timeError;
  String? dayError;

  // only shows error after they tried to submit once
  bool _autoValidateTime = false;

  int _minutesOf(TimeOfDay t) => t.hour * 60 + t.minute;

  void _revalidateDays() {
    if (!_autoValidateTime) return;
    dayError = fromDay > toDay ? 'Must be later than starting day' : null;
  }

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
    _revalidateDays();
    notifyListeners();
  }

  void setToDay(int day) {
    toDay = day;
    _revalidateDays();
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

  @override
  void dispose() {
    fromController.dispose();
    toController.dispose();
    super.dispose();
  }

  Map<String, bool> _activeDaysMap() {
    final active = <int>{};
    var day = fromDay;
    while (true) {
      active.add(day);
      if (day == toDay) break;
      day = day == DateTime.sunday ? DateTime.monday : day + 1;
    }
    return {
      'active_monday': active.contains(DateTime.monday),
      'active_tuesday': active.contains(DateTime.tuesday),
      'active_wednesday': active.contains(DateTime.wednesday),
      'active_thursday': active.contains(DateTime.thursday),
      'active_friday': active.contains(DateTime.friday),
      'active_saturday': active.contains(DateTime.saturday),
      'active_sunday': active.contains(DateTime.sunday),
    };
  }

  String _shortLabel(String label) => label.split(',').first.trim();

  String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

  Future<bool> submit() async {
    _autoValidateTime = true;
    fromError = fromPlace == null ? 'Please pick a location' : null;
    toError = toPlace == null ? 'Please pick a location' : null;
    _revalidateDays();
    notifyListeners();
    if (fromError != null || toError != null || timeError != null || dayError != null) return false;

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      errorMessage = 'Not signed in.';
      notifyListeners();
      return false;
    }

    isSubmitting = true;
    errorMessage = null;
    notifyListeners();

    try {
      final tripId = const Uuid().v4();
      final tripName = '${_shortLabel(fromPlace!.label)} → ${_shortLabel(toPlace!.label)}';

      await Supabase.instance.client.from('driver_trips').insert({
        'id': tripId,
        'user_id': userId,
        'trip_name': tripName,
        'depart_time': _formatTime(departTime),
        'arrival_time': _formatTime(arriveTime),
        'depart_lat': fromPlace!.latitude,
        'depart_lng': fromPlace!.longitude,
        'depart_name': fromPlace!.label,
        'arrival_lat': toPlace!.latitude,
        'arrival_lng': toPlace!.longitude,
        'arrival_name': toPlace!.label,
        ..._activeDaysMap(),
      });

      return true;
    } on PostgrestException catch (e) {
      errorMessage = e.message;
      return false;
    } catch (e) {
      errorMessage = 'Could not save your route. Please try again.';
      return false;
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
  }
}