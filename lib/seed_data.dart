import 'package:cloud_firestore/cloud_firestore.dart';

Future<void> populateFirestore() async {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  final WriteBatch batch = firestore.batch();

  print('⏳ Starting database seeding...');

  // 1. Create Users
  final passengerRef = firestore.collection('users').doc('usr_pass_9921');
  batch.set(passengerRef, {
    'name': 'Chong Wei Min',
    'email': 'weimin.chong@student.tarumt.edu.my',
    'phone': '+60123456789',
    'reward_points_bal': 123,
    'role': 'passenger',
    'active_days': {
      'monday': true, 'tuesday': true, 'wednesday': true,
      'thursday': true, 'friday': true, 'saturday': false, 'sunday': false
    },
    'passenger_profile': {
      'desired_pickup_time': '08:00 AM',
      'desired_pickup_location': {
        'lat': 3.2025, 'lng': 101.7154, 'name': 'PV13 Platinum Lake Condominium, Setapak'
      },
      'desired_dropoff_location': {
        'lat': 3.2159, 'lng': 101.7261, 'name': 'TAR UMT Arena, Kuala Lumpur'
      }
    },
    'driver_profile': null, // Edge case: strictly passenger
  });

  final driverRef = firestore.collection('users').doc('usr_driv_4412');
  batch.set(driverRef, {
    'name': 'Ahmad Rayyan',
    'email': 'rayyan.ahmad@gmail.com',
    'phone': '+60198765432',
    'reward_points_bal': 50,
    'role': 'driver',
    'active_days': {
      'monday': true, 'tuesday': false, 'wednesday': true, // Edge case: irregular days
      'thursday': false, 'friday': true, 'saturday': false, 'sunday': false
    },
    'passenger_profile': null,
    'driver_profile': {
      'earnings': 0.0, // Edge case: brand new driver, no money yet
      'depart_time': '07:45 AM',
      'arrival_time': '08:30 AM',
      'start_location': {
        'lat': 3.2064, 'lng': 101.7323, 'name': 'Wangsa Maju LRT Station'
      },
      'end_location': {
        'lat': 3.2038, 'lng': 101.7219, 'name': 'Setapak Central Mall'
      }
    }
  });

  // 2. Create Active Subscription
  final subRef = firestore.collection('tumpang_subscription').doc('sub_match_77881');
  batch.set(subRef, {
    'passenger_id': 'usr_pass_9921',
    'driver_id': 'usr_driv_4412',
    'pickup_location': {
      'lat': 3.2025, 'lng': 101.7154, 'name': 'PV13 Platinum Lake Condominium, Setapak'
    },
    'dropoff_location': {
      'lat': 3.2159, 'lng': 101.7261, 'name': 'TAR UMT Arena, Kuala Lumpur'
    },
    'pickup_time': '07:55 AM',
    'fee': 150.00,
    'subscription_start_date': Timestamp.fromDate(DateTime(2026, 8, 1)),
    'subscription_end_date': Timestamp.fromDate(DateTime(2026, 8, 31)),
  });

  // 3. Create a Negotiation Request (Edge Case: Partially Accepted)
  final reqRef = firestore.collection('tumpang_request').doc('req_tumpang_5501');
  batch.set(reqRef, {
    'passenger_id': 'usr_pass_9921',
    'driver_id': 'usr_driv_4412',
    'status': 'negotiating',
    'pickup_location': {
      'lat': 3.2025, 'lng': 101.7154, 'name': 'PV13 Platinum Lake Condominium',
      'requested_by': 'usr_pass_9921', 'is_accepted': true
    },
    'dropoff_location': {
      'lat': 3.2159, 'lng': 101.7261, 'name': 'TAR UMT Arena',
      'requested_by': 'usr_pass_9921', 'is_accepted': true
    },
    'pickup_time': {
      'value': '07:50 AM', 'requested_by': 'usr_driv_4412', 'is_accepted': false // Still negotiating time
    },
    'fee': {
      'value': 140.00, 'requested_by': 'usr_pass_9921', 'is_accepted': false // Still negotiating fee
    },
    'subscription_start_date': {
      'value': Timestamp.fromDate(DateTime(2026, 9, 1)), 'requested_by': 'usr_pass_9921', 'is_accepted': true
    },
    'subscription_end_date': {
      'value': Timestamp.fromDate(DateTime(2026, 9, 30)), 'requested_by': 'usr_pass_9921', 'is_accepted': true
    }
  });

  // 4. Create Payments (Edge Case: One paid, one overdue)
  final paymentPaidRef = firestore.collection('payments').doc('pay_august_441');
  batch.set(paymentPaidRef, {
    'tumpang_subscription_id': 'sub_match_77881',
    'month': 8,
    'year': 2026,
    'due_date': Timestamp.fromDate(DateTime(2026, 8, 7)),
    'paid_at': Timestamp.fromDate(DateTime(2026, 8, 5)), // Paid early
  });

  final paymentOverdueRef = firestore.collection('payments').doc('pay_september_442');
  batch.set(paymentOverdueRef, {
    'tumpang_subscription_id': 'sub_match_77881',
    'month': 9,
    'year': 2026,
    'due_date': Timestamp.fromDate(DateTime(2026, 9, 7)),
    'paid_at': null, // Edge case: Unpaid and currently overdue
  });

  // 5. Create Voucher Catalog
  final voucherRef = firestore.collection('vouchers').doc('vch_famima_01');
  batch.set(voucherRef, {
    'name': 'RM5 Off FamilyMart',
    'description': 'Enjoy RM5 off any bento or oden purchase at the Setapak FamilyMart outlet.',
    'validity_days': 30,
    'tnc': 'Valid for walk-in only. Must present generated code at the cashier.',
    'open_for_redeem': true,
    'req_points': 50
  });

  // 6. Create an Exception (Edge Case: Driver Medical Leave)
  final exceptionRef = firestore.collection('tumpang_exception').doc('ex_8822');
  batch.set(exceptionRef, {
    'tumpang_subscription_id': 'sub_match_77881',
    'initiated_by': 'usr_driv_4412',
    'dates': [
      '2026-08-15',
      '2026-08-16'
    ],
    'reason': 'Medical leave',
  });

  // 7. Create Reward Points Batch
  final pointsRef = firestore.collection('reward_points').doc('batch_98A2bx');
  batch.set(pointsRef, {
    'user_id': 'usr_pass_9921',
    'obtained_points': 15,
    'avai_points': 8,
    'obtained_at': Timestamp.fromDate(DateTime(2026, 8, 1, 8, 30)),
    'expired_at': Timestamp.fromDate(DateTime(2026, 12, 31, 23, 59)),
  });

  // 8. Create User Voucher (Claimed Reward)
  final userVoucherRef = firestore.collection('user_vouchers').doc('uv_77XqL92');
  batch.set(userVoucherRef, {
    'user_id': 'usr_pass_9921',
    'voucher_id': 'vch_famima_01',
    'code': 'TUMPANG-FM-9921A',
    'obtained_at': Timestamp.fromDate(DateTime(2026, 8, 10, 14, 0)),
    'expired_at': Timestamp.fromDate(DateTime(2026, 9, 9, 14, 0)),
    'used_at': null, // Edge case: Unused voucher ready to be scanned
  });

  // 9. Create Payout History (Driver Withdrawal)
  final payoutRef = firestore.collection('payout_history').doc('wd_99xMz21');
  batch.set(payoutRef, {
    'user_id': 'usr_driv_4412',
    'amount': 65.00,
    'payout_at': Timestamp.fromDate(DateTime(2026, 8, 10, 14, 28)),
    'bank_name': 'Maybank',
    'bank_acc_no': '164012345678',
    'status': 'completed'
  });

  // --- DRIVER 2: THE PERFECT MATCH ---
  final driver2Ref = firestore.collection('users').doc('usr_driv_1002');
  batch.set(driver2Ref, {
    'name': 'Lim Wei Jie',
    'email': 'weijie.lim@gmail.com',
    'phone': '+60112233445',
    'reward_points_bal': 120,
    'role': 'driver',
    'active_days': {
      'monday': true, 'tuesday': true, 'wednesday': true,
      'thursday': true, 'friday': true, 'saturday': false, 'sunday': false
    },
    'passenger_profile': null,
    'driver_profile': {
      'earnings': 0.0,
      'depart_time': '07:50 AM',
      'arrival_time': '08:10 AM',
      'start_location': {
        'lat': 3.2005, 'lng': 101.7160, 'name': 'PV15 Platinum Lake Condominium'
      },
      'end_location': {
        'lat': 3.2155, 'lng': 101.7265, 'name': 'TAR UMT Main Gate'
      }
    }
  });

  // --- DRIVER 3: THE TIME MISMATCH ---
  final driver3Ref = firestore.collection('users').doc('usr_driv_1003');
  batch.set(driver3Ref, {
    'name': 'Muthu Kumar',
    'email': 'muthu.k@gmail.com',
    'phone': '+60199887766',
    'reward_points_bal': 45,
    'role': 'driver',
    'active_days': {
      'monday': true, 'tuesday': true, 'wednesday': true,
      'thursday': true, 'friday': true, 'saturday': false, 'sunday': false
    },
    'passenger_profile': null,
    'driver_profile': {
      'earnings': 35.0,
      'depart_time': '11:00 AM', // Way too late for the passenger
      'arrival_time': '11:30 AM',
      'start_location': {
        'lat': 3.2050, 'lng': 101.7140, 'name': 'Danau Kota Flat'
      },
      'end_location': {
        'lat': 3.2159, 'lng': 101.7261, 'name': 'TAR UMT Arena'
      }
    }
  });

  // --- DRIVER 4: THE ROUTE MISMATCH ---
  final driver4Ref = firestore.collection('users').doc('usr_driv_1004');
  batch.set(driver4Ref, {
    'name': 'Sarah Lee',
    'email': 'sarah.lee@gmail.com',
    'phone': '+60177788899',
    'reward_points_bal': 200,
    'role': 'driver',
    'active_days': {
      'monday': true, 'tuesday': true, 'wednesday': true,
      'thursday': true, 'friday': true, 'saturday': false, 'sunday': false
    },
    'passenger_profile': null,
    'driver_profile': {
      'earnings': 150.0,
      'depart_time': '07:45 AM', // Perfect time
      'arrival_time': '08:30 AM',
      'start_location': {
        'lat': 3.1340, 'lng': 101.6869, 'name': 'KL Sentral' // Wrong area
      },
      'end_location': {
        'lat': 3.1174, 'lng': 101.6775, 'name': 'Mid Valley Megamall' // Wrong area
      }
    }
  });

  // --- DRIVER 5: THE DAY MISMATCH ---
  final driver5Ref = firestore.collection('users').doc('usr_driv_1005');
  batch.set(driver5Ref, {
    'name': 'Amirul Haziq',
    'email': 'amirul.h@gmail.com',
    'phone': '+60133445566',
    'reward_points_bal': 10,
    'role': 'driver',
    'active_days': {
      'monday': false, 'tuesday': false, 'wednesday': false, // Wrong days
      'thursday': false, 'friday': false, 'saturday': true, 'sunday': true
    },
    'passenger_profile': null,
    'driver_profile': {
      'earnings': 0.0,
      'depart_time': '07:45 AM',
      'arrival_time': '08:15 AM',
      'start_location': {
        'lat': 3.2033, 'lng': 101.7188, 'name': 'Setapak Central'
      },
      'end_location': {
        'lat': 3.2159, 'lng': 101.7261, 'name': 'TAR UMT Arena'
      }
    }
  });

  // --- DRIVER 6: NEW MATCH (Starts deep in Danau Kota, ends at LRT) ---
  final driver6Ref = firestore.collection('users').doc('usr_driv_1006');
  batch.set(driver6Ref, {
    'name': 'Wong Kah Yan',
    'email': 'kahyan.w@gmail.com',
    'phone': '+60182223344',
    'reward_points_bal': 75,
    'role': 'driver',
    'active_days': {
      'monday': true, 'tuesday': true, 'wednesday': true,
      'thursday': true, 'friday': true, 'saturday': false, 'sunday': false
    },
    'passenger_profile': null,
    'driver_profile': {
      'earnings': 12.5,
      'depart_time': '07:45 AM',
      'arrival_time': '08:15 AM',
      'start_location': {
        'lat': 3.2001, 'lng': 101.7118, 'name': 'Danau Kota Suite'
      },
      'end_location': {
        'lat': 3.2225, 'lng': 101.7250, 'name': 'Taman Melati LRT'
      }
    }
  });

  // --- DRIVER 7: NEW MATCH (Long commute crossing through Setapak) ---
  final driver7Ref = firestore.collection('users').doc('usr_driv_1007');
  batch.set(driver7Ref, {
    'name': 'Aisyah Batrisyia',
    'email': 'aisyah.b@gmail.com',
    'phone': '+60124445566',
    'reward_points_bal': 210,
    'role': 'driver',
    'active_days': {
      'monday': true, 'tuesday': true, 'wednesday': true,
      'thursday': true, 'friday': true, 'saturday': false, 'sunday': false
    },
    'passenger_profile': null,
    'driver_profile': {
      'earnings': 85.0,
      'depart_time': '07:55 AM', // Adjusted to fit 30 min window
      'arrival_time': '08:45 AM',
      'start_location': {
        'lat': 3.2052, 'lng': 101.7077, 'name': 'Plaza Idaman, Gombak'
      },
      'end_location': {
        'lat': 3.2245, 'lng': 101.7310, 'name': 'KL East Mall'
      }
    }
  });

  // Commit the batch to Firestore
  try {
    await batch.commit();
    print('✅ Database successfully seeded!');
  } catch (e) {
    print('❌ Error seeding database: $e');
  }
}