import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// What the screen should do after [LoginViewModel.submit] succeeds.
enum LoginResult {
  /// Go straight to the home screen as normal.
  home,
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
  // driver_profiles row here (see submit()) — their license never made
  // it into driver_profiles (backfilling it here has no license to
  // attach), so the screen should nudge them to add it again from their
  // profile.
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

      final existingRow = await _supabase
          .from('users')
          .select('role, name, phone, email')
          .eq('id', userId)
          .maybeSingle();

      // RegisterViewModel writes `users` (and `driver_profiles`, for
      // drivers) immediately once the auth account is created — "Confirm
      // email" is off for this project, so that always happens during
      // registration itself, never deferred to here. A missing `users`
      // row at login time therefore means that write didn't fully land
      // (e.g. the connection dropped between signUp() succeeding and
      // the users upsert running) — self-heal it the same way
      // RegisterViewModel would have, same reasoning as the
      // driver_profiles self-heal below.
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
          // Same existence check as the self-heal branch below, and for
          // the same reason: `existingRow == null` means no `users` row
          // was found, but that's not proof driver_profiles is also
          // missing — maybeSingle() also returns null on an RLS-hidden
          // row, and if driver_profiles genuinely already has a real
          // balance, upserting zeros here would silently wipe it.
          final driverProfile = await _supabase
              .from('driver_profiles')
              .select('user_id')
              .eq('user_id', userId)
              .maybeSingle();

          if (driverProfile == null) {
            // The license was never uploaded here — there's no local
            // copy of the picked photo left to fall back on this far
            // after registration — so nudge them to add it from their
            // profile.
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
        // Self-heal: a driver's `users` and `driver_profiles` rows are
        // always written together (RegisterViewModel, or the backfill
        // above), so a `users` row should mean `driver_profiles` exists
        // too. This only catches the rare case where that didn't fully
        // commit (e.g. the network dropped mid-write). Checked on every
        // login, not just the first, since a driver could go a while
        // without noticing a missing wallet.
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
      errorMessage = 'Something went wrong. Please try again.';
      return null;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}