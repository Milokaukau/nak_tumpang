import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nak_tumpang/core/utils/validators.dart';

/// Holds all state and logic for the sign-up form. The screen only reads
/// state from here and calls [submit] — no validation or Supabase calls
/// live in the widget itself.
class RegisterViewModel extends ChangeNotifier {
  final nameController = TextEditingController();
  final icController = TextEditingController();
  final phoneController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  final phoneFocusNode = FocusNode();

  bool obscurePassword = true;
  bool obscureConfirmPassword = true;
  bool isLoading = false;
  String? errorMessage;

  String? nameError;
  String? icError;
  String? phoneError;
  String? emailError;
  String? passwordError;
  String? confirmError;

  bool _autoValidate = false;

  final _supabase = Supabase.instance.client;

  @override
  void dispose() {
    nameController.dispose();
    icController.dispose();
    phoneController.dispose();
    phoneFocusNode.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  void toggleObscurePassword() {
    obscurePassword = !obscurePassword;
    notifyListeners();
  }

  void toggleObscureConfirmPassword() {
    obscureConfirmPassword = !obscureConfirmPassword;
    notifyListeners();
  }

  void _runValidation() {
    nameError = Validators.name(nameController.text);
    icError = Validators.ic(icController.text);
    phoneError = Validators.phoneLocal(phoneController.text);
    emailError = Validators.email(emailController.text);
    passwordError = Validators.password(passwordController.text);
    confirmError = Validators.confirmPassword(confirmPasswordController.text, passwordController.text);
  }

  void revalidateIfNeeded() {
    if (!_autoValidate) return;
    _runValidation();
    notifyListeners();
  }

  /// Attempts to register. Returns true on success so the screen can
  /// navigate onward; all other state (loading/errors) is exposed via
  /// this notifier for the screen to react to.
  Future<bool> submit() async {
    _autoValidate = true;
    _runValidation();
    notifyListeners();

    if (nameError != null ||
        icError != null ||
        phoneError != null ||
        emailError != null ||
        passwordError != null ||
        confirmError != null) {
      return false;
    }

    isLoading = true;
    errorMessage = null;
    notifyListeners();

    final fullPhoneForStorage = Validators.toStoredPhone(phoneController.text);
    final cleanedIC = icController.text.replaceAll(RegExp(r'[^0-9]'), '');

    try {
      // Check IC uniqueness BEFORE creating the auth user. Without this,
      // a duplicate IC fails silently in the DB trigger that creates the
      // profiles row *after* auth.signUp() has already committed, leaving
      // an orphaned auth user behind (email "already exists" on retry,
      // even though nothing was ever actually created for that email).
      final existingIC = await _supabase
          .from('profiles')
          .select('id')
          .eq('ic_number', cleanedIC)
          .maybeSingle();

      if (existingIC != null) {
        icError = 'This IC number is already registered';
        errorMessage = 'This IC number is already registered';
        return false;
      }

      final response = await _supabase.auth.signUp(
        email: emailController.text.trim(),
        password: passwordController.text,
        data: {
          'name': nameController.text.trim(),
          'ic_number': cleanedIC,
          'phone': fullPhoneForStorage,
          'role': 'passenger', // placeholder; the role dialog after this sets the real one
        },
      );

      // double check if email exists
      final identities = response.user?.identities;
      if (identities != null && identities.isEmpty) {
        errorMessage = 'An account with this email already exists. Please log in instead.';
        return false;
      }

      return true;
    } on AuthException catch (e) {
      errorMessage = e.message;
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