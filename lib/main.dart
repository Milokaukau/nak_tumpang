import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
//import 'package:nak_tumpang/seed_data.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase before the app starts
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const TumpangApp());
}

class TumpangApp extends StatelessWidget {
  const TumpangApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tumpang',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: Scaffold(
        appBar: AppBar(title: const Text('Firestore Reference Guide')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [

              // --- TEAM REFERENCE: HOW TO FETCH DATA ---
              ElevatedButton(
                onPressed: () async {
                  try {
                    print('⏳ Fetching data from Firestore...');

                    // 1. Fetch the collection ('users')
                    final snapshot = await FirebaseFirestore.instance
                        .collection('users') // Ensure this matches your exact collection name
                        .get();

                    if (snapshot.docs.isEmpty) {
                      print('⚠️ Collection is empty. Did you name it correctly?');
                      return;
                    }

                    // 2. Loop through the documents and parse the complex data
                    for (var doc in snapshot.docs) {
                      final data = doc.data();

                      print('\n--- FOUND USER: ${doc.id} ---');
                      print('Name: ${data['name']}');
                      print('Role: ${data['role']}');

                      // 3. How to read a simple nested Map (active_days)
                      final activeDays = data['active_days'] as Map<String, dynamic>?;
                      if (activeDays != null) {
                        print('Is active on Monday? ${activeDays['monday']}');
                      }

                      // 4. How to read a deeply nested Map (passenger_profile -> desired_pickup_location)
                      final passengerProfile = data['passenger_profile'] as Map<String, dynamic>?;
                      if (passengerProfile != null) {
                        print('Pickup Time: ${passengerProfile['desired_pickup_time']}');

                        final pickupLoc = passengerProfile['desired_pickup_location'] as Map<String, dynamic>?;
                        if (pickupLoc != null) {
                          print('Pickup Name: ${pickupLoc['name']}');
                          // Notice how these print as double/decimal values
                          print('Pickup Lat: ${pickupLoc['lat']}');
                          print('Pickup Lng: ${pickupLoc['lng']}');
                        }
                      }
                    }
                    print('\n✅ Data fetch complete!');
                  } catch (e) {
                    print('❌ ERROR: $e');
                  }
                },
                child: const Text('Fetch Firestore Data'),
              ),

              const SizedBox(height: 20),

              /*
              ElevatedButton(
                onPressed: () async {
                  await populateFirestore(); // Calls the script in seed_data.dart
                },
                child: const Text('Seed Database'),
              ),
              */

            ],
          ),
        ),
      ),
    );
  }
}