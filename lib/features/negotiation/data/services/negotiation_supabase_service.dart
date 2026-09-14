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

  Future<void> createSubscriptionAfterDeposit({
    required TumpangRequest request,
    required double deposit,
  }) async {
    final startDate = DateTime.parse(request.subscriptionStartDate.value);
    final endDate = DateTime.tryParse(request.subscriptionEndDate.value) ?? startDate;
    final subscriptionId = 'sub_${DateTime.now().millisecondsSinceEpoch}';

    await _supabase.from('tumpang_subscription').insert({
      'id': subscriptionId,
      'passenger_trip_id': request.passengerTripId,
      'driver_trip_id': request.driverTripId,
      'pickup_lat': request.pickupLocation.lat,
      'pickup_lng': request.pickupLocation.lng,
      'pickup_location': request.pickupLocation.name,
      'dropoff_lat': request.dropoffLocation.lat,
      'dropoff_lng': request.dropoffLocation.lng,
      'dropoff_location': request.dropoffLocation.name,
      'pickup_time': request.pickupTime.value,
      'fee': request.fee.value,
      'deposit': deposit,
      'deposit_refunded': false,
      'subscription_start_date': startDate.toIso8601String().split('T').first,
      'subscription_end_date': endDate.toIso8601String().split('T').first,
      'status': 'active',
    });

    final paidAt = DateTime.now();
    await _supabase.from('payments').insert({
      'id': 'pay_${paidAt.millisecondsSinceEpoch}',
      'tumpang_subscription_id': subscriptionId,
      'month': paidAt.month,
      'year': paidAt.year,
      'due_date': paidAt.toIso8601String(),
      'paid_at': paidAt.toIso8601String(),
      'amount': deposit,
    });

    await _supabase
        .from(_table)
        .update({'status': 'completed', 'subscription_id': subscriptionId})
        .eq('id', request.id);
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

  Future<String> finalizeExtension(String extensionRequestId, {double additionalDeposit = 0.0}) async {
    final request = await fetchSingleRequest(extensionRequestId);

    if (request == null) {
      throw StateError('Extension request $extensionRequestId not found.');
    }

    // IDEMPOTENCY GUARD: Prevent duplicate rows on retry
    if (request.status == 'completed' && request.subscriptionId != null) {
      return request.subscriptionId!;
    }

    if (!request.isExtension || request.extendsSubscriptionId == null) {
      throw StateError('Request $extensionRequestId is not an extension.');
    }
    if (!request.isFullyAgreed) {
      throw StateError('Extension request $extensionRequestId is not fully agreed yet.');
    }

    // VALIDATION: Ensure the extension end date has not expired relative to today before writing
    final extensionEndDate = DateTime.tryParse(request.subscriptionEndDate.value);
    final today = DateTime.now();
    final todayDateOnly = DateTime(today.year, today.month, today.day);

    if (extensionEndDate == null || extensionEndDate.isBefore(todayDateOnly)) {
      throw StateError('Extension request $extensionRequestId has expired.');
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

    final newSubscriptionId = 'sub_${DateTime.now().millisecondsSinceEpoch}';
    final todayStr = todayDateOnly.toIso8601String().split('T').first;
    final nowIso = today.toIso8601String();

    // 1. ALWAYS create a brand new subscription row
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
      'deposit': additionalDeposit, // Fresh deposit only
      'deposit_refunded': false,
      'subscription_start_date': todayStr,
      'subscription_end_date': request.subscriptionEndDate.value,
      'status': 'active',
    });

    // 2. Shut down the old subscription safely
    final oldEndDate = DateTime.tryParse(oldSub['subscription_end_date']?.toString() ?? '');
    final isOldEndInFuture = oldEndDate != null && oldEndDate.isAfter(today);

    final updatePayload = {
      'status': 'inactive',
      'ended_by': 'system', // Satisfies DB constraint
      'ended_at': nowIso,   // Satisfies DB constraint
      'deposit_refunded': false,
    };

    if (isOldEndInFuture) {
      updatePayload['subscription_end_date'] = todayStr;
    }

    await _supabase
        .from('tumpang_subscription')
        .update(updatePayload)
        .eq('id', oldSubscriptionId);

    // 3. Mark request completed
    await _supabase.from(_table).update({
      'status': 'completed',
      'subscription_id': newSubscriptionId,
    }).eq('id', extensionRequestId);

    // 4. Save the fresh payment
    if (additionalDeposit > 0) {
      final paymentId = 'pay_${DateTime.now().millisecondsSinceEpoch}_extdep';
      await _supabase.from('payments').insert({
        'id': paymentId,
        'tumpang_subscription_id': newSubscriptionId,
        'month': today.month,
        'year': today.year,
        'due_date': nowIso,
        'paid_at': nowIso,
        'amount': additionalDeposit,
      });
    }

    return newSubscriptionId;
  }
}
