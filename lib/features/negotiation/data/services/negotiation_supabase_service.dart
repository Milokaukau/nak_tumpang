import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nak_tumpang/core/entities/tumpang_request.dart';

// Ensure the class name is NegotiationSupabaseService
class NegotiationSupabaseService {
  final SupabaseClient _supabase;

  NegotiationSupabaseService({SupabaseClient? supabase})
      : _supabase = supabase ?? Supabase.instance.client;

  final String _table = 'tumpang_request';

  Stream<TumpangRequest?> streamSingleRequest(String requestId) {
    return _supabase
        .from(_table)
        .stream(primaryKey: ['id'])
        .eq('id', requestId)
        .map((rows) {
      if (rows.isEmpty) return null;
      return TumpangRequest.fromJson(rows.first);
    });
  }

  Stream<List<TumpangRequest>> streamRequestsForDriver(String driverTripId) {
    return _supabase
        .from(_table)
        .stream(primaryKey: ['id'])
        .eq('driver_trip_id', driverTripId)
        .eq('status', 'negotiating')
        .map((rows) => rows.map((row) => TumpangRequest.fromJson(row)).toList());
  }

  Stream<List<TumpangRequest>> streamRequestsForPassenger(String passengerTripId) {
    return _supabase
        .from(_table)
        .stream(primaryKey: ['id'])
        .eq('passenger_trip_id', passengerTripId)
        .eq('status', 'negotiating')
        .map((rows) => rows.map((row) => TumpangRequest.fromJson(row)).toList());
  }

  Future<void> updateNegotiationField({
    required String requestId,
    required String fieldPrefix,
    dynamic value,
    double? lat,
    double? lng,
    required String requestedById,
    required bool isAccepted,
  }) async {
    final Map<String, dynamic> updates = {
      '${fieldPrefix}_requested_by': requestedById,
      '${fieldPrefix}_is_accepted': isAccepted,
    };

    if (fieldPrefix == 'pickup' || fieldPrefix == 'dropoff') {
      updates['${fieldPrefix}_name'] = value;
      if (lat != null) updates['${fieldPrefix}_lat'] = lat;
      if (lng != null) updates['${fieldPrefix}_lng'] = lng;
    } else {
      updates[fieldPrefix] = value;
    }

    await _supabase.from(_table).update(updates).eq('id', requestId);
  }

  Future<void> acceptNegotiationField({
    required String requestId,
    required String fieldPrefix,
  }) async {
    await _supabase
        .from(_table)
        .update({'${fieldPrefix}_is_accepted': true})
        .eq('id', requestId);
  }

  Future<void> rejectRequest(String requestId) async {
    await _supabase
        .from(_table)
        .update({'status': 'rejected'})
        .eq('id', requestId);
  }
}