import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:nak_tumpang/core/theme/app_theme.dart';
import 'package:nak_tumpang/core/app_providers.dart';
import 'package:nak_tumpang/features/home/UI/screens/home_screen.dart';
import 'package:nak_tumpang/features/auth/UI/screens/login_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load the .env file
  await dotenv.load(fileName: ".env");

  final supabaseUrl = dotenv.env['SUPABASE_URL'];
  final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'];

  if (supabaseUrl == null || supabaseAnonKey == null) {
    throw StateError(
      'Missing SUPABASE_URL or SUPABASE_ANON_KEY — check your .env file.',
    );
  }

  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
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
      home: const AuthGate(),
    );
  }
}

// shows login screen if nobody is logged in, homescreen if already logged in

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot){
        final session = Supabase.instance.client.auth.currentSession;
        if (session != null){
          return const HomeScreen();
        }
        return const LoginScreen();
      },
    );
  }
}