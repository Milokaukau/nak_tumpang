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

  Future<String> createDepositPaymentIntent({
    required double amount,
    required String requestId,
  }) async {
    final response = await _supabase.functions.invoke(
      'create-payment-intent',
      body: {
        'amount': amount,
        'currency': 'myr',
        'description': 'Nak Tumpang deposit for request $requestId',
      },
    );
    if (response.status != 200 || response.data == null) {
      final error = response.data is Map ? response.data['error'] : null;
      throw StateError(error?.toString() ?? 'Failed to create PaymentIntent');
    }
    final clientSecret = (response.data as Map)['client_secret']?.toString();
    if (clientSecret == null || clientSecret.isEmpty) {
      throw StateError('No client_secret returned from server');
    }
    return clientSecret;
  }

  /// Finalizes a brand-new subscription after a successful deposit payment.
  ///
  /// All multi-table writes (subscription insert, payment insert, request
  /// status update) now happen inside the `finalize_tumpang_payment` Postgres
  /// function, in a single atomic transaction. `paymentIntentId` is used
  /// server-side as an idempotency key: if the app retries this call (e.g.
  /// after a crash or network drop) with the same Stripe PaymentIntent id,
  /// the RPC detects the existing `payments` row and returns the already-
  /// created subscription id instead of writing duplicate rows.
  Future<String> createSubscriptionAfterDeposit({
    required TumpangRequest request,
    required double deposit,
    required String paymentIntentId,
  }) async {
    final response = await _supabase.rpc(
      'finalize_tumpang_payment',
      params: {
        'p_request_id': request.id,
        'p_payment_intent_id': paymentIntentId,
        'p_deposit': deposit,
      },
    );

    final subscriptionId = response?.toString();
    if (subscriptionId == null || subscriptionId.isEmpty) {
      throw StateError('finalize_tumpang_payment did not return a subscription id');
    }
    return subscriptionId;
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

  Future<String> createExtensionRequest({
    required Map<String, dynamic> subscription,
    required String requestedById,
    required DateTime newEndDate,
    required String extensionType,
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

    final todayStr = DateTime.now().toIso8601String().split('T').first;

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

      'sub_start_date': todayStr,
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

  /// Finalizes an extension after a successful additional-deposit payment.
  ///
  /// As with [createSubscriptionAfterDeposit], all writes (new subscription
  /// insert, old subscription shutdown, request completion, payment insert)
  /// now happen atomically inside `finalize_tumpang_payment`, keyed on
  /// `paymentIntentId` for idempotent retries. The client-side
  /// isFullyAgreed / isExtension / expiry validation that used to live here
  /// should be re-checked server-side inside the RPC (or kept here as a
  /// pre-flight check) since this method no longer performs those reads
  /// itself before writing.
  Future<String> finalizeExtension(
      String extensionRequestId, {
        double additionalDeposit = 0.0,
        required String paymentIntentId,
      }) async {
    final response = await _supabase.rpc(
      'finalize_tumpang_payment',
      params: {
        'p_request_id': extensionRequestId,
        'p_payment_intent_id': paymentIntentId,
        'p_deposit': additionalDeposit,
      },
    );

    final subscriptionId = response?.toString();
    if (subscriptionId == null || subscriptionId.isEmpty) {
      throw StateError('finalize_tumpang_payment did not return a subscription id');
    }
    return subscriptionId;
  }
}
