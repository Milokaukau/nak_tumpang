import 'package:flutter/foundation.dart'; // Added for debugPrint
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // <--- Added Firestore import
import 'package:nak_tumpang/core/entities/tumpang_request.dart';
import 'package:nak_tumpang/features/negotiation/data/services/negotiation_service_remote.dart';

// =====================================================================
// 1. Core Providers
// =====================================================================

final negotiationServiceProvider = Provider<NegotiationServiceRemote>((ref) {
  return NegotiationServiceRemote();
});

final mockAuthUserProvider = Provider((ref) => (id: 'usr_driv_4412', role: 'driver'));

// =====================================================================
// 2. Real-Time Data Streams
// =====================================================================

final pendingRequestsStreamProvider = StreamProvider.autoDispose<List<TumpangRequest>>((ref) {
  final user = ref.watch(mockAuthUserProvider);
  final service = ref.watch(negotiationServiceProvider);

  if (user.role == 'driver') {
    return service.streamRequestsForDriver(user.id);
  } else {
    return service.streamRequestsForPassenger(user.id);
  }
});

/// Streams a single specific request to keep the negotiation room updated in real-time.
final singleRequestStreamProvider = StreamProvider.family.autoDispose<TumpangRequest?, String>((ref, requestId) {
  final service = ref.watch(negotiationServiceProvider);
  return service.streamSingleRequest(requestId);
});

// =====================================================================
// 3. Action Controller
// =====================================================================

final negotiationControllerProvider = Provider.autoDispose<NegotiationController>((ref) {
  final service = ref.watch(negotiationServiceProvider);
  final user = ref.watch(mockAuthUserProvider);
  return NegotiationController(service, user.id);
});

class NegotiationController {
  final NegotiationServiceRemote _service;
  final String _currentUserId;

  NegotiationController(this._service, this._currentUserId);

  Future<void> acceptTerm(String requestId, String fieldKey) async {
    try {
      await _service.acceptNegotiationField(
        requestId: requestId,
        fieldKey: fieldKey,
      );
    } catch (e) {
      debugPrint('Error accepting term: $e');
    }
  }

  Future<void> proposeNewTerm(String requestId, String fieldKey, dynamic newValue) async {
    try {
      await _service.updateNegotiationField(
        requestId: requestId,
        fieldKey: fieldKey,
        newValue: newValue,
        requestedById: _currentUserId,
        isAccepted: false,
      );
    } catch (e) {
      debugPrint('Error proposing term: $e');
    }
  }

  Future<void> rejectEntireRequest(String requestId) async {
    try {
      await _service.rejectRequest(requestId);
    } catch (e) {
      debugPrint('Error rejecting request: $e');
    }
  }

  Future<bool> finalizeAgreement(TumpangRequest request) async {
    bool allAccepted = request.fee.isAccepted &&
        request.pickupTime.isAccepted &&
        request.pickupLocation.isAccepted &&
        request.dropoffLocation.isAccepted &&
        request.subscriptionStartDate.isAccepted &&
        request.subscriptionEndDate.isAccepted;

    if (!allAccepted) {
      return false;
    }

    try {
      // await _service.createSubscriptionFromRequest(request);
      return true;
    } catch (e) {
      debugPrint('Error finalizing agreement: $e');
      return false;
    }
  }
}

// =====================================================================
// 4. User Profile Fetcher (ADDED THIS HERE!)
// =====================================================================

final userProfileProvider = FutureProvider.family<Map<String, dynamic>?, String>((ref, userId) async {
  try {
    final doc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
    if (doc.exists) {
      return doc.data();
    }
  } catch (e) {
    debugPrint('Error fetching user: $e');
  }
  return null;
});