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

  /// Account created, but Supabase requires the new email to be
  /// confirmed before a session exists. There's no `auth.uid()` yet, so
  /// nothing has been written to `users`/`driver_profiles`/storage —
  /// that happens on first login instead, once the account is
  /// confirmed. The screen should tell the user to check their email.
  pendingVerification,
}

class RegisterViewModel extends ChangeNotifier {
  RegisterViewModel({String initialRole = 'passenger'}) : role = initialRole {
    // Rebuild the phone field's focus-dependent border when focus changes.
    phoneFocusNode.addListener(notifyListeners);
  }

  String role;

  final nameController = TextEditingController();
  final phoneController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  final phoneFocusNode = FocusNode();

  // driver fields
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

        // If "Confirm email" is on, Supabase creates the auth user but
        // doesn't return a session until the confirmation link is
        // clicked. Without a session there's no auth.uid(), so RLS would
        // block writing to users/driver_profiles/storage right now —
        // defer all of that to first login instead, once they're
        // confirmed.
        if (response.session == null) {
          return RegisterResult.pendingVerification;
        }
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

      await _supabase.from('users').upsert({
        'id': newUserId,
        'name': nameController.text.trim(),
        'phone': fullPhoneForStorage,
        'email': emailController.text.trim(),
        'role': role,
      });

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
      // cannot register with email already in database
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