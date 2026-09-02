import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nak_tumpang/core/entities/tumpang_request.dart';

class NegotiationSupabaseService {
  final SupabaseClient _supabase;

  NegotiationSupabaseService({SupabaseClient? supabase})
      : _supabase = supabase ?? Supabase.instance.client;

  final String _table = 'tumpang_request';

  Future<TumpangRequest?> fetchSingleRequest(String requestId) async {
    final response = await _supabase
        .from(_table)
        .select()
        .eq('id', requestId)
        .maybeSingle();

    if (response == null) return null;
    return TumpangRequest.fromJson(response);
  }

  Future<List<TumpangRequest>> fetchRequestsForDriver(String driverTripId) async {
    final List<dynamic> rows = await _supabase
        .from(_table)
        .select()
        .eq('driver_trip_id', driverTripId)
        .or('status.eq.pending,status.eq.negotiating');

    return rows.map((row) => TumpangRequest.fromJson(row)).toList();
  }

  Future<List<TumpangRequest>> fetchRequestsForPassenger(String passengerTripId) async {
    final List<dynamic> rows = await _supabase
        .from(_table)
        .select()
        .eq('passenger_trip_id', passengerTripId)
        .or('status.eq.pending,status.eq.negotiating');

    return rows.map((row) => TumpangRequest.fromJson(row)).toList();
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
    } else if (fieldPrefix == 'sub_start' || fieldPrefix == 'sub_end') {
      // DB column is sub_start_date / sub_end_date, but requested_by and
      // is_accepted columns use the shorter sub_start / sub_end prefix.
      updates['${fieldPrefix}_date'] = value;
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