import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nak_tumpang/core/utils/validators.dart';
import 'package:nak_tumpang/features/profile/data/services/profile_storage_service.dart';

/// What the screen should do after [ProfileViewModel.save] returns.
enum ProfileSaveResult {
  /// First-time setup is done — move on into the app.
  firstTimeSetupComplete,

  /// Saved; [ProfileViewModel.successMessage] has the message to show.
  success,

  /// Didn't save; [ProfileViewModel.errorMessage] (or a per-field error)
  /// has the reason.
  failure,
}

/// Holds all state and logic for the profile / edit-profile screen. The
/// screen only reads state from here and calls into it — Supabase calls,
/// validation, and file uploads all live here instead of the widget.
///
/// Dialogs and navigation (the first-time role picker, routing after
/// save/logout) stay in the screen since they need a BuildContext.
class ProfileViewModel extends ChangeNotifier {
  final bool isFirstTimeSetup;

  ProfileViewModel({required this.isFirstTimeSetup});

  final supabase = Supabase.instance.client;
  final _storageService = ProfileStorageService();

  final nameController = TextEditingController();
  final phoneController = TextEditingController();
  final licenseNumberController = TextEditingController();
  final emailController = TextEditingController();
  final currentPasswordController = TextEditingController();
  final newPasswordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  final phoneFocusNode = FocusNode();

  bool obscureCurrentPassword = true;
  bool obscureNewPassword = true;
  bool obscureConfirmPassword = true;

  /// Whether the current/new/confirm password fields are expanded. Starts
  /// collapsed behind a "Change Password" link so the section doesn't
  /// look like it's always demanding a password change.
  bool showChangePassword = false;

  // Driving license numbers don't follow one official public format the
  // way the IC does, so this is a light sanity check rather than a strict
  // pattern: letters, digits, spaces and dashes only, no emoji/junk paste.
  final _licenseNumberRegex = RegExp(r'^[A-Z0-9](?:[A-Z0-9\s-]*[A-Z0-9])?$');

  String _role = 'passenger';
  String? _originalRole; // role as loaded from the DB; used to lock edits
  String? _email;

  String get role => _role;

  Uint8List? avatarBytes;
  String? avatarUrl;
  bool isUploadingAvatar = false;

  Uint8List? licenseBytes;
  String? licenseUrl;      // signed URL for display only — never save this to DB
  String? _licensePath;    // raw "<userId>/<fileName>" path — this is what gets saved
  bool isUploadingLicense = false;

  bool isLoading = true;
  bool isSaving = false;
  String? errorMessage;
  String? successMessage;

  // Profile/Route tab (drivers only) — 'profile' or 'route'.
  String activeTab = 'profile';
  List<Map<String, dynamic>> driverTrips = [];
  bool isLoadingRoutes = false;
  bool _routesLoaded = false;

  bool _autoValidate = false;
  String? nameError;
  String? phoneError;
  String? emailError;
  String? licenseNumberError;
  String? currentPasswordError;
  String? newPasswordError;
  String? confirmPasswordError;

  @override
  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    phoneFocusNode.dispose();
    licenseNumberController.dispose();
    emailController.dispose();
    currentPasswordController.dispose();
    newPasswordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  /// Loads the signed-in user's profile row. Doesn't show the first-time
  /// Passenger/Driver dialog itself (that needs a BuildContext) — the
  /// screen awaits this, then shows the dialog and calls [setRole].
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
      emailController.text = _email ?? '';

      // License number/photo live on driver_profiles, not users — only
      // drivers have a row there, so only look it up for drivers.
      if (_role == 'driver') {
        final driverData = await supabase
            .from('driver_profiles')
            .select('license_number, license_url')
            .eq('user_id', userId)
            .maybeSingle();
        licenseNumberController.text = driverData?['license_number'] as String? ?? '';
        _licensePath = driverData?['license_url'] as String?;
        if (_licensePath != null) {
          licenseUrl = await _storageService.getSignedUrl(
            bucket: 'driver-licenses',
            path: _licensePath!,
          );
        }
      }
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void setRole(String role) {
    _role = role;
    notifyListeners();
  }

  /// Switches between the 'profile' and 'route' tabs (drivers only).
  /// Lazily loads the driver's saved routes the first time 'route' is
  /// opened, so passengers/first-load never pay for a query they won't
  /// use.
  Future<void> setTab(String tab) async {
    activeTab = tab;
    notifyListeners();
    if (tab == 'route' && !_routesLoaded) {
      await loadDriverRoutes();
    }
  }

  Future<void> loadDriverRoutes() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    isLoadingRoutes = true;
    notifyListeners();
    try {
      final rows = await supabase.from('driver_trips').select().eq('user_id', userId);
      driverTrips = List<Map<String, dynamic>>.from(rows);
      _routesLoaded = true;
    } catch (e) {
      debugPrint('Failed to load driver routes: $e');
    } finally {
      isLoadingRoutes = false;
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
    final trimmed = v?.trim() ?? '';
    if (trimmed.isEmpty) return 'Driving license number is required';
    if (trimmed.length < 4) return 'Please enter a valid driver license number';
    if (!_licenseNumberRegex.hasMatch(trimmed)) {
      return 'Letters, numbers, spaces and dashes only';
    }
    return null;
  }

  String? _validateCurrentPassword() {
    if (!showChangePassword) return null;
    if (newPasswordController.text.isEmpty && confirmPasswordController.text.isEmpty) {
      return null;
    }
    if (currentPasswordController.text.isEmpty) return 'Enter your current password';
    return null;
  }

  void _runValidation() {
    nameError = Validators.name(nameController.text);
    phoneError = Validators.phoneLocal(phoneController.text);
    emailError = Validators.email(emailController.text);
    licenseNumberError = _validateLicenseNumber(licenseNumberController.text);
    currentPasswordError = _validateCurrentPassword();
    newPasswordError = Validators.password(newPasswordController.text, optional: true);
    confirmPasswordError = Validators.confirmPassword(
      confirmPasswordController.text,
      newPasswordController.text,
      optional: true,
    );
  }

  void revalidateIfNeeded() {
    if (!_autoValidate) return;
    _runValidation();
    notifyListeners();
  }

  /// Call after any change that affects the live avatar initials (name)
  /// or other derived display state, so the screen rebuilds.
  void notifyUiOnly() => notifyListeners();

  Future<void> pickAvatar() async {
    final bytes = await _storageService.pickImage(source: ImageSource.gallery);
    if (bytes != null) {
      avatarBytes = bytes;
      notifyListeners();
    }
  }

  Future<void> pickLicense() async {
    final bytes = await _storageService.pickImage(source: ImageSource.gallery);
    if (bytes != null) {
      licenseBytes = bytes;
      notifyListeners();
    }
  }

  String get initials {
    final name = nameController.text.trim();
    if (name.isEmpty) return '?';
    final parts = name.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  Future<ProfileSaveResult> save() async {
    _autoValidate = true;
    _runValidation();
    notifyListeners();

    if (nameError != null ||
        phoneError != null ||
        emailError != null ||
        licenseNumberError != null ||
        currentPasswordError != null ||
        newPasswordError != null ||
        confirmPasswordError != null) {
      return ProfileSaveResult.failure;
    }

    // Role is only settable during first-time setup (via the dialog/
    // dropdown). On every later save, ignore whatever is in `_role` and
    // use the role already on file, so it can never be switched later.
    final roleToSave = isFirstTimeSetup ? _role : (_originalRole ?? _role);

    // Driver must have a license photo on file (either already uploaded,
    // or picked just now) before they can continue.
    if (roleToSave == 'driver' && licenseUrl == null && licenseBytes == null) {
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

    final wantsPasswordChange = newPasswordController.text.isNotEmpty;

    try {
      // Supabase has no separate "verify this password" call, so a
      // password change re-authenticates with the current password
      // first — that doubles as the check the reviewer asked for.
      if (wantsPasswordChange) {
        try {
          await supabase.auth.signInWithPassword(
            email: _email ?? emailController.text.trim(),
            password: currentPasswordController.text,
          );
        } on AuthException {
          errorMessage = 'Current password is incorrect.';
          return ProfileSaveResult.failure;
        }
      }

      // Email/password live on the auth user, not the `users` table, so
      // they're updated via Supabase Auth first. A changed email triggers
      // Supabase's own confirmation flow (a link sent to the new address);
      // the change only takes effect once that's clicked.
      final newEmail = emailController.text.trim();
      final emailChanged = newEmail.isNotEmpty && newEmail != (_email ?? '');
      if (emailChanged) {
        await supabase.auth.updateUser(UserAttributes(email: newEmail));
      }

      if (wantsPasswordChange) {
        await supabase.auth.updateUser(UserAttributes(password: newPasswordController.text));
      }

      if (avatarBytes != null) {
        isUploadingAvatar = true;
        notifyListeners();
        avatarUrl = await _storageService.uploadUserFile(
          bytes: avatarBytes!,
          bucket: 'avatars',
          userId: userId,
          fileName: 'avatar.jpg',
        );
        isUploadingAvatar = false;
      }

      if (roleToSave == 'driver' && licenseBytes != null) {
        isUploadingLicense = true;
        notifyListeners();
        _licensePath = await _storageService.uploadUserFile(
          bytes: licenseBytes!,
          bucket: 'driver-licenses',
          userId: userId,
          fileName: 'license.jpg',
          public: false,
        );
        // Also refresh the signed URL so it displays immediately after save,
        // without needing another round trip to loadProfile().
        licenseUrl = await _storageService.getSignedUrl(
          bucket: 'driver-licenses',
          path: _licensePath!,
        );
        isUploadingLicense = false;
      }

      await supabase.from('users').upsert({
        'id': userId,
        'name': nameController.text.trim(),
        'phone': Validators.toStoredPhone(phoneController.text),
        'role': roleToSave,
        'avatar_url': avatarUrl,
        'email': _email ?? newEmail,
        'updated_at': DateTime.now().toIso8601String(),
      });

      // License number/photo live on driver_profiles now. Only touch
      // those two columns here — never total_earnings/available_balance/
      // total_withdrawn, since this upsert must not reset a driver's
      // wallet back to zero on an unrelated profile edit.
      if (roleToSave == 'driver') {
        await supabase.from('driver_profiles').upsert({
          'user_id': userId,
          'license_number': licenseNumberController.text.trim(),
          'license_url': _licensePath,
        });
      }

      // Password fields are never pre-filled from stored data, so clear
      // them (and collapse the section) after a successful save rather
      // than leaving them sitting in the form.
      currentPasswordController.clear();
      newPasswordController.clear();
      confirmPasswordController.clear();
      showChangePassword = false;

      if (isFirstTimeSetup) {
        return ProfileSaveResult.firstTimeSetupComplete;
      }

      if (wantsPasswordChange && emailChanged) {
        successMessage = 'Password changed. Check your new email to confirm the change.';
      } else if (wantsPasswordChange) {
        successMessage = 'Password changed.';
      } else if (emailChanged) {
        successMessage = 'Profile updated. Check your new email to confirm the change.';
      } else {
        successMessage = 'Profile updated.';
      }
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