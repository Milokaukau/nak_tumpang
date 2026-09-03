import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Holds all state and logic for the login form. The screen only reads
/// state from here and calls [submit]/[toggleObscurePassword] — no
/// validation or Supabase calls live in the widget itself.
class LoginViewModel extends ChangeNotifier {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool isLoading = false;
  bool obscurePassword = true;
  String? errorMessage;

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

  /// Attempts to log in. Returns true on success so the screen can
  /// navigate onward; all other state (loading/errors) is exposed via
  /// this notifier for the screen to react to.
  Future<bool> submit() async {
    _autoValidate = true;
    emailError = _validateEmail(emailController.text);
    passwordError = _validatePassword(passwordController.text);
    notifyListeners();

    if (emailError != null || passwordError != null) return false;

    isLoading = true;
    errorMessage = null;
    notifyListeners();

    final email = emailController.text.trim();
    final password = passwordController.text;

    try {
      await _supabase.auth.signInWithPassword(email: email, password: password);
      return true;
    } on AuthException catch (e) {
      errorMessage = e.message.contains('Invalid login credentials')
          ? 'Incorrect email or password.'
          : e.message;
      return false;
    } catch (e) {
      errorMessage = 'Something went wrong. Please try again.';
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}