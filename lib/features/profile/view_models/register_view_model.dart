import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nak_tumpang/core/utils/validators.dart';
import 'package:nak_tumpang/features/profile/data/services/profile_storage_service.dart';

/// What the screen should do after [RegisterViewModel.submit] succeeds.
enum RegisterResult {
  /// Driver account created — go to the post-signup-driver (route/days/
  /// time) page next.
  driverNext,

  /// Passenger account created — show the "Let's get started!" popup.
  passengerComplete,
}

/// Holds all state and logic for the sign-up form. The screen only reads
/// state from here and calls [submit] — no validation or Supabase calls
/// live in the widget itself.
class RegisterViewModel extends ChangeNotifier {
  RegisterViewModel({String initialRole = 'passenger'}) : role = initialRole {
    // Rebuild the phone field's focus-dependent border when focus changes.
    phoneFocusNode.addListener(notifyListeners);
  }

  /// 'passenger' or 'driver' — switchable from the screen's role toggle
  /// before the account is created.
  String role;

  final nameController = TextEditingController();
  final phoneController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  final phoneFocusNode = FocusNode();

  // Driver-only fields.
  final licenseNumberController = TextEditingController();
  Uint8List? licenseBytes;
  bool isUploadingLicense = false;
  final _licenseNumberRegex = RegExp(r'^[A-Z0-9](?:[A-Z0-9\s-]*[A-Z0-9])?$');
  String? licenseNumberError;
  String? licenseError;

  final _storageService = ProfileStorageService();

  bool obscurePassword = true;
  bool obscureConfirmPassword = true;
  bool isLoading = false;
  String? errorMessage;

  String? nameError;
  String? phoneError;
  String? emailError;
  String? passwordError;
  String? confirmError;

  bool _autoValidate = false;

  final _supabase = Supabase.instance.client;

  // Set once `submit()` has successfully created the auth account. A
  // driver can back out of the following route/days/time page to this
  // screen (e.g. to fix a typo) and press "Next" again — in that case
  // the account already exists, so re-run only skips straight to
  // updating the `users`/`driver_profiles` rows instead of calling
  // `auth.signUp` again (which would fail with "email already
  // registered", even though it's *their* email).
  String? _registeredUserId;

  void setRole(String newRole) {
    role = newRole;
    notifyListeners();
  }

  Future<void> pickLicense() async {
    final bytes = await _storageService.pickImage(source: ImageSource.gallery);
    if (bytes != null) {
      licenseBytes = bytes;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    phoneFocusNode.removeListener(notifyListeners);
    phoneFocusNode.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    licenseNumberController.dispose();
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

  String? _validateLicenseNumber(String v) {
    final trimmed = v.trim();
    if (trimmed.isEmpty) return 'License number is required';
    if (!_licenseNumberRegex.hasMatch(trimmed)) return 'Enter a valid license number';
    return null;
  }

  void _runValidation() {
    nameError = Validators.name(nameController.text);
    phoneError = Validators.phoneLocal(phoneController.text);
    emailError = Validators.email(emailController.text);
    passwordError = Validators.password(passwordController.text);
    confirmError = Validators.confirmPassword(confirmPasswordController.text, passwordController.text);

    if (role == 'driver') {
      licenseNumberError = _validateLicenseNumber(licenseNumberController.text);
      licenseError = licenseBytes == null ? 'Please upload your driving license' : null;
    } else {
      licenseNumberError = null;
      licenseError = null;
    }
  }

  void revalidateIfNeeded() {
    if (!_autoValidate) return;
    _runValidation();
    notifyListeners();
  }

  /// Attempts to register. Returns the next step on success (null on
  /// failure); all other state (loading/errors) is exposed via this
  /// notifier for the screen to react to.
  Future<RegisterResult?> submit() async {
    _autoValidate = true;
    _runValidation();
    notifyListeners();

    if (nameError != null ||
        phoneError != null ||
        emailError != null ||
        passwordError != null ||
        confirmError != null ||
        licenseNumberError != null ||
        licenseError != null) {
      return null;
    }

    isLoading = true;
    errorMessage = null;
    notifyListeners();

    final fullPhoneForStorage = Validators.toStoredPhone(phoneController.text);

    try {
      String newUserId;

      if (_registeredUserId != null) {
        // Already signed up on an earlier pass (see [_registeredUserId])
        // — just reuse that account instead of signing up again.
        newUserId = _registeredUserId!;
      } else {
        final response = await _supabase.auth.signUp(
          email: emailController.text.trim(),
          password: passwordController.text,
          data: {
            'name': nameController.text.trim(),
            'phone': fullPhoneForStorage,
            'role': role,
          },
        );

        // double check if email exists
        final identities = response.user?.identities;
        if (identities != null && identities.isEmpty) {
          errorMessage = 'An account with this email already exists. Please log in instead.';
          return null;
        }

        final createdUserId = response.user?.id;
        if (createdUserId == null) {
          errorMessage = 'Something went wrong creating your account.';
          return null;
        }
        newUserId = createdUserId;
        _registeredUserId = newUserId;
      }

      String? licenseStoragePath;
      if (role == 'driver' && licenseBytes != null) {
        isUploadingLicense = true;
        notifyListeners();
        licenseStoragePath = await _storageService.uploadUserFile(
          bytes: licenseBytes!,
          bucket: 'driver-licenses',
          userId: newUserId,
          fileName: 'license.jpg',
          public: false,
        );
        isUploadingLicense = false;
      }

      // Don't rely solely on a DB trigger to create the `users` row — upsert
      // it directly so name and phone are guaranteed to be there even if
      // the trigger is missing or doesn't copy every field.
      await _supabase.from('users').upsert({
        'id': newUserId,
        'name': nameController.text.trim(),
        'phone': fullPhoneForStorage,
        'email': emailController.text.trim(),
        'role': role,
      });

      // A fresh driver needs a driver_profiles row too, so the wallet
      // screen has something to read instead of relying purely on
      // client-side zero defaults. This also carries the license number
      // and photo path — driver-only data lives here, not on `users`.
      // This is non-critical bookkeeping — by this point the auth user
      // and `users` row already exist, so a failure here (e.g. an RLS
      // hiccup) must NOT surface as a registration failure. That used to
      // report an error on an account that had, in fact, already been
      // created, and every retry after that failed with "email already
      // exists" — because it did. If this fails, driver_profiles just
      // stays absent until it's created lazily elsewhere (e.g. first
      // wallet screen load) — though that does mean the license info
      // wouldn't be saved in that rare case; the profile screen lets a
      // driver re-upload it later if it's ever missing.
      if (role == 'driver') {
        try {
          await _supabase.from('driver_profiles').upsert({
            'user_id': newUserId,
            'total_earnings': 0,
            'available_balance': 0,
            'total_withdrawn': 0,
            'license_number': licenseNumberController.text.trim(),
            'license_url': licenseStoragePath,
          });
        } catch (e) {
          debugPrint('driver_profiles bootstrap failed (non-fatal): $e');
        }
      }

      return role == 'driver' ? RegisterResult.driverNext : RegisterResult.passengerComplete;
    } on AuthException catch (e) {
      errorMessage = e.message;
      return null;
    } on PostgrestException catch (e) {
      // Surfaces the real DB error (e.g. unique constraint) instead of
      // hiding it behind a generic message.
      errorMessage = e.code == '23505'
          ? 'That account detail is already registered.'
          : e.message;
      return null;
    } catch (e) {
      errorMessage = 'Something went wrong: $e';
      return null;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}