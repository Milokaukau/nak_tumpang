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
      // 'sub_start' / 'sub_end' no longer go through here individually -
      // see proposeTumpangDates() below.
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

  /// Atomically proposes both the Tumpang start and end date.
  ///
  /// This is a SINGLE `.update()` call setting both `sub_start_date` and
  /// `sub_end_date` (and both requested_by / is_accepted columns) in one
  /// map. PostgREST turns that into ONE SQL `UPDATE` statement against one
  /// row - a single statement is atomic by itself in Postgres, so there is
  /// no window where only one of the two dates has changed. This replaces
  /// the old pattern of two separate `updateNegotiationField()` calls
  /// (two HTTP requests, two independent SQL statements), which is what
  /// let the row end up with sub_start_date changed but sub_end_date
  /// stale if the second call failed or was interrupted.
  ///
  /// [startDate] / [endDate] are "YYYY-MM-DD" strings, matching what the
  /// date picker already produces - no RPC / server-side function needed.
  Future<void> proposeTumpangDates({
    required String requestId,
    required String startDate,
    required String endDate,
    required String requestedById,
  }) async {
    await _supabase.from(_table).update({
      'sub_start_date': startDate,
      'sub_end_date': endDate,
      'sub_start_requested_by': requestedById,
      'sub_end_requested_by': requestedById,
      'sub_start_is_accepted': false,
      'sub_end_is_accepted': false,
    }).eq('id', requestId);
  }

  /// Atomically accepts both the Tumpang start and end date - same
  /// single-statement reasoning as [proposeTumpangDates].
  Future<void> acceptTumpangDates({required String requestId}) async {
    await _supabase.from(_table).update({
      'sub_start_is_accepted': true,
      'sub_end_is_accepted': true,
    }).eq('id', requestId);
  }

  Future<void> rejectRequest(String requestId) async {
    await _supabase
        .from(_table)
        .update({'status': 'rejected'})
        .eq('id', requestId);
  }
}
