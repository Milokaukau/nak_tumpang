import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class HomeViewModel extends ChangeNotifier {
  // 1. Filter State (Tracks the exact string now)
  String selectedFilter = 'Direct';

  // 2. Mock Passenger State
  Map<String, dynamic>? currentPassenger;
  bool isLoading = true;

  // Change the filter and update the UI
  void setFilter(String option) {
    selectedFilter = option;
    notifyListeners();
  }

  // Fetch the mock passenger since Auth is not ready
  Future<void> fetchMockPassenger() async {
    isLoading = true;
    notifyListeners();

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc('usr_pass_9921')
          .get();

      if (doc.exists) {
        currentPassenger = doc.data();
        currentPassenger?['id'] = doc.id;
        print('✅ Mock Passenger Loaded: ${currentPassenger?['name']}');
      }
    } catch (e) {
      print('❌ Error fetching mock passenger: $e');
    }

    isLoading = false;
    notifyListeners();
  }
}