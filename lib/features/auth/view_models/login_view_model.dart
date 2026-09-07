import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// What the screen should do after [LoginViewModel.submit] succeeds.
enum LoginResult {
  /// Go straight to the home screen as normal.
  home,

  /// Signed in fine, but this driver still needs to finish the
  /// route/days/time setup that `RegisterViewModel` normally does right
  /// after signup — see the comment on [submit] for why that can be
  /// deferred all the way to here.
  needsDriverSetup,
}

/// Holds all state and logic for the login form. The screen only reads
/// state from here and calls [submit]/[toggleObscurePassword] — no
/// validation or Supabase calls live in the widget itself.
class LoginViewModel extends ChangeNotifier {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool isLoading = false;
  bool obscurePassword = true;
  String? errorMessage;

  // Set during submit() when we had to backfill this driver's
  // driver_profiles row here (see submit()) — their license was never
  // saved (registration only uploads it once a session exists, and a
  // confirm-your-email account has none yet), so the screen should nudge
  // them to add it again from their profile.
  bool driverLicenseNeedsReupload = false;

  // Per-field error messages, rendered manually below each box so they
  // align flush-left with the labels/box edges instead of using Flutter's
  // default (indented) error text.
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

  /// Attempts to log in. Returns the next step on success (null on
  /// failure); all other state (loading/errors) is exposed via this
  /// notifier for the screen to react to.
  Future<LoginResult?> submit() async {
    _autoValidate = true;
    emailError = _validateEmail(emailController.text);
    passwordError = _validatePassword(passwordController.text);
    notifyListeners();

    if (emailError != null || passwordError != null) return null;

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

      final existingRow = await _supabase.from('users').select('role').eq('id', userId).maybeSingle();

      // First login after confirming their email: signUp() deliberately
      // skipped writing the `users` (and, for a driver, `driver_profiles`)
      // row, because there was no session/auth.uid() yet for RLS to allow
      // it — see the comment in RegisterViewModel.submit(). That moment
      // has now arrived, so backfill from the metadata signUp() stashed
      // on the auth user. This only ever runs once per account — after
      // this, the row exists and every future login skips straight past.
      if (existingRow == null) {
        final meta = response.user?.userMetadata;
        final role = meta?['role'] as String? ?? 'passenger';

        await _supabase.from('users').upsert({
          'id': userId,
          'name': meta?['name'] as String? ?? '',
          'phone': meta?['phone'] as String?,
          'email': response.user?.email,
          'role': role,
        });

        if (role == 'driver') {
          // The license they picked during registration only ever lived
          // in memory on that screen — there was nothing to attach it to
          // yet, so it's gone. Zero-balance wallet row now; they'll need
          // to re-add the license from their profile.
          await _supabase.from('driver_profiles').upsert({
            'user_id': userId,
            'total_earnings': 0,
            'available_balance': 0,
            'total_withdrawn': 0,
          });
          driverLicenseNeedsReupload = true;
          // Same driver_trips step registration would have sent them to
          // immediately after signing up — just resumed here instead,
          // since signup couldn't do it yet. Not re-checked on later
          // logins.
          return LoginResult.needsDriverSetup;
        }
      }

      return LoginResult.home;
    } on AuthException catch (e) {
      errorMessage = e.message.contains('Invalid login credentials')
          ? 'Incorrect email or password.'
          : e.message;
      return null;
    } catch (e) {
      errorMessage = 'Something went wrong. Please try again.';
      return null;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}