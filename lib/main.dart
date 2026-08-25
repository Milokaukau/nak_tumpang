import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'; // 1. Added Riverpod import
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:nak_tumpang/firebase_options.dart';
import 'package:nak_tumpang/core/theme/app_theme.dart';
import 'package:nak_tumpang/core/app_providers.dart';
import 'package:nak_tumpang/features/home/UI/screens/home_screen.dart';
// import 'package:nak_tumpang/seed_data.dart'; // NEVER REMOVE THIS IMPORT (if error occurred, just comment out)

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load the .env file
  await dotenv.load(fileName: ".env");

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // NEVER REMOVE THIS PART ===============
  // await populateFirestore();
  //=======================================

  runApp(
    // 2. Wrapped root in ProviderScope
    ProviderScope(
      child: MultiProvider(
        providers: AppProviders.providers,
        child: const TumpangApp(),
      ),
    ),
  );
}

class TumpangApp extends StatelessWidget {
  const TumpangApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tumpang',
      theme: AppTheme.lightTheme,
      debugShowCheckedModeBanner: false,
      home: const HomeScreen(),
    );
  }
}