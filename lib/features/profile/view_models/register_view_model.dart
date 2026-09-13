import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nak_tumpang/core/utils/validators.dart';
import 'package:nak_tumpang/features/profile/data/services/profile_storage_service.dart';

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
  String? licenseNumberError;
  String? licenseError;

  // Set once the license (if any) is uploaded to Storage, then written
  // straight onto `driver_profiles` below in the same submit() call —
  // the post-signup "add trip" step (AddEditTripScreen) never touches
  // driver_profiles, it only ever writes driver_trips.
  String? licenseStoragePath;

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

  /// The Auth user id created by [submit], once it's run at least once.
  String? get registeredUserId => _registeredUserId;

  String get trimmedName => nameController.text.trim();
  String get trimmedEmail => emailController.text.trim();
  String get trimmedLicenseNumber => licenseNumberController.text.trim();
  String get storedPhone => Validators.toStoredPhone(phoneController.text);

  void setRole(String newRole) {
    role = newRole;
    notifyListeners();
  }

  Future<void> pickLicense() async {
    final bytes = await _storageService.pickImage(source: ImageSource.gallery);
    if (bytes == null) return;

    final imageCheck = await _storageService.validateImage(bytes);
    if (!imageCheck.isValid) {
      errorMessage = imageCheck.error;
      notifyListeners();
      return;
    }

    licenseBytes = bytes;
    errorMessage = null;
    notifyListeners();
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

  void _runValidation() {
    nameError = Validators.name(nameController.text);
    phoneError = Validators.phoneLocal(phoneController.text);
    emailError = Validators.email(emailController.text);
    passwordError = Validators.password(passwordController.text);
    confirmError = Validators.confirmPassword(confirmPasswordController.text, passwordController.text);

    if (role == 'driver') {
      licenseNumberError = Validators.licenseNumber(licenseNumberController.text);
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

  Future<bool> submit() async {
    // Guards against a second call landing while one is already in
    // flight (e.g. a double-tap before the UI rebuilds with isLoading
    // disabling the button) — this can create an auth user and upload a
    // file, so don't rely on the button's disabled state alone.
    if (isLoading) return false;

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
      return false;
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
          return false;
        }

        final createdUserId = response.user?.id;
        if (createdUserId == null) {
          errorMessage = 'Something went wrong creating your account.';
          return false;
        }
        newUserId = createdUserId;
        _registeredUserId = newUserId;

        // "Confirm email" is off for this project, so signUp() always
        // returns a session immediately — there's no pending-
        // verification state to handle here. If that setting ever gets
        // turned on, this assumption breaks (signUp() would return
        // session: null and auth.uid() wouldn't exist yet for the
        // writes below), so this comment is the flag to revisit it.
      }

      // Tracked separately from licenseStoragePath: only set when *this*
      // call actually uploads a file, so the rollback below can't ever
      // delete a file a previous, already-committed attempt is relying
      // on — only ever the upload made in this attempt, if the DB
      // writes right after it fail.
      String? pendingLicensePath;
      if (role == 'driver' && licenseBytes != null) {
        isUploadingLicense = true;
        notifyListeners();
        // Unique filename per upload (rather than a fixed 'license.jpg')
        // so re-picking a new photo on a retry doesn't collide with, or
        // get confused for, an earlier attempt.
        pendingLicensePath = await _storageService.uploadUserFile(
          bytes: licenseBytes!,
          bucket: 'driver-licenses',
          userId: newUserId,
          fileName: 'license_${DateTime.now().millisecondsSinceEpoch}.jpg',
          public: false,
        );
        licenseStoragePath = pendingLicensePath;
        isUploadingLicense = false;
      }

      try {
        // Account row is written immediately for both roles now — a
        // route is no longer required to have an account. Adding a trip
        // is an optional next step offered by the "Let's get started!"
        // dialog instead, not a precondition for the account existing.
        await _supabase.from('users').upsert({
          'id': newUserId,
          'name': nameController.text.trim(),
          'phone': fullPhoneForStorage,
          'email': emailController.text.trim(),
          'role': role,
        });

        if (role == 'driver') {
          await _supabase.from('driver_profiles').upsert({
            'user_id': newUserId,
            'total_earnings': 0,
            'available_balance': 0,
            'total_withdrawn': 0,
            'license_number': trimmedLicenseNumber,
            'license_url': licenseStoragePath,
          });
        }
      } catch (e) {
        // Neither write can be trusted to have committed — clean up the
        // license file uploaded *in this attempt* so a failed submit
        // doesn't leave an orphaned file in Storage that nothing in the
        // DB ever ends up pointing to. A later retry (same screen
        // instance) re-uploads under a fresh filename, so this is always
        // safe to remove.
        if (pendingLicensePath != null) {
          await _storageService.deleteUserFile(bucket: 'driver-licenses', path: pendingLicensePath);
          licenseStoragePath = null;
        }
        rethrow;
      }

      return true;
    } on AuthException catch (e) {
      errorMessage = e.message;
      return false;
    } on PostgrestException catch (e) {
      // cannot register with email already in database
      errorMessage = e.code == '23505'
          ? 'That account detail is already registered.'
          : 'Could not complete registration. Please try again.';
      return false;
    } catch (e) {
      errorMessage = 'Could not complete registration. Please try again.';
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}