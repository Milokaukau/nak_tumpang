import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nak_tumpang/features/auth/UI/screens/login_screen.dart';
import 'package:nak_tumpang/features/home/UI/screens/home_screen.dart';
import 'package:nak_tumpang/features/profile/UI/components/role_selection_dialog.dart';
import 'package:nak_tumpang/features/profile/data/services/profile_storage_service.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/core/utils/validators.dart';

class ProfileScreen extends StatefulWidget {
  /// When true, this screen is shown right after a brand-new sign-up
  /// so the user can fill in their details for the first time.
  final bool isFirstTimeSetup;

  const ProfileScreen({super.key, this.isFirstTimeSetup = false});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _licenseNumberController = TextEditingController();
  final _emailController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _icController = TextEditingController();
  final _phoneFocusNode = FocusNode();

  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;

  // Driving license numbers don't follow one official public format the
  // way the IC does, so this is a light sanity check rather than a strict
  // pattern: letters, digits, spaces and dashes only, no emoji/junk paste.
  final _licenseNumberRegex = RegExp(r'^[A-Z0-9](?:[A-Z0-9\s-]*[A-Z0-9])?$');

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

  void _revalidateIfNeeded() {
    if (!_autoValidate) return;
    setState(() {
      _nameError = Validators.name(_nameController.text);
      _phoneError = Validators.phoneLocal(_phoneController.text);
      _emailError = Validators.email(_emailController.text);
      _licenseNumberError = _validateLicenseNumber(_licenseNumberController.text);
      _newPasswordError = Validators.password(_newPasswordController.text, optional: true);
      _confirmPasswordError = Validators.confirmPassword(
        _confirmPasswordController.text,
        _newPasswordController.text,
        optional: true,
      );
    });
  }

  final _storageService = ProfileStorageService();

  String _role = 'passenger';
  String? _originalRole; // role as loaded from the DB; used to lock edits
  String? _email;
  String? _icNumber; // set once at registration, shown read-only here

  Uint8List? _avatarBytes;
  String? _avatarUrl;
  bool _isUploadingAvatar = false;
  bool _isHoveringAvatar = false;

  Uint8List? _licenseBytes;
  String? _licenseUrl;
  bool _isUploadingLicense = false;

  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;
  String? _successMessage;

  bool _autoValidate = false;
  String? _nameError;
  String? _phoneError;
  String? _emailError;
  String? _licenseNumberError;
  String? _newPasswordError;
  String? _confirmPasswordError;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _phoneFocusNode.dispose();
    _licenseNumberController.dispose();
    _emailController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _icController.dispose();
    super.dispose();
  }

  String _formatIC(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length != 12) return digits; // fallback, don't crash on bad data
    return '${digits.substring(0, 6)}-${digits.substring(6, 8)}-${digits.substring(8, 12)}';
  }

  Future<void> _loadProfile() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final data = await supabase
          .from('users')
          .select()
          .eq('id', userId)
          .single();

      // debugPrint('Loaded user profile row');

      setState(() {
        _nameController.text = data['name'] ?? '';
        _phoneController.text = Validators.localDigitsFromStored(data['phone']);
        _licenseNumberController.text = data['license_number'] ?? '';
        _role = data['role'] ?? 'passenger';
        _originalRole = data['role'] as String?;
        _email = data['email'] ?? supabase.auth.currentUser?.email;
        _emailController.text = _email ?? '';
        _icNumber = data['ic_number'] as String?;
        _icController.text = _formatIC(_icNumber);
        _avatarUrl = data['avatar_url'] as String?;
        _licenseUrl = data['license_url'] as String?;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _email = supabase.auth.currentUser?.email;
        _emailController.text = _email ?? '';
        _isLoading = false;
      });
    }

    // Brand-new account -> ask Passenger or Driver before they fill in
    // the rest, same as before this was wired up.
    if (widget.isFirstTimeSetup && mounted) {
      final role = await RoleSelectionDialog.show(context);
      if (mounted) setState(() => _role = role);
    }
  }

  Future<void> _pickAvatar() async {
    final bytes = await _storageService.pickImage(source: ImageSource.gallery);
    if (bytes != null) setState(() => _avatarBytes = bytes);
  }

  Future<void> _pickLicense() async {
    final bytes = await _storageService.pickImage(source: ImageSource.gallery);
    if (bytes != null) setState(() => _licenseBytes = bytes);
  }

  Future<void> _saveProfile() async {
    setState(() {
      _autoValidate = true;
      _nameError = Validators.name(_nameController.text);
      _phoneError = Validators.phoneLocal(_phoneController.text);
      _emailError = Validators.email(_emailController.text);
      _licenseNumberError = _validateLicenseNumber(_licenseNumberController.text);
      _newPasswordError = Validators.password(_newPasswordController.text, optional: true);
      _confirmPasswordError = Validators.confirmPassword(
        _confirmPasswordController.text,
        _newPasswordController.text,
        optional: true,
      );
    });

    if (_nameError != null ||
        _phoneError != null ||
        _emailError != null ||
        _licenseNumberError != null ||
        _newPasswordError != null ||
        _confirmPasswordError != null) {
      return;
    }

    // Role is only settable during first-time setup (via the dropdown
    // above, which mirrors the Passenger/Driver dialog). On every later
    // save, ignore whatever is in `_role` and use the role already on
    // file, so it can never be switched after the account is created.
    final roleToSave = widget.isFirstTimeSetup ? _role : (_originalRole ?? _role);

    // Driver must have a license photo on file (either already uploaded,
    // or picked just now) before they can continue.
    if (roleToSave == 'driver' && _licenseUrl == null && _licenseBytes == null) {
      setState(() => _errorMessage = 'Please upload your driving license.');
      return;
    }

    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      // Email/password live on the auth user, not the `users` table, so
      // they're updated via Supabase Auth first. A changed email triggers
      // Supabase's own confirmation flow (a link sent to the new address);
      // the change only takes effect once that's clicked.
      final newEmail = _emailController.text.trim();
      final emailChanged = newEmail.isNotEmpty && newEmail != (_email ?? '');
      if (emailChanged) {
        await supabase.auth.updateUser(UserAttributes(email: newEmail));
      }

      final newPassword = _newPasswordController.text;
      if (newPassword.isNotEmpty) {
        await supabase.auth.updateUser(UserAttributes(password: newPassword));
      }

      if (_avatarBytes != null) {
        setState(() => _isUploadingAvatar = true);
        _avatarUrl = await _storageService.uploadUserFile(
          bytes: _avatarBytes!,
          bucket: 'avatars',
          userId: userId,
          fileName: 'avatar.jpg',
        );
        setState(() => _isUploadingAvatar = false);
      }

      if (roleToSave == 'driver' && _licenseBytes != null) {
        setState(() => _isUploadingLicense = true);
        _licenseUrl = await _storageService.uploadUserFile(
          bytes: _licenseBytes!,
          bucket: 'driver-licenses',
          userId: userId,
          fileName: 'license.jpg',
          public: false,
        );
        setState(() => _isUploadingLicense = false);
      }

      await supabase.from('users').update({
        'name': _nameController.text.trim(),
        'phone': Validators.toStoredPhone(_phoneController.text),
        'role': roleToSave,
        'avatar_url': _avatarUrl,
        // Left as the current (confirmed) email even if a change was just
        // requested — it only actually changes once the confirmation
        // link is clicked, at which point this gets synced on next load.
        'email': _email ?? newEmail,
        'license_number': roleToSave == 'driver' ? _licenseNumberController.text.trim() : null,
        'license_url': roleToSave == 'driver' ? _licenseUrl : null,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', userId);

      // Password fields are never pre-filled from stored data, so clear
      // them after a successful save rather than leaving them sitting
      // in the form.
      _newPasswordController.clear();
      _confirmPasswordController.clear();

      if (!mounted) return;

      if (widget.isFirstTimeSetup) {
        // First-time setup complete -> continue into the app.
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      } else {
        setState(() => _successMessage = emailChanged
            ? 'Profile updated. Check your new email to confirm the change.'
            : 'Profile updated.');
      }
    } on AuthException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (e) {
      setState(() => _errorMessage = 'Could not save. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _isUploadingAvatar = false;
          _isUploadingLicense = false;
        });
      }
    }
  }

  Future<void> _logout() async {
    await supabase.auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
    );
  }

  String get _initials {
    final name = _nameController.text.trim();
    if (name.isEmpty) return '?';
    final parts = name.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        title: Text(
          widget.isFirstTimeSetup ? 'Complete your profile' : 'My Profile',
        ),
        automaticallyImplyLeading: !widget.isFirstTimeSetup,
        actions: [
          if (!widget.isFirstTimeSetup)
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Log out',
              onPressed: _logout,
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Avatar - tap to pick a photo, falls back to initials
                Center(
                  child: MouseRegion(
                    cursor: _isUploadingAvatar
                        ? SystemMouseCursors.basic
                        : SystemMouseCursors.click,
                    onEnter: (_) => setState(() => _isHoveringAvatar = true),
                    onExit: (_) => setState(() => _isHoveringAvatar = false),
                    child: GestureDetector(
                      onTap: _isUploadingAvatar ? null : _pickAvatar,
                      child: Stack(
                        children: [
                          CircleAvatar(
                            radius: 44,
                            backgroundColor: AppColors.primaryYellow,
                            backgroundImage: _avatarBytes != null
                                ? MemoryImage(_avatarBytes!)
                                : (_avatarUrl != null
                                ? NetworkImage(_avatarUrl!) as ImageProvider
                                : null),
                            child: _isUploadingAvatar
                                ? const CircularProgressIndicator(color: Colors.white)
                                : (_avatarBytes == null && _avatarUrl == null)
                                ? Text(
                              _initials,
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            )
                                : null,
                          ),
                          // Gray shade over the avatar, shown only on hover
                          // to signal that it's tappable.
                          Positioned.fill(
                            child: IgnorePointer(
                              child: AnimatedOpacity(
                                opacity: _isHoveringAvatar ? 1 : 0,
                                duration: const Duration(milliseconds: 150),
                                child: CircleAvatar(
                                  radius: 44,
                                  backgroundColor: Colors.black.withValues(alpha: 0.35),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: CircleAvatar(
                              radius: 14,
                              backgroundColor: AppColors.black,
                              child: Icon(Icons.camera_alt, size: 14, color: AppColors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // Name
                Text('Full Name (as per IC)', style: TextStyle(color: AppColors.greyText, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: _nameController,
                  decoration: _fieldDecoration(),
                  onChanged: (_) {
                    setState(() {}); // updates avatar initials live
                    _revalidateIfNeeded();
                  },
                ),
                _errorText(_nameError),
                const SizedBox(height: 18),

                // IC number - set at registration, locked here so it can
                // never drift from the identity used to register the account.
                if (_icNumber != null) ...[
                  Text('IC number', style: TextStyle(color: AppColors.greyText, fontSize: 13)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _icController,
                    enabled: false,
                    decoration: _fieldDecoration(),
                  ),
                  const SizedBox(height: 18),
                ],

                // Phone
                Text('Phone Number', style: TextStyle(color: AppColors.greyText, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: _phoneController,
                  focusNode: _phoneFocusNode,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(11),
                  ],
                  decoration: _fieldDecoration(hint: '0123456789').copyWith(
                    prefixText: '+60  ',
                    prefixStyle: TextStyle(color: AppColors.greyText, fontWeight: FontWeight.w500),
                  ),
                  onChanged: (_) {
                    setState(() {}); // updates avatar initials live
                    _revalidateIfNeeded();
                  }
                ),
                _errorText(_nameError),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Enter your number starting with 01, e.g. 0123456789',
                    style: TextStyle(color: AppColors.greyText, fontSize: 11),
                  ),
                ),
                const SizedBox(height: 18),

                // Email — editable, but Supabase Auth only applies the
                // change once the confirmation link sent to the new
                // address is clicked.
                Text('Email', style: TextStyle(color: AppColors.greyText, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: _fieldDecoration(hint: 'e.g. name@example.com'),
                    onChanged: (_) {
                      setState(() {}); // updates avatar initials live
                      _revalidateIfNeeded();
                    }
                ),
                _errorText(_emailError),
                const SizedBox(height: 18),

                // Role — chosen once via the Passenger/Driver dialog right
                // after sign-up and locked in afterwards. Editable here only
                // during first-time setup, before the account is saved; once
                // saved it's shown read-only so it can't be switched later.
                Text('I am a', style: TextStyle(color: AppColors.greyText, fontSize: 13)),
                const SizedBox(height: 6),
                if (widget.isFirstTimeSetup)
                  DropdownButtonFormField<String>(
                    initialValue: _role,
                    decoration: _fieldDecoration(),
                    items: const [
                      DropdownMenuItem(value: 'passenger', child: Text('Passenger')),
                      DropdownMenuItem(value: 'driver', child: Text('Driver')),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _role = value);
                    },
                  )
                else
                  TextFormField(
                    initialValue: _role == 'driver' ? 'Driver' : 'Passenger',
                    enabled: false,
                    decoration: _fieldDecoration(),
                  ),

                // Driving license - drivers only
                if (_role == 'driver') ...[
                  const SizedBox(height: 18),
                  Text('Driving License Number', style: TextStyle(color: AppColors.greyText, fontSize: 13)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _licenseNumberController,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [
                      UpperCaseTextFormatter(),
                      LengthLimitingTextInputFormatter(20),
                    ],
                    decoration: _fieldDecoration(hint: 'e.g. D1234567', hintColor: Colors.grey),
                      onChanged: (_) {
                        setState(() {}); // updates avatar initials live
                        _revalidateIfNeeded();
                      }
                  ),
                  const SizedBox(height: 18),

                  Text('Driving License Photo', style: TextStyle(color: AppColors.greyText, fontSize: 13)),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: _isUploadingLicense ? null : _pickLicense,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      height: 140,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.greyBorder),
                      ),
                      child: _isUploadingLicense
                          ? const Center(child: CircularProgressIndicator())
                          : _licenseBytes != null
                          ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(_licenseBytes!, fit: BoxFit.cover, width: double.infinity),
                      )
                          : _licenseUrl != null
                          ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(_licenseUrl!, fit: BoxFit.cover, width: double.infinity),
                      )
                          : Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.upload_file, color: AppColors.greyText),
                            const SizedBox(height: 6),
                            Text(
                              'Tap to upload your driving license',
                              style: TextStyle(color: AppColors.greyText, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],

                // Change password — optional, both fields left blank
                // leaves the current password untouched.
                if (!widget.isFirstTimeSetup) ...[
                  const SizedBox(height: 18),
                  Text('Change Password', style: TextStyle(color: AppColors.greyText, fontSize: 13)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _newPasswordController,
                    obscureText: _obscureNewPassword,
                    decoration: _fieldDecoration(hint: 'Leave blank to keep current password').copyWith(
                      suffixIcon: IconButton(
                        icon: Icon(_obscureNewPassword ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _obscureNewPassword = !_obscureNewPassword),
                      ),
                    ),
                      onChanged: (_) {
                        setState(() {}); // updates avatar initials live
                        _revalidateIfNeeded();
                      }
                  ),
                  _errorText(_newPasswordError),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'At least 6 characters, with a letter and a number',
                      style: TextStyle(color: AppColors.greyText, fontSize: 11),
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextFormField(
                    controller: _confirmPasswordController,
                    obscureText: _obscureConfirmPassword,
                    decoration: _fieldDecoration(hint: 'Confirm new password').copyWith(
                      suffixIcon: IconButton(
                        icon: Icon(_obscureConfirmPassword ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                      ),
                    ),
                    validator: (v) => Validators.confirmPassword(
                      v,
                      _newPasswordController.text,
                      optional: true,
                    ),
                      onChanged: (_) {
                        setState(() {}); // updates avatar initials live
                        _revalidateIfNeeded();
                      }
                  ),
                  _errorText(_confirmPasswordError),
                ],

                if (_errorMessage != null) ...[
                  const SizedBox(height: 14),
                  Text(_errorMessage!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
                ],
                if (_successMessage != null) ...[
                  const SizedBox(height: 14),
                  Text(_successMessage!, style: const TextStyle(color: Colors.green), textAlign: TextAlign.center),
                ],

                const SizedBox(height: 28),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryYellow,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: _isSaving ? null : _saveProfile,
                    child: _isSaving
                        ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                        : Text(
                      widget.isFirstTimeSetup ? 'Continue' : 'Save Changes',
                      style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration({String? hint, Color? hintColor}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: hintColor ?? AppColors.greyText.withValues(alpha: 0.6)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: AppColors.greyBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: AppColors.greyBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: AppColors.primaryYellow, width: 1.5),
      ),
    );
  }
}

Widget _errorText(String? error) {
  if (error == null) return const SizedBox.shrink();
  return Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Text(
      error,
      style: const TextStyle(color: Colors.red, fontSize: 12),
    ),
  );
}
/// Uppercases text as the user types, so driving license numbers are
/// stored and compared consistently (e.g. "d1234567" -> "D1234567").
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}