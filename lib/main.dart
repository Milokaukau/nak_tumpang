import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:nak_tumpang/core/theme/app_theme.dart';
import 'package:nak_tumpang/core/app_providers.dart';
import 'package:nak_tumpang/features/home/UI/screens/home_screen.dart';
import 'package:nak_tumpang/core/services/local_db_service.dart';
// TODO: adjust this import to wherever your teammate's real login screen lives.
import 'package:nak_tumpang/features/auth/UI/screens/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: ".env");

  final supabaseUrl = dotenv.env['SUPABASE_URL'];
  final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'];
  final stripePublishableKey = dotenv.env['STRIPE_PUBLISHABLE_KEY'];

  // Fail fast with a clear message instead of silently initializing with
  // empty strings, which produces confusing runtime errors much later.
  // Never print the actual key values/prefixes — that leaks credentials
  // into logs (including crash reporting tools that capture stdout).
  if (supabaseUrl == null || supabaseUrl.isEmpty) {
    throw StateError('SUPABASE_URL is missing from .env — check your .env file exists and is loaded.');
  }
  if (supabaseAnonKey == null || supabaseAnonKey.isEmpty) {
    throw StateError('SUPABASE_ANON_KEY is missing from .env.');
  }
  if (stripePublishableKey == null || stripePublishableKey.isEmpty) {
    throw StateError('STRIPE_PUBLISHABLE_KEY is missing from .env.');
  }

  Stripe.publishableKey = stripePublishableKey;

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );

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
      home: const AuthGate(),
    );
  }
}

/// Shows the login screen if nobody is signed in, otherwise the home screen.
/// Rebuilds automatically whenever the auth state changes (sign in/out).
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = Supabase.instance.client.auth.currentSession;
        if (session != null) {
          return const HomeScreen();
        }
        return const LoginScreen();
      },
    );
  }
}