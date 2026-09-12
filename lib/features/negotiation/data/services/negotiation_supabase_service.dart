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

  /// Creates a new tumpang_request representing an extension of an
  /// existing subscription. All fields are copied from the current
  /// subscription and marked already-accepted, EXCEPT the end date (and,
  /// for a 'renegotiate' extension, whichever other fields the caller
  /// passes as overrides) — those go in unaccepted, so they flow through
  /// the normal negotiation UI and require the driver's acceptance.
  ///
  /// This never touches tumpang_subscription directly - see
  /// [finalizeExtension] for what happens once this request is agreed.
  Future<String> createExtensionRequest({
    required Map<String, dynamic> subscription, // a tumpang_subscription row
    required String requestedById,
    required DateTime newEndDate,
    required String extensionType, // 'date_only' | 'renegotiate'
    String? overridePickupName,
    double? overridePickupLat,
    double? overridePickupLng,
    String? overrideDropoffName,
    double? overrideDropoffLat,
    double? overrideDropoffLng,
    String? overridePickupTime,
    double? overrideFee,
  }) async {
    final subscriptionId = subscription['id'] as String;
    final requestId = 'ext_${DateTime.now().millisecondsSinceEpoch}';
    final newEndDateStr = newEndDate.toIso8601String().split('T').first;

    final bool pickupChanged = overridePickupName != null;
    final bool dropoffChanged = overrideDropoffName != null;
    final bool timeChanged = overridePickupTime != null;
    final bool feeChanged = overrideFee != null;

    await _supabase.from(_table).insert({
      'id': requestId,
      'passenger_trip_id': subscription['passenger_trip_id'],
      'driver_trip_id': subscription['driver_trip_id'],
      'status': 'negotiating',

      'pickup_name': overridePickupName ?? subscription['pickup_location'],
      'pickup_lat': overridePickupLat ?? subscription['pickup_lat'],
      'pickup_lng': overridePickupLng ?? subscription['pickup_lng'],
      'pickup_requested_by': requestedById,
      'pickup_is_accepted': !pickupChanged,

      'dropoff_name': overrideDropoffName ?? subscription['dropoff_location'],
      'dropoff_lat': overrideDropoffLat ?? subscription['dropoff_lat'],
      'dropoff_lng': overrideDropoffLng ?? subscription['dropoff_lng'],
      'dropoff_requested_by': requestedById,
      'dropoff_is_accepted': !dropoffChanged,

      'pickup_time': overridePickupTime ?? subscription['pickup_time'],
      'pickup_time_requested_by': requestedById,
      'pickup_time_is_accepted': !timeChanged,

      'fee': overrideFee ?? subscription['fee'],
      'fee_requested_by': requestedById,
      'fee_is_accepted': !feeChanged,

      // Start date carries over unchanged (the subscription's original
      // start) and is pre-accepted; only the end date is actually new.
      'sub_start_date': subscription['subscription_start_date'],
      'sub_start_requested_by': requestedById,
      'sub_start_is_accepted': true,

      'sub_end_date': newEndDateStr,
      'sub_end_requested_by': requestedById,
      'sub_end_is_accepted': false,

      'is_extension': true,
      'extends_subscription_id': subscriptionId,
      'extension_type': extensionType,
    });

    return requestId;
  }

  /// Called once an extension request's [TumpangRequest.isFullyAgreed] is
  /// true (i.e. the driver has accepted). Applies the agreed terms to
  /// tumpang_subscription, then marks the extension request completed.
  ///
  /// - 'date_only': UPDATEs the existing subscription's end date directly.
  ///   No new subscription row, no new deposit - your existing invoice
  ///   generator naturally continues billing into the extended period
  ///   once subscription_end_date moves.
  /// - 'renegotiate': INSERTs a brand-new subscription row with the
  ///   agreed terms, and marks the OLD subscription row 'superseded'
  ///   rather than updating/deleting it — old data is preserved.
  ///
  /// Returns the id of the subscription now in effect (the same id for
  /// 'date_only', a new id for 'renegotiate').
  Future<String> finalizeExtension(String extensionRequestId, {double additionalDeposit = 0.0}) async {
    final request = await fetchSingleRequest(extensionRequestId);
    if (request == null) {
      throw StateError('Extension request $extensionRequestId not found.');
    }
    if (!request.isExtension || request.extendsSubscriptionId == null) {
      throw StateError('Request $extensionRequestId is not an extension.');
    }
    if (!request.isFullyAgreed) {
      throw StateError('Extension request $extensionRequestId is not fully agreed yet.');
    }

    final oldSubscriptionId = request.extendsSubscriptionId!;
    final oldSub = await _supabase
        .from('tumpang_subscription')
        .select()
        .eq('id', oldSubscriptionId)
        .maybeSingle();

    if (oldSub == null) {
      throw StateError('Original subscription $oldSubscriptionId not found.');
    }

    // Calculate total updated deposit
    final currentDeposit = double.tryParse(oldSub['deposit']?.toString() ?? '') ?? 0.0;
    final newTotalDeposit = currentDeposit + additionalDeposit;
    String activeSubscriptionId = oldSubscriptionId;

    if (request.extensionType == 'renegotiate') {
      final newSubscriptionId = 'sub_${DateTime.now().millisecondsSinceEpoch}';
      activeSubscriptionId = newSubscriptionId;

      await _supabase.from('tumpang_subscription').insert({
        'id': newSubscriptionId,
        'passenger_trip_id': oldSub['passenger_trip_id'],
        'driver_trip_id': oldSub['driver_trip_id'],
        'pickup_lat': request.pickupLocation.lat,
        'pickup_lng': request.pickupLocation.lng,
        'pickup_location': request.pickupLocation.name,
        'dropoff_lat': request.dropoffLocation.lat,
        'dropoff_lng': request.dropoffLocation.lng,
        'dropoff_location': request.dropoffLocation.name,
        'pickup_time': request.pickupTime.value,
        'fee': request.fee.value,
        'deposit': newTotalDeposit, // Updated Deposit
        'deposit_refunded': false,
        'subscription_start_date': request.subscriptionStartDate.value,
        'subscription_end_date': request.subscriptionEndDate.value,
        'status': 'active',
      });

      await _supabase
          .from('tumpang_subscription')
          .update({'status': 'superseded'})
          .eq('id', oldSubscriptionId);

    } else {
      // date_only
      await _supabase.from('tumpang_subscription').update({
        'subscription_end_date': request.subscriptionEndDate.value,
        'deposit': newTotalDeposit, // Updated Deposit
      }).eq('id', oldSubscriptionId);

      await _supabase
          .from(_table)
          .update({'sub_end_date': request.subscriptionEndDate.value})
          .eq('subscription_id', oldSubscriptionId)
          .neq('id', extensionRequestId);
    }

    // Mark request completed
    await _supabase.from(_table).update({
      'status': 'completed',
      'subscription_id': activeSubscriptionId,
    }).eq('id', extensionRequestId);

    // Create payment record for the additional deposit collected
    if (additionalDeposit > 0) {
      final paidAt = DateTime.now();
      final paymentId = 'pay_${paidAt.millisecondsSinceEpoch}_extdep';
      await _supabase.from('payments').insert({
        'id': paymentId,
        'tumpang_subscription_id': activeSubscriptionId,
        'month': paidAt.month,
        'year': paidAt.year,
        'due_date': paidAt.toIso8601String(),
        'paid_at': paidAt.toIso8601String(),
        'amount': additionalDeposit,
      });
    }

    return activeSubscriptionId;
  }


}