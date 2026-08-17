import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nak_tumpang/core/entities/tumpang_request.dart';
import 'package:nak_tumpang/features/negotiation/data/services/negotiation_service_remote.dart';

// =====================================================================
// 1. Core Providers
// =====================================================================

/// Provides the remote service instance
final negotiationServiceProvider = Provider<NegotiationServiceRemote>((ref) {
  return NegotiationServiceRemote();
});

// *NOTE: Replace this with your actual Auth Provider that holds the logged-in user's state.
// For this example, we assume it provides an object with 'id' and 'role' (driver/passenger).
final mockAuthUserProvider = Provider((ref) => (id: 'usr_driv_4412', role: 'driver'));

// =====================================================================
// 2. Real-Time Data Streams
// =====================================================================

/// Automatically fetches pending requests based on the current user's role.
/// Used by: RequestListScreen
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
/// Used by: ViewRequestScreen
final singleRequestStreamProvider = StreamProvider.family.autoDispose<TumpangRequest?, String>((ref, requestId) {
  final requestsAsync = ref.watch(pendingRequestsStreamProvider);

  return requestsAsync.whenData((requests) {
    try {
      return requests.firstWhere((req) => req.id == requestId);
    } catch (_) {
      return null; // Request not found or removed
    }
  });
});

// =====================================================================
// 3. Action Controller
// =====================================================================

/// Handles user actions inside the ViewRequestScreen
final negotiationControllerProvider = Provider.autoDispose<NegotiationController>((ref) {
  final service = ref.watch(negotiationServiceProvider);
  final user = ref.watch(mockAuthUserProvider);
  return NegotiationController(service, user.id);
});

class NegotiationController {
  final NegotiationServiceRemote _service;
  final String _currentUserId;

  NegotiationController(this._service, this._currentUserId);

  /// Called when the user clicks "Accept" on a specific row (e.g., Time or Fee)
  Future<void> acceptTerm(String requestId, String fieldKey) async {
    try {
      await _service.acceptNegotiationField(
        requestId: requestId,
        fieldKey: fieldKey,
      );
    } catch (e) {
      // Handle error (e.g., log it, or you could use a StateNotifier to push error states to UI)
      print('Error accepting term: $e');
    }
  }

  /// Called when the user submits a new value from the "Propose another" bottom sheet
  Future<void> proposeNewTerm(String requestId, String fieldKey, dynamic newValue) async {
    try {
      await _service.updateNegotiationField(
        requestId: requestId,
        fieldKey: fieldKey,
        newValue: newValue,
        requestedById: _currentUserId, // I am now the requester of this new term
        isAccepted: false, // The other party now needs to accept it
      );
    } catch (e) {
      print('Error proposing term: $e');
    }
  }

  /// Called when the user clicks the global "Reject" button at the bottom of the screen
  Future<void> rejectEntireRequest(String requestId) async {
    try {
      await _service.rejectRequest(requestId);
    } catch (e) {
      print('Error rejecting request: $e');
    }
  }

  /// Called when the user clicks the global "Accept" button
  /// Validates if all terms are accepted before proceeding to generate a subscription.
  Future<bool> finalizeAgreement(TumpangRequest request) async {
    // Check if both parties have agreed to all individual terms
    bool allAccepted = request.fee.isAccepted &&
        request.pickupTime.isAccepted &&
        request.pickupLocation.isAccepted &&
        request.dropoffLocation.isAccepted &&
        request.subscriptionStartDate.isAccepted &&
        request.subscriptionEndDate.isAccepted;

    if (!allAccepted) {
      return false; // UI should show a SnackBar saying "All terms must be accepted first"
    }

    try {
      // TODO: Call a service method to convert this tumpang_request into a tumpang_subscription
      // await _service.createSubscriptionFromRequest(request);
      return true; // Success
    } catch (e) {
      print('Error finalizing agreement: $e');
      return false;
    }
  }
}