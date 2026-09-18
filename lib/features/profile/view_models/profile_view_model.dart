import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nak_tumpang/core/services/network_service.dart';
import 'package:nak_tumpang/core/utils/validators.dart';
import 'package:nak_tumpang/features/profile/data/services/profile_local_service.dart';
import 'package:nak_tumpang/features/profile/data/services/profile_storage_service.dart';

enum ProfileSaveResult {
  success,
  failure,
}

class ProfileViewModel extends ChangeNotifier {
  ProfileViewModel();

  final supabase = Supabase.instance.client;
  final _storageService = ProfileStorageService();
  final _localService = ProfileLocalService();

  final nameController = TextEditingController();
  final phoneController = TextEditingController();
  final carPlateNumberController = TextEditingController();
  final currentPasswordController = TextEditingController();
  final newPasswordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  final phoneFocusNode = FocusNode();

  bool obscureCurrentPassword = true;
  bool obscureNewPassword = true;
  bool obscureConfirmPassword = true;

  bool showChangePassword = false;

  String _role = 'passenger';
  String? _originalRole;
  String? _email;

  String get role => _role;
  String? get email => _email;

  bool get isOffline => NetworkService.isOfflineNotifier.value;

  Uint8List? avatarBytes;
  String? avatarUrl;
  bool isUploadingAvatar = false;

  Uint8List? licenseBytes;
  String? licenseUrl;
  String? _licensePath;
  bool isUploadingLicense = false;

  String? _pendingAvatarFileName;

  bool isLoading = true;
  bool isSaving = false;
  String? errorMessage;
  String? successMessage;

  bool _autoValidate = false;
  String? nameError;
  String? phoneError;
  String? carPlateNumberError;
  String? currentPasswordError;
  String? newPasswordError;
  String? confirmPasswordError;

  @override
  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    phoneFocusNode.dispose();
    carPlateNumberController.dispose();
    currentPasswordController.dispose();
    newPasswordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> loadProfile() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      isLoading = false;
      notifyListeners();
      return;
    }

    try {
      final data = await supabase.from('users').select().eq('id', userId).maybeSingle();
      final meta = supabase.auth.currentUser?.userMetadata;

      if (data == null) {
        nameController.text = meta?['name'] as String? ?? '';
        phoneController.text = Validators.localDigitsFromStored(meta?['phone'] as String?);
        _role = meta?['role'] as String? ?? 'passenger';
        _originalRole = _role;
      } else {
        nameController.text = data['name'] ?? '';
        phoneController.text = Validators.localDigitsFromStored(data['phone']);
        _role = data['role'] ?? 'passenger';
        _originalRole = data['role'] as String?;
        avatarUrl = data['avatar_url'] as String?;
      }
      _email = data?['email'] as String? ?? supabase.auth.currentUser?.email;

      if (data != null) {
        await _localService.cacheUserProfile(
          userId: userId,
          name: data['name'] as String? ?? '',
          email: _email ?? '',
          phone: data['phone'] as String? ?? '',
          role: _role,
          avatarUrl: avatarUrl,
        );
      }

      if (_role == 'driver') {
        final driverData = await supabase
            .from('driver_profiles')
            .select('license_number, license_url')
            .eq('user_id', userId)
            .maybeSingle();
        carPlateNumberController.text = driverData?['license_number'] as String? ?? '';
        _licensePath = driverData?['license_url'] as String?;
        if (_licensePath != null) {
          licenseUrl = await _storageService.getSignedUrl(
            bucket: 'driver-licenses',
            path: _licensePath!,
          );
        }
        await _localService.cacheDriverLicense(
          userId: userId,
          licenseNumber: carPlateNumberController.text,
          licenseUrl: _licensePath,
        );
      }
    } catch (e) {
      debugPrint('loadProfile failed, falling back to local cache: $e');
      final cached = await _localService.getCachedUserProfile(userId);
      if (cached != null) {
        nameController.text = cached['name'] as String? ?? '';
        phoneController.text = Validators.localDigitsFromStored(cached['phone'] as String?);
        _role = cached['role'] as String? ?? 'passenger';
        _originalRole = _role;
        avatarUrl = cached['avatar_url'] as String?;

        final cachedEmail = cached['email'] as String?;
        final sessionEmail = supabase.auth.currentUser?.email;
        _email = (cachedEmail == null || cachedEmail.endsWith('@placeholder.com'))
            ? sessionEmail ?? cachedEmail
            : cachedEmail;

        if (_role == 'driver') {
          final cachedLicense = await _localService.getCachedDriverLicense(userId);
          carPlateNumberController.text = cachedLicense?['license_number'] as String? ?? '';
          _licensePath = cachedLicense?['license_url'] as String?;
        }
        errorMessage = "Showing your last saved profile — you're offline.";
      } else {
        errorMessage = 'Could not load your profile. Please check your connection.';
      }
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void toggleChangePassword() {
    showChangePassword = !showChangePassword;
    if (!showChangePassword) {
      currentPasswordController.clear();
      newPasswordController.clear();
      confirmPasswordController.clear();
      currentPasswordError = null;
      newPasswordError = null;
      confirmPasswordError = null;
    }
    notifyListeners();
  }

  void toggleObscureCurrentPassword() {
    obscureCurrentPassword = !obscureCurrentPassword;
    notifyListeners();
  }

  void toggleObscureNewPassword() {
    obscureNewPassword = !obscureNewPassword;
    notifyListeners();
  }

  void toggleObscureConfirmPassword() {
    obscureConfirmPassword = !obscureConfirmPassword;
    notifyListeners();
  }

  String? _validateLicenseNumber(String? v) {
    if (_role != 'driver') return null;
    return Validators.carPlateNumber(v);
  }

  bool get _touchingPasswordChange =>
      currentPasswordController.text.isNotEmpty ||
          newPasswordController.text.isNotEmpty ||
          confirmPasswordController.text.isNotEmpty;

  String? _validateCurrentPassword() {
    if (!showChangePassword) return null;
    if (!_touchingPasswordChange) return null;
    if (currentPasswordController.text.isEmpty) return 'Enter your current password';
    return null;
  }

  void _runValidation() {
    nameError = Validators.name(nameController.text);
    phoneError = Validators.phoneLocal(phoneController.text);
    carPlateNumberError = _validateLicenseNumber(carPlateNumberController.text);
    currentPasswordError = _validateCurrentPassword();

    if (!showChangePassword || !_touchingPasswordChange) {
      newPasswordError = null;
      confirmPasswordError = null;
    } else {
      newPasswordError = Validators.password(newPasswordController.text);
      confirmPasswordError = newPasswordError != null
          ? null
          : Validators.confirmPassword(confirmPasswordController.text, newPasswordController.text);
    }
  }

  void revalidateIfNeeded() {
    if (!_autoValidate) return;
    _runValidation();
    notifyListeners();
  }

  void notifyUiOnly() => notifyListeners();

  Future<void> pickAvatar() async {
    if (isOffline) return;
    final bytes = await _storageService.pickImage(source: ImageSource.gallery);
    if (bytes != null) {
      avatarBytes = bytes;
      notifyListeners();
    }
  }

  Future<void> pickLicense() async {
    if (isOffline) return;
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

  String get initials {
    final name = nameController.text.trim();
    if (name.isEmpty) return '?';
    final parts = name.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  String? _storagePathFromPublicUrl(String? publicUrl, String bucket) {
    if (publicUrl == null) return null;
    final marker = '/$bucket/';
    final idx = publicUrl.indexOf(marker);
    if (idx == -1) return null;
    return publicUrl.substring(idx + marker.length);
  }

  Future<ProfileSaveResult> save() async {
    if (isSaving) return ProfileSaveResult.failure;
    if (isOffline) {
      errorMessage = "You're offline — profile changes can't be saved until you reconnect.";
      successMessage = null;
      notifyListeners();
      return ProfileSaveResult.failure;
    }

    _autoValidate = true;
    _runValidation();
    notifyListeners();

    if (nameError != null ||
        phoneError != null ||
        carPlateNumberError != null ||
        currentPasswordError != null ||
        newPasswordError != null ||
        confirmPasswordError != null) {
      return ProfileSaveResult.failure;
    }

    final roleToSave = _originalRole ?? _role;
    if (roleToSave == 'driver' && _licensePath == null && licenseBytes == null) {
      errorMessage = 'Please upload your driving license.';
      notifyListeners();
      return ProfileSaveResult.failure;
    }

    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return ProfileSaveResult.failure;

    isSaving = true;
    errorMessage = null;
    successMessage = null;
    notifyListeners();

    final newPassword = newPasswordController.text;
    final confirmPassword = confirmPasswordController.text;
    final wantsPasswordChange =
        newPassword.isNotEmpty && confirmPassword.isNotEmpty && newPassword == confirmPassword;
    final previousAvatarUrl = avatarUrl;
    final previousLicenseUrl = licenseUrl;
    final previousLicensePath = _licensePath;

    try {
      if (wantsPasswordChange) {
        try {
          await supabase.auth.signInWithPassword(
            email: _email ?? supabase.auth.currentUser?.email ?? '',
            password: currentPasswordController.text,
          );
        } on AuthException catch (e) {
          errorMessage = e.message.contains('Invalid login credentials')
              ? 'Current password is incorrect.'
              : 'Could not verify your current password right now. Please try again.';
          return ProfileSaveResult.failure;
        } catch (_) {
          errorMessage = 'Network error while verifying your password. Please check your connection and try again.';
          return ProfileSaveResult.failure;
        }
      }

      if (wantsPasswordChange) {
        await supabase.auth.updateUser(UserAttributes(password: newPassword));
      }

      if (avatarBytes != null) {
        isUploadingAvatar = true;
        notifyListeners();
        _pendingAvatarFileName = 'avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';
        avatarUrl = await _storageService.uploadUserFile(
          bytes: avatarBytes!,
          bucket: 'profile-photos',
          userId: userId,
          fileName: _pendingAvatarFileName!,
        );
        isUploadingAvatar = false;
      }

      String? pendingLicensePath;
      if (roleToSave == 'driver' && licenseBytes != null) {
        isUploadingLicense = true;
        notifyListeners();
        pendingLicensePath = await _storageService.uploadUserFile(
          bytes: licenseBytes!,
          bucket: 'driver-licenses',
          userId: userId,
          fileName: 'license_${DateTime.now().millisecondsSinceEpoch}.jpg',
          public: false,
        );
        _licensePath = pendingLicensePath;
        licenseUrl = await _storageService.getSignedUrl(
          bucket: 'driver-licenses',
          path: _licensePath!,
        );
        isUploadingLicense = false;
      }

      try {
        await supabase.from('users').upsert({
          'id': userId,
          'name': nameController.text.trim(),
          'phone': Validators.toStoredPhone(phoneController.text),
          'role': roleToSave,
          'avatar_url': avatarUrl,
          'email': _email,
          'updated_at': DateTime.now().toIso8601String(),
        });

        if (roleToSave == 'driver') {
          await supabase.from('driver_profiles').upsert({
            'user_id': userId,
            'license_number': carPlateNumberController.text.trim(),
            'license_url': _licensePath,
          });
        }

      } catch (e) {
        if (_pendingAvatarFileName != null) {
          await _storageService.deleteUserFile(
            bucket: 'profile-photos',
            path: '$userId/$_pendingAvatarFileName',
          );
          _pendingAvatarFileName = null;
          avatarUrl = previousAvatarUrl;
        }
        if (pendingLicensePath != null) {
          await _storageService.deleteUserFile(bucket: 'driver-licenses', path: pendingLicensePath);
          _licensePath = previousLicensePath;
          licenseUrl = previousLicenseUrl;
        }
        rethrow;
      }

      try {
        await _localService.cacheUserProfile(
          userId: userId,
          name: nameController.text.trim(),
          email: _email ?? '',
          phone: Validators.toStoredPhone(phoneController.text),
          role: roleToSave,
          avatarUrl: avatarUrl,
        );
        if (roleToSave == 'driver') {
          await _localService.cacheDriverLicense(
            userId: userId,
            licenseNumber: carPlateNumberController.text.trim(),
            licenseUrl: _licensePath,
          );
        }
      } catch (e) {
        debugPrint('Profile saved to Supabase but failed to update local cache: $e');
      }

      _pendingAvatarFileName = null;
      final didUploadAvatar = avatarBytes != null;
      avatarBytes = null;
      licenseBytes = null;

      if (didUploadAvatar) {
        final oldAvatarPath = _storagePathFromPublicUrl(previousAvatarUrl, 'profile-photos');
        if (oldAvatarPath != null) {
          await _storageService.deleteUserFile(bucket: 'profile-photos', path: oldAvatarPath);
        }
      }
      if (pendingLicensePath != null &&
          previousLicensePath != null &&
          previousLicensePath != pendingLicensePath) {
        await _storageService.deleteUserFile(bucket: 'driver-licenses', path: previousLicensePath);
      }

      currentPasswordController.clear();
      newPasswordController.clear();
      confirmPasswordController.clear();
      showChangePassword = false;

      successMessage = wantsPasswordChange ? 'Password changed.' : 'Profile updated.';
      return ProfileSaveResult.success;
    } on AuthException catch (e) {
      errorMessage = e.message;
      return ProfileSaveResult.failure;
    } catch (e) {
      errorMessage = 'Could not save. Please try again.';
      return ProfileSaveResult.failure;
    } finally {
      isSaving = false;
      isUploadingAvatar = false;
      isUploadingLicense = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await supabase.auth.signOut();
  }
}