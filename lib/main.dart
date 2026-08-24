import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:nak_tumpang/firebase_options.dart';
import 'package:nak_tumpang/core/theme/app_theme.dart';
import 'package:nak_tumpang/core/app_providers.dart';
import 'package:nak_tumpang/features/home/UI/screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(
    MultiProvider(
      providers: AppProviders.providers,
      child: const TumpangApp(),
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