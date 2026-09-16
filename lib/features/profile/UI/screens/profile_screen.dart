import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:nak_tumpang/core/components/base_button.dart';
import 'package:nak_tumpang/core/services/network_service.dart';
import 'package:nak_tumpang/features/auth/UI/screens/login_screen.dart';
import 'package:nak_tumpang/features/profile/view_models/profile_view_model.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ProfileViewModel(),
      child: const _ProfileView(),
    );
  }

}

class _ProfileView extends StatefulWidget {
  const _ProfileView();

  @override
  State<_ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<_ProfileView> {
  bool _isHoveringAvatar = false;

  // Set to whatever avatarUrl last failed to load, so the CircleAvatar
  // below can fall back to initials for that specific URL instead of
  // retrying it forever — but still attempts a *different* URL (e.g.
  // after picking a new avatar, or after loadProfile() re-fetches a
  // fresh signed one) since only that exact failed value is excluded.
  String? _failedAvatarUrl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialLoad());
  }

  Future<void> _initialLoad() async {
    final vm = context.read<ProfileViewModel>();
    await vm.loadProfile();
  }

  Future<void> _save(ProfileViewModel vm) async {
    await vm.save();
  }

  Future<void> _logout(ProfileViewModel vm) async {
    await vm.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ProfileViewModel>();

    if (vm.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Rebuilds the whole form the moment connectivity flips, so the
    // fields lock/unlock immediately instead of only after the next
    // notifyListeners() from the view model.
    return ValueListenableBuilder<bool>(
      valueListenable: NetworkService.isOfflineNotifier,
      builder: (context, isOffline, _) => _buildForm(context, vm, isOffline),
    );
  }

  Widget _buildForm(BuildContext context, ProfileViewModel vm, bool locked) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        title: const Text('My Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Log out',
            onPressed: () => _logout(vm),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Avatar - tap to pick a photo, falls back to initials
                    Center(
                      child: MouseRegion(
                        cursor: (vm.isUploadingAvatar || locked)
                            ? SystemMouseCursors.basic
                            : SystemMouseCursors.click,
                        onEnter: locked ? null : (_) => setState(() => _isHoveringAvatar = true),
                        onExit: locked ? null : (_) => setState(() => _isHoveringAvatar = false),
                        child: GestureDetector(
                          onTap: (vm.isUploadingAvatar || locked) ? null : vm.pickAvatar,
                          child: Stack(
                            children: [
                              Builder(builder: (context) {
                                final networkUrl = vm.avatarBytes == null &&
                                    vm.avatarUrl != null &&
                                    vm.avatarUrl != _failedAvatarUrl
                                    ? vm.avatarUrl
                                    : null;
                                final ImageProvider? avatarImage = vm.avatarBytes != null
                                    ? MemoryImage(vm.avatarBytes!)
                                    : (networkUrl != null ? NetworkImage(networkUrl) : null);

                                return CircleAvatar(
                                  radius: 44,
                                  backgroundColor: AppColors.primaryYellow,
                                  backgroundImage: avatarImage,
                                  // A stale/expired avatar URL (e.g. the
                                  // bucket file was removed, or the URL
                                  // is otherwise no longer valid) should
                                  // fall back to initials instead of
                                  // just failing silently with no image
                                  // and no child shown.
                                  onBackgroundImageError: avatarImage is NetworkImage
                                      ? (_, __) {
                                    if (!mounted) return;
                                    setState(() => _failedAvatarUrl = vm.avatarUrl);
                                  }
                                      : null,
                                  child: vm.isUploadingAvatar
                                      ? const CircularProgressIndicator(color: Colors.white)
                                      : avatarImage == null
                                      ? Text(
                                    vm.initials,
                                    style: const TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  )
                                      : null,
                                );
                              }),
                              // Gray shade over the avatar, shown only on hover
                              // to signal that it's tappable.
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: AnimatedOpacity(
                                    opacity: (_isHoveringAvatar && !locked) ? 1 : 0,
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
                    if (vm.email != null) ...[
                      const SizedBox(height: 10),
                      Center(
                        child: Text(
                          vm.email!,
                          style: TextStyle(color: AppColors.greyText, fontSize: 13),
                        ),
                      ),
                    ],
                    if (locked) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.greyBorder),
                          color: AppColors.lightYellow.withValues(alpha: 0.5),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.wifi_off, size: 16, color: AppColors.greyText),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                "You're offline. This is your last saved profile — editing is "
                                    'locked until you reconnect.',
                                style: TextStyle(color: AppColors.greyText, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 28),

                    // Name
                    Text('Full Name', style: TextStyle(color: AppColors.greyText, fontSize: 13)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: vm.nameController,
                      enabled: !locked,
                      decoration: _fieldDecoration(locked: locked),
                      onChanged: (_) {
                        vm.notifyUiOnly(); // updates avatar initials live
                        vm.revalidateIfNeeded();
                      },
                    ),
                    _errorText(vm.nameError),
                    const SizedBox(height: 18),

                    // Phone — the +60 prefix is a fixed Text widget outside the
                    // TextField (not InputDecoration.prefixText), so it's always
                    // visible instead of only appearing once the field is
                    // focused or has content.
                    Text('Phone Number', style: TextStyle(color: AppColors.greyText, fontSize: 13)),
                    const SizedBox(height: 6),
                    AnimatedBuilder(
                      animation: vm.phoneFocusNode,
                      builder: (context, child) {
                        return Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            // Matches the greyed fill the other fields
                            // get from _fieldDecoration when locked —
                            // this one draws its own border/background
                            // because of the fixed "+60" prefix.
                            color: locked ? AppColors.greyBorder.withValues(alpha: 0.18) : null,
                            border: Border.all(
                              color: vm.phoneError != null
                                  ? Colors.red
                                  : (vm.phoneFocusNode.hasFocus
                                  ? AppColors.primaryYellow
                                  : AppColors.greyBorder),
                              width: (vm.phoneError != null || vm.phoneFocusNode.hasFocus) ? 1.5 : 1,
                            ),
                          ),
                          child: child,
                        );
                      },
                      child: Row(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(left: 14),
                            child: Text(
                              '+60',
                              style: TextStyle(color: AppColors.greyText, fontWeight: FontWeight.w500),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: TextField(
                              controller: vm.phoneController,
                              focusNode: vm.phoneFocusNode,
                              enabled: !locked,
                              keyboardType: TextInputType.phone,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(9),
                              ],
                              style: TextStyle(color: AppColors.black),
                              decoration: InputDecoration(
                                hintText: '123456789',
                                hintStyle: TextStyle(color: AppColors.greyText.withValues(alpha: 0.5)),
                                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                              ),
                              onChanged: (_) {
                                vm.notifyUiOnly(); // updates avatar initials live
                                vm.revalidateIfNeeded();
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                      ),
                    ),
                    _errorText(vm.phoneError),
                    const SizedBox(height: 18),

                    // Role — chosen once via the Passenger/Driver dialog on
                    // the register screen, and never editable from here.
                    Text('I am a', style: TextStyle(color: AppColors.greyText, fontSize: 13)),
                    const SizedBox(height: 6),
                    // Locked — the only place the role is ever actually
                    // chosen is at registration. This is a plain pill
                    // rather than a dropdown/text field so nothing on this
                    // screen suggests it can be tapped and changed.
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.greyBorder),
                        color: AppColors.lightYellow.withValues(alpha: 0.5),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            vm.role == 'driver' ? Icons.directions_car : Icons.person,
                            size: 18,
                            color: AppColors.black,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            vm.role == 'driver' ? 'Driver' : 'Passenger',
                            style: TextStyle(color: AppColors.black, fontWeight: FontWeight.w600),
                          ),
                          const Spacer(),
                          Icon(Icons.lock_outline, size: 16, color: AppColors.greyText),
                        ],
                      ),
                    ),

                    // Driving license - drivers only
                    if (vm.role == 'driver') ...[
                      const SizedBox(height: 18),
                      Text('Car Plate Number', style: TextStyle(color: AppColors.greyText, fontSize: 13)),
                      const SizedBox(height: 6),
                      TextField(
                          controller: vm.carPlateNumberController,
                          enabled: !locked,
                          textCapitalization: TextCapitalization.characters,
                          inputFormatters: [
                            UpperCaseTextFormatter(),
                            LengthLimitingTextInputFormatter(20),
                          ],
                          decoration: _fieldDecoration(hint: 'e.g. D1234567', hintColor: Colors.grey, locked: locked),
                          onChanged: (_) {
                            vm.notifyUiOnly();
                            vm.revalidateIfNeeded();
                          }
                      ),
                      _errorText(vm.carPlateNumberError),
                      const SizedBox(height: 18),

                      Text('Driving License Photo', style: TextStyle(color: AppColors.greyText, fontSize: 13)),
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: (vm.isUploadingLicense || locked) ? null : vm.pickLicense,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          height: 140,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.greyBorder),
                          ),
                          child: Stack(
                            children: [
                              if (vm.isUploadingLicense)
                                const Center(child: CircularProgressIndicator())
                              else if (vm.licenseBytes != null)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.memory(vm.licenseBytes!, fit: BoxFit.cover, width: double.infinity, height: double.infinity),
                                )
                              else if (vm.licenseUrl != null)
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(
                                      vm.licenseUrl!,
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                      height: double.infinity,
                                      // The signed URL expires after 1 hour
                                      // (ProfileStorageService.getSignedUrl) —
                                      // if this screen was left open that
                                      // long, or the network just failed,
                                      // show a clear message instead of
                                      // Flutter's default broken-image icon.
                                      errorBuilder: (context, error, stackTrace) => Center(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.refresh, color: AppColors.greyText),
                                            const SizedBox(height: 6),
                                            Text(
                                              'Could not load preview. Reopen this screen to refresh it.',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(color: AppColors.greyText, fontSize: 11),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  )
                                else
                                  Center(
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
                            ],
                          ),
                        ),
                      ),
                    ],

                    // Change password — collapsed by default behind a link, so
                    // opening it up is a deliberate action. Once open, the
                    // current password is required before a new one is accepted.
                    const SizedBox(height: 18),
                    if (!vm.showChangePassword)
                      InkWell(
                        onTap: locked ? null : vm.toggleChangePassword,
                        borderRadius: BorderRadius.circular(4),
                        child: Row(
                          children: [
                            Icon(Icons.lock_reset, size: 18, color: AppColors.primaryYellow),
                            const SizedBox(width: 8),
                            Text(
                              'Change Password',
                              style: TextStyle(
                                color: AppColors.primaryYellow,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      )
                    else ...[
                      Row(
                        children: [
                          Text('Change Password', style: TextStyle(color: AppColors.greyText, fontSize: 13)),
                          const Spacer(),
                          InkWell(
                            onTap: vm.toggleChangePassword,
                            child: Text(
                              'Cancel',
                              style: TextStyle(
                                color: AppColors.greyText,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      Text('Current Password', style: TextStyle(color: AppColors.greyText, fontSize: 12)),
                      const SizedBox(height: 4),
                      TextField(
                        controller: vm.currentPasswordController,
                        enabled: !locked,
                        obscureText: vm.obscureCurrentPassword,
                        decoration: _fieldDecoration(hint: 'Your current password', locked: locked).copyWith(
                          suffixIcon: IconButton(
                            icon: Icon(vm.obscureCurrentPassword ? Icons.visibility_off : Icons.visibility),
                            onPressed: vm.toggleObscureCurrentPassword,
                          ),
                        ),
                        onChanged: (_) => vm.revalidateIfNeeded(),
                      ),
                      _errorText(vm.currentPasswordError),
                      const SizedBox(height: 14),

                      Text('New Password', style: TextStyle(color: AppColors.greyText, fontSize: 12)),
                      const SizedBox(height: 4),
                      TextField(
                        controller: vm.newPasswordController,
                        enabled: !locked,
                        obscureText: vm.obscureNewPassword,
                        decoration: _fieldDecoration(hint: 'New password', locked: locked).copyWith(
                          suffixIcon: IconButton(
                            icon: Icon(vm.obscureNewPassword ? Icons.visibility_off : Icons.visibility),
                            onPressed: vm.toggleObscureNewPassword,
                          ),
                        ),
                        onChanged: (_) => vm.revalidateIfNeeded(),
                      ),
                      _errorText(vm.newPasswordError),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'At least 6 characters, with a lowercase letter, an uppercase letter, a number and a special character',
                          style: TextStyle(color: AppColors.greyText, fontSize: 11),
                        ),
                      ),
                      const SizedBox(height: 14),

                      Text('Confirm New Password', style: TextStyle(color: AppColors.greyText, fontSize: 12)),
                      const SizedBox(height: 4),
                      TextField(
                        controller: vm.confirmPasswordController,
                        enabled: !locked,
                        obscureText: vm.obscureConfirmPassword,
                        decoration: _fieldDecoration(hint: 'Re-enter new password', locked: locked).copyWith(
                          suffixIcon: IconButton(
                            icon: Icon(vm.obscureConfirmPassword ? Icons.visibility_off : Icons.visibility),
                            onPressed: vm.toggleObscureConfirmPassword,
                          ),
                        ),
                        onChanged: (_) => vm.revalidateIfNeeded(),
                      ),
                      _errorText(vm.confirmPasswordError),
                    ],

                    if (vm.errorMessage != null) ...[
                      const SizedBox(height: 14),
                      Text(vm.errorMessage!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
                    ],
                    if (vm.successMessage != null) ...[
                      const SizedBox(height: 14),
                      Text(vm.successMessage!, style: const TextStyle(color: Colors.green), textAlign: TextAlign.center),
                    ],

                    const SizedBox(height: 28),
                    BaseButton(
                      text: locked ? 'Offline — editing locked' : 'Save Changes',
                      height: 48,
                      isLoading: vm.isSaving,
                      textStyle: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                      // Null disables the button outright rather than
                      // letting a tap through to a save that can only fail.
                      onPressed: locked ? null : () => _save(vm),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration({String? hint, Color? hintColor, bool locked = false}) {
    return InputDecoration(
      hintText: hint,
      // Greyed fill while offline, so a locked field reads as locked at a
      // glance and not just as an ordinary field that won't accept taps.
      filled: locked,
      fillColor: locked ? AppColors.greyBorder.withValues(alpha: 0.18) : null,
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: AppColors.greyBorder),
      ),
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