import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:nak_tumpang/core/theme/app_theme.dart';
import 'package:nak_tumpang/core/app_providers.dart';
import 'package:nak_tumpang/features/home/UI/screens/home_screen.dart';
import 'package:nak_tumpang/core/services/local_db_service.dart';
import 'package:nak_tumpang/features/auth/UI/screens/login_screen.dart';
import 'package:nak_tumpang/core/services/network_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: ".env");

  final supabaseUrl = dotenv.env['SUPABASE_URL'];
  final supabasePublishableKey = dotenv.env['SUPABASE_PUBLISHABLE_KEY'];
  final stripePublishableKey = dotenv.env['STRIPE_PUBLISHABLE_KEY'];

  if (supabaseUrl == null || supabaseUrl.isEmpty) {
    throw StateError('SUPABASE_URL is missing from .env');
  }
  if (supabasePublishableKey == null || supabasePublishableKey.isEmpty) {
    throw StateError('SUPABASE_PUBLISHABLE_KEY is missing from .env.');
  }
  if (stripePublishableKey == null || stripePublishableKey.isEmpty) {
    throw StateError('STRIPE_PUBLISHABLE_KEY is missing from .env.');
  }

  Stripe.publishableKey = stripePublishableKey;

  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabasePublishableKey,
  );

  await LocalDbService.instance.testConnection();

  await NetworkService.initialize();

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
      scaffoldMessengerKey: NetworkService.messengerKey,
      home: const AuthGate(),
    );
  }
}

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