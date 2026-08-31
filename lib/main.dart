import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:nak_tumpang/core/theme/app_theme.dart';
import 'package:nak_tumpang/core/app_providers.dart';
import 'package:nak_tumpang/features/home/UI/screens/home_screen.dart';
import 'package:nak_tumpang/core/services/local_db_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

// Load the .env file
  await dotenv.load(fileName: ".env");

  // ADD THESE TWO LINES:
  print("🔗 Target URL: ${dotenv.env['SUPABASE_URL']}");
  print("🔑 Target Key starts with: ${dotenv.env['SUPABASE_ANON_KEY']?.substring(0, 10)}...");

  // Initialize Supabase
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL'] ?? '',
    publishableKey: dotenv.env['SUPABASE_ANON_KEY'] ?? '',
  );

  print('✅ Supabase connected successfully!');

  await LocalDbService.instance.testConnection();

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