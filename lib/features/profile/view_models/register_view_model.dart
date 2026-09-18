import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nak_tumpang/core/services/network_service.dart';
import 'package:nak_tumpang/core/utils/validators.dart';
import 'package:nak_tumpang/features/profile/data/services/profile_local_service.dart';
import 'package:nak_tumpang/features/profile/data/services/profile_storage_service.dart';

class RegisterViewModel extends ChangeNotifier {
  RegisterViewModel({String initialRole = 'passenger'}) : role = initialRole {
    phoneFocusNode.addListener(notifyListeners);
  }

  String role;

  final nameController = TextEditingController();
  final phoneController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  final phoneFocusNode = FocusNode();

  final carPlateNumberController = TextEditingController();
  Uint8List? licenseBytes;
  bool isUploadingLicense = false;
  String? licenseNumberError;
  String? licenseError;
  String? licenseStoragePath;

  final _storageService = ProfileStorageService();
  final _localService = ProfileLocalService();

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

  String? get registeredUserId => _registeredUserId;

  String get trimmedName => nameController.text.trim();
  String get trimmedEmail => emailController.text.trim();
  String get trimmedCarPlateNumber => carPlateNumberController.text.trim();
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
    carPlateNumberController.dispose();
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
      licenseNumberError = Validators.carPlateNumber(carPlateNumberController.text);
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

    if (NetworkService.isOfflineNotifier.value) {
      errorMessage = "You're offline. You need an internet connection to create an account.";
      notifyListeners();
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
      }
      String? pendingLicensePath;
      if (role == 'driver' && licenseBytes != null) {
        isUploadingLicense = true;
        notifyListeners();
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
            'license_number': trimmedCarPlateNumber,
            'license_url': licenseStoragePath,
          });
        }

      } catch (e) {
        if (pendingLicensePath != null) {
          await _storageService.deleteUserFile(bucket: 'driver-licenses', path: pendingLicensePath);
          licenseStoragePath = null;
        }
        rethrow;
      }

      try {
        await _localService.cacheUserProfile(
          userId: newUserId,
          name: nameController.text.trim(),
          email: emailController.text.trim(),
          phone: fullPhoneForStorage,
          role: role,
        );
        if (role == 'driver') {
          await _localService.cacheDriverLicense(
            userId: newUserId,
            licenseNumber: trimmedCarPlateNumber,
            licenseUrl: licenseStoragePath,
          );
        }
      } catch (e) {
        debugPrint('Registered on Supabase but failed to seed local cache: $e');
      }

      return true;
    } on AuthException catch (e) {
      errorMessage = e.message;
      return false;
    } on PostgrestException catch (e) {
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