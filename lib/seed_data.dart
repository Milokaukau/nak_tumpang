import 'package:cloud_firestore/cloud_firestore.dart';

Future<void> populateFirestore() async {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  final WriteBatch batch = firestore.batch();

  print('⏳ Starting database seeding for matching test cases...');

  // ==========================================
  // PASSENGERS (Swap these IDs in ViewModel to test)
  // ==========================================

  // Original Direct Match Passenger
  batch.set(firestore.collection('users').doc('usr_pass_9921'), _createPassenger(
      name: 'Chong Wei Min',
      pickLat: 3.2025, pickLng: 101.7154, pickName: 'PV13 Platinum Lake',
      dropLat: 3.2159, dropLng: 101.7261, dropName: 'TAR UMT Arena',
      time: '08:00 AM'
  ));

  // Direct 1: No drivers available (3 AM trip)
  batch.set(firestore.collection('users').doc('pass_direct_none'), _createPassenger(
      name: 'Night Owl',
      pickLat: 3.1589, pickLng: 101.7132, pickName: 'KLCC',
      dropLat: 2.9827, dropLng: 101.7902, dropName: 'Kajang',
      time: '03:00 AM'
  ));

// Mixed 1: Walk - Train - Walk (Lives 400m from KJ3 Wangsa Maju, going 300m from KJ10 KLCC)
  batch.set(firestore.collection('users').doc('pass_mix_wtw'), _createPassenger(
      name: 'Walker Train',
      pickLat: 3.2045, pickLng: 101.7310, pickName: 'Desa Setapak',
      dropLat: 3.1595, dropLng: 101.7140, dropName: 'Menara Maxis', // <--- Changed pickLng to dropLng
      time: '08:00 AM'
  ));

  // Mixed 2: Walk only (Pickup and Dropoff are 800m apart, both near same station)
  batch.set(firestore.collection('users').doc('pass_mix_walk'), _createPassenger(
      name: 'Short Distance Walker',
      pickLat: 3.2025, pickLng: 101.7154, pickName: 'PV13 Platinum Lake',
      dropLat: 3.2038, dropLng: 101.7219, dropName: 'Setapak Central',
      time: '08:00 AM'
  ));

  // Mixed 3: Walk - Train - Driver (Starts at KLCC, ends far from Phileo Damansara KG12)
  batch.set(firestore.collection('users').doc('pass_mix_wtd'), _createPassenger(
      name: 'Last Mile Needed',
      pickLat: 3.1595, pickLng: 101.7140, pickName: 'Menara Maxis',
      dropLat: 3.1650, dropLng: 101.6500, dropName: 'Solaris Mont Kiara',
      time: '08:00 AM'
  ));

  // Mixed 4: Driver - Train - Walk (Starts far from Gombak KJ1, ends at KLCC)
  batch.set(firestore.collection('users').doc('pass_mix_dtw'), _createPassenger(
      name: 'First Mile Needed',
      pickLat: 3.2500, pickLng: 101.7300, pickName: 'UIA Gombak',
      dropLat: 3.1595, dropLng: 101.7140, dropName: 'Menara Maxis',
      time: '08:00 AM'
  ));

  // Mixed 5: Driver - Train - Driver (Starts far from Gombak KJ1, ends far from Phileo KG12)
  batch.set(firestore.collection('users').doc('pass_mix_dtd'), _createPassenger(
      name: 'Full Transit User',
      pickLat: 3.2500, pickLng: 101.7300, pickName: 'UIA Gombak',
      dropLat: 3.1650, dropLng: 101.6500, dropName: 'Solaris Mont Kiara',
      time: '08:00 AM'
  ));

  // Mixed 6: Multi-line Train (KJ3 Wangsa Maju to KG18A Bukit Bintang)
  batch.set(firestore.collection('users').doc('pass_mix_multi'), _createPassenger(
      name: 'Line Switcher',
      pickLat: 3.2045, pickLng: 101.7310, pickName: 'Desa Setapak',
      dropLat: 3.1460, dropLng: 101.7115, dropName: 'Pavilion Bukit Bintang',
      time: '08:00 AM'
  ));


  // ==========================================
  // DRIVERS
  // ==========================================

  // Direct Match Driver (for PV13 to TARUMT)
  batch.set(firestore.collection('users').doc('usr_driv_1002'), _createDriver(
      name: 'Lim Wei Jie',
      startLat: 3.2005, startLng: 101.7160, startName: 'PV15 Condominium',
      endLat: 3.2155, endLng: 101.7265, endName: 'TAR UMT Main Gate',
      depart: '07:50 AM', arrival: '08:10 AM'
  ));

  // Direct Match Driver (Crossing through Setapak)
  batch.set(firestore.collection('users').doc('usr_driv_1007'), _createDriver(
      name: 'Aisyah Batrisyia',
      startLat: 3.2052, startLng: 101.7077, startName: 'Plaza Idaman',
      endLat: 3.2245, endLng: 101.7310, endName: 'KL East Mall',
      depart: '07:55 AM', arrival: '08:45 AM'
  ));

  // First-Mile Driver (For UIA Gombak to Gombak LRT KJ1)
  batch.set(firestore.collection('users').doc('driv_first_mile'), _createDriver(
      name: 'Sarah Lee',
      startLat: 3.2550, startLng: 101.7350, startName: 'UIA Gombak Hostels',
      endLat: 3.2317, endLng: 101.7244, endName: 'Gombak LRT',
      depart: '07:45 AM', arrival: '08:10 AM'
  ));

  // Last-Mile Driver (For Phileo Damansara KG12 to Mont Kiara)
  batch.set(firestore.collection('users').doc('driv_last_mile'), _createDriver(
      name: 'Muthu Kumar',
      startLat: 3.1298, startLng: 101.6424, startName: 'Phileo Damansara MRT',
      endLat: 3.1700, endLng: 101.6550, endName: 'Publika Mont Kiara',
      depart: '08:45 AM', arrival: '09:00 AM' // Departs later to account for train ride
  ));


  try {
    await batch.commit();
    print('✅ Database successfully seeded!');
  } catch (e) {
    print('❌ Error seeding database: $e');
  }
}

// Helper to generate passenger JSON
Map<String, dynamic> _createPassenger({
  required String name,
  required double pickLat, required double pickLng, required String pickName,
  required double dropLat, required double dropLng, required String dropName,
  required String time
}) {
  return {
    'name': name,
    'role': 'passenger',
    'active_days': {
      'monday': true, 'tuesday': true, 'wednesday': true,
      'thursday': true, 'friday': true, 'saturday': false, 'sunday': false
    },
    'passenger_profile': {
      'desired_pickup_time': time,
      'desired_pickup_location': {'lat': pickLat, 'lng': pickLng, 'name': pickName},
      'desired_dropoff_location': {'lat': dropLat, 'lng': dropLng, 'name': dropName}
    },
    'driver_profile': null,
  };
}

// Helper to generate driver JSON
Map<String, dynamic> _createDriver({
  required String name,
  required double startLat, required double startLng, required String startName,
  required double endLat, required double endLng, required String endName,
  required String depart, required String arrival
}) {
  return {
    'name': name,
    'role': 'driver',
    'active_days': {
      'monday': true, 'tuesday': true, 'wednesday': true,
      'thursday': true, 'friday': true, 'saturday': false, 'sunday': false
    },
    'passenger_profile': null,
    'driver_profile': {
      'earnings': 0.0,
      'depart_time': depart,
      'arrival_time': arrival,
      'start_location': {'lat': startLat, 'lng': startLng, 'name': startName},
      'end_location': {'lat': endLat, 'lng': endLng, 'name': endName}
    }
  };
}