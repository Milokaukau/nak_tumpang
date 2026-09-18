import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nak_tumpang/core/services/network_service.dart';

enum LoginResult {
  home,
}

class LoginViewModel extends ChangeNotifier {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool isLoading = false;
  bool obscurePassword = true;
  String? errorMessage;

  bool driverLicenseNeedsReupload = false;

  String? emailError;
  String? passwordError;

  bool _autoValidate = false;

  static final RegExp _emailRegex = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$');

  final _supabase = Supabase.instance.client;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  void toggleObscurePassword() {
    obscurePassword = !obscurePassword;
    notifyListeners();
  }

  String? _validateEmail(String? v) {
    if (v == null || v.trim().isEmpty) return 'Email is required';
    if (!_emailRegex.hasMatch(v.trim())) return 'Enter a valid email';
    return null;
  }

  String? _validatePassword(String? v) {
    if (v == null || v.isEmpty) return 'Password is required';
    if (v.length < 6) return 'At least 6 characters';
    return null;
  }

  void revalidateIfNeeded() {
    if (!_autoValidate) return;
    emailError = _validateEmail(emailController.text);
    passwordError = _validatePassword(passwordController.text);
    notifyListeners();
  }

  Future<LoginResult?> submit() async {
    _autoValidate = true;
    emailError = _validateEmail(emailController.text);
    passwordError = _validatePassword(passwordController.text);
    notifyListeners();

    if (emailError != null || passwordError != null) return null;


    if (NetworkService.isOfflineNotifier.value) {
      errorMessage = "You're offline. Connect to the internet to log in.";
      notifyListeners();
      return null;
    }

    isLoading = true;
    errorMessage = null;
    driverLicenseNeedsReupload = false;
    notifyListeners();

    final email = emailController.text.trim();
    final password = passwordController.text;

    try {
      final response = await _supabase.auth.signInWithPassword(email: email, password: password);
      final userId = response.user?.id;
      if (userId == null) return LoginResult.home;

      final existingRow = await _supabase
          .from('users')
          .select('role, name, phone, email')
          .eq('id', userId)
          .maybeSingle();

      if (existingRow == null) {
        final meta = response.user?.userMetadata;
        final role = meta?['role'] as String? ?? 'passenger';
        final phone = meta?['phone'] as String? ?? '';

        await _supabase.from('users').upsert({
          'id': userId,
          'name': meta?['name'] as String? ?? '',
          'phone': phone,
          'email': response.user?.email,
          'role': role,
        });

        if (role == 'driver') {
          final driverProfile = await _supabase
              .from('driver_profiles')
              .select('user_id')
              .eq('user_id', userId)
              .maybeSingle();

          if (driverProfile == null) {
            await _supabase.from('driver_profiles').upsert({
              'user_id': userId,
              'total_earnings': 0,
              'available_balance': 0,
              'total_withdrawn': 0,
            });
            driverLicenseNeedsReupload = true;
          }
        }
      } else if (existingRow['role'] == 'driver') {
        final driverProfile = await _supabase
            .from('driver_profiles')
            .select('license_number, license_url')
            .eq('user_id', userId)
            .maybeSingle();

        if (driverProfile == null) {
          await _supabase.from('driver_profiles').upsert({
            'user_id': userId,
            'total_earnings': 0,
            'available_balance': 0,
            'total_withdrawn': 0,
          });
          driverLicenseNeedsReupload = true;
        }
      }

      return LoginResult.home;
    } on AuthException catch (e) {
      errorMessage = e.message.contains('Invalid login credentials')
          ? 'Incorrect email or password.'
          : e.message;
      return null;
    } catch (e) {
      debugPrint('LoginViewModel.submit failed: $e');
      errorMessage = 'Something went wrong. Please try again.';
      return null;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}