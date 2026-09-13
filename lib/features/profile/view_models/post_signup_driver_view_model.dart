import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:nak_tumpang/core/entities/geocoded_place.dart';

/// Collects a driver's route/schedule — offered right after signup, if
/// they choose "Add trip" on the get-started dialog. The driver's
/// account (`users` + `driver_profiles`) already exists by the time
/// this screen is reached (RegisterViewModel writes it immediately,
/// same as passengers), so [submit] only ever needs to write a
/// `driver_trips` row. There's currently no way to reach this screen
/// again later (e.g. choosing "Later" here means no route until one is
/// added some other way) — if that's needed, it'll need its own entry
/// point elsewhere.
class PostSignupDriverViewModel extends ChangeNotifier {
  PostSignupDriverViewModel({required this.userId});

  final String userId;

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

  // only shows error after they tried to submit once
  bool _autoValidateTime = false;

  int _minutesOf(TimeOfDay t) => t.hour * 60 + t.minute;

  /// Days can now wrap across the week boundary (e.g. Friday -> Monday,
  /// for a weekend-crossing commute) — [_activeDaysMap] below already
  /// walks forward with wraparound, so there's nothing to block here
  /// anymore. Kept as a preview instead of a hard error: a wraparound
  /// range is easy to select by accident (picking the wrong "from" day),
  /// so rather than forbidding it outright, the screen shows exactly
  /// which days it resolves to and lets the driver visually confirm
  /// that's actually what they meant before submitting.
  List<String> get activeDaysPreview {
    const names = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final active = _activeDaysSet();
    return [
      for (var d = DateTime.monday; d <= DateTime.sunday; d++)
        if (active.contains(d)) names[d],
    ];
  }

  void _revalidateTime() {
    if (!_autoValidateTime) return;
    // Same-day trip only — depart_time/arrival_time are bare TIME values
    // with no date attached, so there's no way to record "arrives the
    // next day". Equal or earlier arrival is therefore always either a
    // mistake or something this schema can't represent, never a
    // legitimate multi-day trip.
    timeError = _minutesOf(arriveTime) <= _minutesOf(departTime)
        ? 'Arrival time must be after departure time'
        : null;
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

  @override
  void dispose() {
    fromController.dispose();
    toController.dispose();
    super.dispose();
  }

  /// Walks from [fromDay] to [toDay] inclusive, wrapping past Sunday
  /// back to Monday if [toDay] comes "before" [fromDay] in the week —
  /// e.g. Friday -> Monday resolves to {Fri, Sat, Sun, Mon}. Shared by
  /// [_activeDaysMap] (what gets written to the DB) and
  /// [activeDaysPreview] (what the driver sees before submitting), so
  /// the two can never disagree about which days a range covers.
  Set<int> _activeDaysSet() {
    final active = <int>{};
    var day = fromDay;
    while (true) {
      active.add(day);
      if (day == toDay) break;
      day = day == DateTime.sunday ? DateTime.monday : day + 1;
    }
    return active;
  }

  Map<String, bool> _activeDaysMap() {
    final active = _activeDaysSet();
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
    // Guards against a second call landing while one is already in
    // flight (e.g. a double-tap before the UI rebuilds with isSubmitting
    // disabling the button) — don't rely on the button's disabled state
    // alone.
    if (isSubmitting) return false;

    _autoValidateTime = true;
    fromError = fromPlace == null ? 'Please pick a location' : null;
    toError = toPlace == null ? 'Please pick a location' : null;
    if (fromError == null &&
        toError == null &&
        fromPlace!.latitude == toPlace!.latitude &&
        fromPlace!.longitude == toPlace!.longitude) {
      toError = "Pickup and drop-off can't be the same location";
    }
    _revalidateTime();
    notifyListeners();
    if (fromError != null || toError != null || timeError != null) return false;

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
      // Generic message instead of e.message — don't leak raw
      // constraint/column details from the DB to the driver.
      errorMessage = 'Could not save your route. Please try again.';
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