import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nak_tumpang/core/entities/tumpang_request.dart';
import 'package:nak_tumpang/features/negotiation/data/services/negotiation_service_remote.dart';

class NegotiationViewModel extends ChangeNotifier {
  final NegotiationServiceRemote _service = NegotiationServiceRemote();

  // MOCK AUTH (Replace with your actual AuthProvider later)
  final String currentUserId = 'usr_driv_4412';
  final String currentUserRole = 'driver';

  final Map<String, Map<String, dynamic>> _userCache = {};

  // Real-Time Data Streams
  Stream<List<TumpangRequest>> get pendingRequestsStream {
    if (currentUserRole == 'driver') {
      return _service.streamRequestsForDriver(currentUserId);
    } else {
      return _service.streamRequestsForPassenger(currentUserId);
    }
  }

  Stream<TumpangRequest?> singleRequestStream(String requestId) {
    return _service.streamSingleRequest(requestId);
  }

  // Caches profile fetches so we don't spam Firestore
  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    if (_userCache.containsKey(userId)) return _userCache[userId];
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
      if (doc.exists && doc.data() != null) {
        _userCache[userId] = doc.data()!;
        return _userCache[userId];
      }
    } catch (e) {
      debugPrint('Error fetching user: $e');
    }
    return null;
  }

  // Action Controllers
  Future<void> acceptTerm(String requestId, String fieldKey) async {
    await _service.acceptNegotiationField(requestId: requestId, fieldKey: fieldKey);
  }

  Future<void> proposeNewTerm(String requestId, String fieldKey, dynamic newValue) async {
    await _service.updateNegotiationField(
      requestId: requestId,
      fieldKey: fieldKey,
      newValue: newValue,
      requestedById: currentUserId,
      isAccepted: false,
    );
  }

  Future<void> rejectEntireRequest(String requestId) async {
    await _service.rejectRequest(requestId);
  }

  Future<bool> finalizeAgreement(TumpangRequest request) async {
    bool allAccepted = request.fee.isAccepted &&
        request.pickupTime.isAccepted &&
        request.pickupLocation.isAccepted &&
        request.dropoffLocation.isAccepted &&
        request.subscriptionStartDate.isAccepted &&
        request.subscriptionEndDate.isAccepted;

    if (!allAccepted) return false;
    return true;
  }
}