import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nak_tumpang/core/services/network_service.dart';
import 'package:nak_tumpang/core/utils/validators.dart';
import 'package:nak_tumpang/features/profile/data/services/profile_local_service.dart';
import 'package:nak_tumpang/features/profile/data/services/profile_storage_service.dart';

/// What the screen should do after [ProfileViewModel.save] returns.
enum ProfileSaveResult {
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
/// Navigation after logout stays in the screen since it needs a
/// BuildContext.
class ProfileViewModel extends ChangeNotifier {
  ProfileViewModel();

  final supabase = Supabase.instance.client;
  final _storageService = ProfileStorageService();
  final _localService = ProfileLocalService();

  final nameController = TextEditingController();
  final phoneController = TextEditingController();
  final licenseNumberController = TextEditingController();
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

  String _role = 'passenger';
  String? _originalRole; // role as loaded from the DB; used to lock edits
  String? _email;

  String get role => _role;

  /// The account's verified email. Read-only here — changing it isn't
  /// supported from the profile screen (Supabase's email-change
  /// confirmation flow needs its own dedicated screen), so it's just
  /// displayed as text under the avatar instead of an editable field.
  String? get email => _email;

  /// True while the device has no connection. Every field on the profile
  /// screen is read-only in that state: saving needs Supabase (the
  /// `users`/`driver_profiles` upserts, Storage uploads, and the
  /// re-authentication a password change does), and there's no
  /// write-behind queue here — so letting someone type a new name or
  /// pick a new avatar offline would only ever end in a failed save with
  /// their edits silently lost against the cached values reloaded next
  /// time. Locking the inputs makes that obvious up front instead.
  bool get isOffline => NetworkService.isOfflineNotifier.value;

  Uint8List? avatarBytes;
  String? avatarUrl;
  bool isUploadingAvatar = false;

  Uint8List? licenseBytes;
  String? licenseUrl;      // signed URL for display only — never save this to DB
  String? _licensePath;    // raw "<userId>/<fileName>" path — this is what gets saved
  bool isUploadingLicense = false;

  // Filename of an avatar upload that's in flight for the current save()
  // call, tracked so a failed DB write can roll back exactly that file —
  // see save().
  String? _pendingAvatarFileName;

  bool isLoading = true;
  bool isSaving = false;
  String? errorMessage;
  String? successMessage;

  bool _autoValidate = false;
  String? nameError;
  String? phoneError;
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

      // Cache what we just fetched so a later loadProfile() can fall
      // back to this if Supabase is unreachable — see the catch below.
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
        await _localService.cacheDriverLicense(
          userId: userId,
          licenseNumber: licenseNumberController.text,
          licenseUrl: _licensePath,
        );
      }
    } catch (e) {
      // Supabase unreachable (offline, DNS failure, etc.) — fall back to
      // whatever was cached from the last successful load, so the
      // screen shows the driver's last-known profile instead of a blank
      // or crashed one.
      debugPrint('loadProfile failed, falling back to local cache: $e');
      final cached = await _localService.getCachedUserProfile(userId);
      if (cached != null) {
        nameController.text = cached['name'] as String? ?? '';
        phoneController.text = Validators.localDigitsFromStored(cached['phone'] as String?);
        _role = cached['role'] as String? ?? 'passenger';
        _originalRole = _role;
        avatarUrl = cached['avatar_url'] as String?;
        // The signed-in session (and its email) is persisted by
        // supabase_flutter and readable offline, so prefer it over the
        // cached `users.email`: HomeLocalService has to write *some*
        // address into that NOT NULL column when it seeds the row, and
        // older installs have a synthetic "<uuid>@placeholder.com"
        // sitting there — which is what made the profile screen show a
        // user id instead of an email offline.
        final cachedEmail = cached['email'] as String?;
        final sessionEmail = supabase.auth.currentUser?.email;
        _email = (cachedEmail == null || cachedEmail.endsWith('@placeholder.com'))
            ? sessionEmail ?? cachedEmail
            : cachedEmail;

        if (_role == 'driver') {
          final cachedLicense = await _localService.getCachedDriverLicense(userId);
          licenseNumberController.text = cachedLicense?['license_number'] as String? ?? '';
          _licensePath = cachedLicense?['license_url'] as String?;
          // Signed URLs are short-lived and Storage isn't reachable
          // right now anyway, so there's no photo to show offline —
          // the license number still displays.
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

  /// Whether the driver is actually attempting a password change — any
  /// of the three password fields having content counts, not just "New
  /// Password". Using only newPasswordController here was the bug: a
  /// driver who typed something into "Confirm New Password" but left
  /// "New Password" blank saw no error on either field (newPasswordError
  /// is optional, and confirmPassword's own optional check only looks at
  /// whether *new* password is empty) and the button appeared to save
  /// successfully — but wantsPasswordChange being keyed on the same
  /// empty field meant no password update was ever actually sent.
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
    licenseNumberError = _validateLicenseNumber(licenseNumberController.text);
    currentPasswordError = _validateCurrentPassword();

    if (!showChangePassword || !_touchingPasswordChange) {
      newPasswordError = null;
      confirmPasswordError = null;
    } else {
      newPasswordError = Validators.password(newPasswordController.text);
      // Only check the match once New Password itself is valid — surfacing
      // "Passwords do not match" or "Please confirm your password" on top
      // of an already-flagged, empty/invalid New Password field is just a
      // second, confusing error pointing at the same missing field.
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

  /// Call after any change that affects the live avatar initials (name)
  /// or other derived display state, so the screen rebuilds.
  void notifyUiOnly() => notifyListeners();

  Future<void> pickAvatar() async {
    if (isOffline) return; // locked — see [isOffline]
    final bytes = await _storageService.pickImage(source: ImageSource.gallery);
    if (bytes != null) {
      avatarBytes = bytes;
      notifyListeners();
    }
  }

  Future<void> pickLicense() async {
    if (isOffline) return; // locked — see [isOffline]
    final bytes = await _storageService.pickImage(source: ImageSource.gallery);
    if (bytes == null) return;

    // Client-side check first — cheap, instant, and catches the "wrong
    // file"/corrupted cases before spending any time uploading.
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

  /// avatar_url is stored as a full public Storage URL (see
  /// ProfileStorageService.uploadUserFile), but deleting a file needs
  /// the bare "<userId>/<fileName>" path — pulls that back out of the
  /// URL so the old avatar can be cleaned up after a successful save.
  String? _storagePathFromPublicUrl(String? publicUrl, String bucket) {
    if (publicUrl == null) return null;
    final marker = '/$bucket/';
    final idx = publicUrl.indexOf(marker);
    if (idx == -1) return null;
    return publicUrl.substring(idx + marker.length);
  }

  Future<ProfileSaveResult> save() async {
    // Guards against a second call landing while one is already in
    // flight (e.g. a double-tap before the UI rebuilds with isSaving
    // disabling the button) — this can upload files and touch two
    // tables, so don't rely on the button's disabled state alone.
    if (isSaving) return ProfileSaveResult.failure;

    // Same reasoning as [isOffline], enforced here as well as in the UI:
    // the screen disables its fields and button, but this is the only
    // check that still holds if the connection drops between the tap
    // and this call.
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
        licenseNumberError != null ||
        currentPasswordError != null ||
        newPasswordError != null ||
        confirmPasswordError != null) {
      return ProfileSaveResult.failure;
    }

    // Role is only ever set at registration. Ignore whatever is in
    // `_role` here and use the role already on file, so it can never be
    // switched later from this screen.
    final roleToSave = _originalRole ?? _role;

    // Driver must have a license photo on file (either already uploaded,
    // or picked just now) before they can continue. Check _licensePath,
    // not licenseUrl — licenseUrl is just the signed display URL, which
    // is null whenever it was loaded from the offline cache (no
    // network to sign it), even though a license is genuinely on file.
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

    // Explicit and self-contained rather than relying on the validation
    // pass above having already guaranteed this: a password change only
    // ever proceeds when New Password AND Confirm New Password are both
    // filled in and match exactly. (This used to key off New Password
    // alone, which meant — depending on validation order — a change
    // could go through with only one of the two fields actually filled
    // in. Checking both directly here removes that dependency.)
    final newPassword = newPasswordController.text;
    final confirmPassword = confirmPasswordController.text;
    final wantsPasswordChange =
        newPassword.isNotEmpty && confirmPassword.isNotEmpty && newPassword == confirmPassword;
    final previousAvatarUrl = avatarUrl;
    final previousLicenseUrl = licenseUrl;
    final previousLicensePath = _licensePath;

    try {
      // Supabase has no separate "verify this password" call, so a
      // password change re-authenticates with the current password
      // first — that doubles as the check the reviewer asked for.
      if (wantsPasswordChange) {
        try {
          await supabase.auth.signInWithPassword(
            email: _email ?? supabase.auth.currentUser?.email ?? '',
            password: currentPasswordController.text,
          );
        } on AuthException catch (e) {
          // Only report "incorrect password" for the specific error
          // Supabase returns for a wrong password. Rate limiting, a
          // temporary outage, etc. throw AuthException too, but telling
          // the driver their password is wrong when it might not be is
          // misleading — give those their own message instead.
          errorMessage = e.message.contains('Invalid login credentials')
              ? 'Current password is incorrect.'
              : 'Could not verify your current password right now. Please try again.';
          return ProfileSaveResult.failure;
        } catch (_) {
          // Non-auth failures here (no network, DNS, etc.) shouldn't be
          // reported as a wrong password either.
          errorMessage = 'Network error while verifying your password. Please check your connection and try again.';
          return ProfileSaveResult.failure;
        }
      }

      // Email is read-only here — it's shown as plain text, not an
      // editable field. Changing the account's verified email needs its
      // own confirmation-aware flow, so that's intentionally not wired
      // up from this screen.

      if (wantsPasswordChange) {
        await supabase.auth.updateUser(UserAttributes(password: newPassword));
      }

      if (avatarBytes != null) {
        isUploadingAvatar = true;
        notifyListeners();
        // Unique filename per upload (rather than a fixed 'avatar.jpg')
        // so a rollback below can remove *this* upload specifically if
        // the DB write fails, without ever touching the file the
        // previous avatar_url still points at.
        _pendingAvatarFileName = 'avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';
        avatarUrl = await _storageService.uploadUserFile(
          bytes: avatarBytes!,
          bucket: 'avatars',
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
        // Also refresh the signed URL so it displays immediately after save,
        // without needing another round trip to loadProfile().
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

      } catch (e) {
        // Neither DB write can be trusted to have committed (upsert
        // isn't itself transactional across the two calls), so roll
        // back any file uploaded *in this attempt* — the previous
        // avatar/license, if any, was never touched and is still what
        // the (unsaved) DB row points to.
        if (_pendingAvatarFileName != null) {
          await _storageService.deleteUserFile(
            bucket: 'avatars',
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

      // Both Supabase writes have committed by this point — mirror them
      // into the local cache so an offline loadProfile() afterward
      // reflects this save. This is deliberately its own try/catch,
      // outside the rollback scope above: a SQLite-only failure here
      // must never delete the avatar/license Supabase already committed
      // to, or report a successful remote save as failed.
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
            licenseNumber: licenseNumberController.text.trim(),
            licenseUrl: _licensePath,
          );
        }
      } catch (e) {
        debugPrint('Profile saved to Supabase but failed to update local cache: $e');
      }

      _pendingAvatarFileName = null;
      // Captured before clearing avatarBytes below — the old-file
      // cleanup a few lines down needs to know whether this save
      // uploaded a new avatar, and avatarBytes itself won't say that
      // anymore once it's null.
      final didUploadAvatar = avatarBytes != null;
      // Committed — the DB row now points at the uploaded file(s), so
      // drop the in-memory copies. Without this, saving again in the
      // same screen session (e.g. after just editing the name) would
      // re-upload the same avatar/license under a new filename and
      // delete the file this save just committed, for no reason.
      avatarBytes = null;
      licenseBytes = null;

      // The new file(s) are now safely referenced by the DB row that
      // just committed — the previous avatar/license (if this save
      // replaced one) is no longer pointed at by anything, so it's safe
      // to remove now. Done last, after commit, and best-effort: unlike
      // the rollback above, a failure here just leaves one harmless
      // unreferenced old file instead of risking new data.
      if (didUploadAvatar) {
        final oldAvatarPath = _storagePathFromPublicUrl(previousAvatarUrl, 'avatars');
        if (oldAvatarPath != null) {
          await _storageService.deleteUserFile(bucket: 'avatars', path: oldAvatarPath);
        }
      }
      if (pendingLicensePath != null &&
          previousLicensePath != null &&
          previousLicensePath != pendingLicensePath) {
        await _storageService.deleteUserFile(bucket: 'driver-licenses', path: previousLicensePath);
      }

      // Password fields are never pre-filled from stored data, so clear
      // them (and collapse the section) after a successful save rather
      // than leaving them sitting in the form.
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