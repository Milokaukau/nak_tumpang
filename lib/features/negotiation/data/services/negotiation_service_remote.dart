import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nak_tumpang/core/entities/tumpang_request.dart';

class NegotiationServiceRemote {
  final FirebaseFirestore _firestore;

  // Dependency injection for testability, defaults to the standard instance
  NegotiationServiceRemote({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final String _collectionPath = 'tumpang_request';

  /// Streams real-time updates for a Driver's pending requests
  Stream<List<TumpangRequest>> streamRequestsForDriver(String driverId) {
    return _firestore
        .collection(_collectionPath)
        .where('driver_id', isEqualTo: driverId)
        .where('status', isEqualTo: 'negotiating')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return TumpangRequest.fromJson(doc.id, doc.data());
      }).toList();
    });
  }

  /// Streams real-time updates for a Passenger's pending requests
  Stream<List<TumpangRequest>> streamRequestsForPassenger(String passengerId) {
    return _firestore
        .collection(_collectionPath)
        .where('passenger_id', isEqualTo: passengerId)
        .where('status', isEqualTo: 'negotiating')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return TumpangRequest.fromJson(doc.id, doc.data());
      }).toList();
    });
  }

  /// Updates a specific field during negotiation (e.g., counter-offering a fee)
  /// [fieldKey] should match the Firestore map key (e.g., 'fee', 'pickup_time')
  Future<void> updateNegotiationField({
    required String requestId,
    required String fieldKey,
    required dynamic newValue,
    required String requestedById,
    required bool isAccepted,
  }) async {
    await _firestore.collection(_collectionPath).doc(requestId).update({
      fieldKey: {
        'value': newValue,
        'requested_by': requestedById,
        'is_accepted': isAccepted,
      }
    });
  }

  /// Accepts a specific field without changing its value
  Future<void> acceptNegotiationField({
    required String requestId,
    required String fieldKey,
  }) async {
    await _firestore.collection(_collectionPath).doc(requestId).update({
      '$fieldKey.is_accepted': true,
    });
  }

  /// Rejects the entire tumpang request
  Future<void> rejectRequest(String requestId) async {
    await _firestore.collection(_collectionPath).doc(requestId).update({
      'status': 'rejected',
    });
  }
}