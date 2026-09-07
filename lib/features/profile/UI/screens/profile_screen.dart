import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:nak_tumpang/core/components/base_button.dart';
import 'package:nak_tumpang/features/auth/UI/screens/login_screen.dart';
import 'package:nak_tumpang/features/home/UI/screens/home_screen.dart';
import 'package:nak_tumpang/features/profile/UI/components/role_selection_dialog.dart';
import 'package:nak_tumpang/features/profile/view_models/profile_view_model.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';

class ProfileScreen extends StatelessWidget {
  /// When true, this screen is shown right after a brand-new sign-up
  /// so the user can fill in their details for the first time.
  final bool isFirstTimeSetup;

  const ProfileScreen({super.key, this.isFirstTimeSetup = false});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ProfileViewModel(isFirstTimeSetup: isFirstTimeSetup),
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialLoad());
  }

  Future<void> _initialLoad() async {
    final vm = context.read<ProfileViewModel>();
    await vm.loadProfile();

    // Brand-new account -> ask Passenger or Driver before they fill in
    // the rest. Shown here (not in the view model) since it needs a
    // BuildContext.
    if (vm.isFirstTimeSetup && mounted) {
      final role = await RoleSelectionDialog.show(context);
      if (mounted) vm.setRole(role ?? 'passenger');
    }
  }

  Future<void> _save(ProfileViewModel vm) async {
    final result = await vm.save();
    if (!mounted) return;
    if (result == ProfileSaveResult.firstTimeSetupComplete) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    }
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

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        title: Text(
          vm.isFirstTimeSetup ? 'Complete your profile' : 'My Profile',
        ),
        automaticallyImplyLeading: !vm.isFirstTimeSetup,
        actions: [
          if (!vm.isFirstTimeSetup)
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
            if (vm.role == 'driver' && !vm.isFirstTimeSetup)
              _ProfileRouteTabBar(
                activeTab: vm.activeTab,
                onChanged: (tab) => vm.setTab(tab),
              ),
            Expanded(
              child: (vm.role == 'driver' && !vm.isFirstTimeSetup && vm.activeTab == 'route')
                  ? _RouteTabView(vm: vm)
                  : SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Avatar - tap to pick a photo, falls back to initials
                    Center(
                      child: MouseRegion(
                        cursor: vm.isUploadingAvatar
                            ? SystemMouseCursors.basic
                            : SystemMouseCursors.click,
                        onEnter: (_) => setState(() => _isHoveringAvatar = true),
                        onExit: (_) => setState(() => _isHoveringAvatar = false),
                        child: GestureDetector(
                          onTap: vm.isUploadingAvatar ? null : vm.pickAvatar,
                          child: Stack(
                            children: [
                              CircleAvatar(
                                radius: 44,
                                backgroundColor: AppColors.primaryYellow,
                                backgroundImage: vm.avatarBytes != null
                                    ? MemoryImage(vm.avatarBytes!)
                                    : (vm.avatarUrl != null
                                    ? NetworkImage(vm.avatarUrl!) as ImageProvider
                                    : null),
                                child: vm.isUploadingAvatar
                                    ? const CircularProgressIndicator(color: Colors.white)
                                    : (vm.avatarBytes == null && vm.avatarUrl == null)
                                    ? Text(
                                  vm.initials,
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
                    if (vm.email != null) ...[
                      const SizedBox(height: 10),
                      Center(
                        child: Text(
                          vm.email!,
                          style: TextStyle(color: AppColors.greyText, fontSize: 13),
                        ),
                      ),
                    ],
                    const SizedBox(height: 28),

                    // Name
                    Text('Full Name', style: TextStyle(color: AppColors.greyText, fontSize: 13)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: vm.nameController,
                      decoration: _fieldDecoration(),
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

                    // Role — chosen once via the Passenger/Driver dialog right
                    // after sign-up and locked in afterwards. Editable here only
                    // during first-time setup, before the account is saved; once
                    // saved it's shown read-only so it can't be switched later.
                    Text('I am a', style: TextStyle(color: AppColors.greyText, fontSize: 13)),
                    const SizedBox(height: 6),
                    if (vm.isFirstTimeSetup)
                      DropdownButtonFormField<String>(
                        initialValue: vm.role,
                        decoration: _fieldDecoration(),
                        items: const [
                          DropdownMenuItem(value: 'passenger', child: Text('Passenger')),
                          DropdownMenuItem(value: 'driver', child: Text('Driver')),
                        ],
                        onChanged: (value) {
                          if (value != null) vm.setRole(value);
                        },
                      )
                    else
                    // Read-only after signup, so this is a plain locked pill
                    // rather than a text field the user might think they can
                    // edit — with darker text to stay legible.
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
                      Text('Driving License Number', style: TextStyle(color: AppColors.greyText, fontSize: 13)),
                      const SizedBox(height: 6),
                      TextField(
                          controller: vm.licenseNumberController,
                          textCapitalization: TextCapitalization.characters,
                          inputFormatters: [
                            UpperCaseTextFormatter(),
                            LengthLimitingTextInputFormatter(20),
                          ],
                          decoration: _fieldDecoration(hint: 'e.g. D1234567', hintColor: Colors.grey),
                          onChanged: (_) {
                            vm.notifyUiOnly();
                            vm.revalidateIfNeeded();
                          }
                      ),
                      _errorText(vm.licenseNumberError),
                      const SizedBox(height: 18),

                      Text('Driving License Photo', style: TextStyle(color: AppColors.greyText, fontSize: 13)),
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: vm.isUploadingLicense ? null : vm.pickLicense,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          height: 140,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.greyBorder),
                          ),
                          child: vm.isUploadingLicense
                              ? const Center(child: CircularProgressIndicator())
                              : vm.licenseBytes != null
                              ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.memory(vm.licenseBytes!, fit: BoxFit.cover, width: double.infinity),
                          )
                              : vm.licenseUrl != null
                              ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(vm.licenseUrl!, fit: BoxFit.cover, width: double.infinity),
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

                    // Change password — collapsed by default behind a link, so
                    // opening it up is a deliberate action. Once open, the
                    // current password is required before a new one is accepted.
                    if (!vm.isFirstTimeSetup) ...[
                      const SizedBox(height: 18),
                      if (!vm.showChangePassword)
                        InkWell(
                          onTap: vm.toggleChangePassword,
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
                          obscureText: vm.obscureCurrentPassword,
                          decoration: _fieldDecoration(hint: 'Your current password').copyWith(
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
                          obscureText: vm.obscureNewPassword,
                          decoration: _fieldDecoration(hint: 'New password').copyWith(
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
                            'At least 6 characters, with a letter and a number',
                            style: TextStyle(color: AppColors.greyText, fontSize: 11),
                          ),
                        ),
                        const SizedBox(height: 14),

                        Text('Confirm New Password', style: TextStyle(color: AppColors.greyText, fontSize: 12)),
                        const SizedBox(height: 4),
                        TextField(
                          controller: vm.confirmPasswordController,
                          obscureText: vm.obscureConfirmPassword,
                          decoration: _fieldDecoration(hint: 'Re-enter new password').copyWith(
                            suffixIcon: IconButton(
                              icon: Icon(vm.obscureConfirmPassword ? Icons.visibility_off : Icons.visibility),
                              onPressed: vm.toggleObscureConfirmPassword,
                            ),
                          ),
                          onChanged: (_) => vm.revalidateIfNeeded(),
                        ),
                        _errorText(vm.confirmPasswordError),
                      ],
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
                      text: vm.isFirstTimeSetup ? 'Continue' : 'Save Changes',
                      height: 48,
                      isLoading: vm.isSaving,
                      textStyle: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                      onPressed: () => _save(vm),
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

/// Profile / Route segmented toggle shown at the top of a driver's own
/// profile page — Profile shows the editable fields already on this
/// screen, Route shows the driving route(s) they set up earlier.
class _ProfileRouteTabBar extends StatelessWidget {
  final String activeTab;
  final ValueChanged<String> onChanged;

  const _ProfileRouteTabBar({required this.activeTab, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      child: Row(
        children: [
          Expanded(
            child: _TabButton(
              label: 'Profile',
              selected: activeTab == 'profile',
              onTap: () => onChanged('profile'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _TabButton(
              label: 'Route',
              selected: activeTab == 'route',
              onTap: () => onChanged('route'),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TabButton({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryYellow : AppColors.white,
          border: Border.all(color: selected ? AppColors.primaryYellow : AppColors.greyBorder),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: selected ? AppColors.black : AppColors.greyText,
          ),
        ),
      ),
    );
  }
}

/// Shows the driving route(s) a driver entered on the post-signup screen
/// — read-only for now, pulled straight from `driver_trips`.
class _RouteTabView extends StatelessWidget {
  final ProfileViewModel vm;

  const _RouteTabView({required this.vm});

  static const _dayKeys = [
    'active_monday',
    'active_tuesday',
    'active_wednesday',
    'active_thursday',
    'active_friday',
    'active_saturday',
    'active_sunday',
  ];
  static const _shortDayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  /// Turns the 7 active_* booleans back into a compact label — a
  /// contiguous range like "Mon - Fri" when possible (matching how
  /// PostSignupDriverViewModel writes them), otherwise a comma list.
  String _formatActiveDays(Map<String, dynamic> trip) {
    final active = List<bool>.generate(7, (i) => trip[_dayKeys[i]] == true);
    final activeCount = active.where((a) => a).length;
    if (activeCount == 7) return 'Every day';
    if (activeCount == 0) return 'No days set';

    for (int start = 0; start < 7; start++) {
      if (!active[start]) continue;
      bool isContiguousRun = true;
      for (int i = 0; i < activeCount; i++) {
        if (!active[(start + i) % 7]) {
          isContiguousRun = false;
          break;
        }
      }
      if (isContiguousRun) {
        final end = (start + activeCount - 1) % 7;
        return activeCount == 1
            ? _shortDayNames[start]
            : '${_shortDayNames[start]} - ${_shortDayNames[end]}';
      }
    }

    return [for (int i = 0; i < 7; i++) if (active[i]) _shortDayNames[i]].join(', ');
  }

  String _formatTime(dynamic raw) {
    // Stored as "HH:mm:ss" — show it as "HH:mm".
    final s = raw as String? ?? '';
    return s.length >= 5 ? s.substring(0, 5) : s;
  }

  @override
  Widget build(BuildContext context) {
    if (vm.isLoadingRoutes) {
      return const Center(child: CircularProgressIndicator());
    }

    if (vm.driverTrips.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            "You haven't set up a route yet.",
            style: TextStyle(color: AppColors.greyText),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: vm.loadDriverRoutes,
      child: ListView.builder(
        padding: const EdgeInsets.all(24),
        itemCount: vm.driverTrips.length,
        itemBuilder: (context, i) {
          final trip = vm.driverTrips[i];
          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.greyBorder),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.route, size: 18, color: AppColors.primaryYellow),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        (trip['trip_name'] as String?) ??
                            '${trip['depart_name']} → ${trip['arrival_name']}',
                        style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.black),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _RouteInfoRow(
                  icon: Icons.calendar_today,
                  text: 'Every ${_formatActiveDays(trip)}',
                ),
                const SizedBox(height: 6),
                _RouteInfoRow(
                  icon: Icons.schedule,
                  text: 'Depart ${_formatTime(trip['depart_time'])} · '
                      'Arrive ${_formatTime(trip['arrival_time'])}',
                ),
                const SizedBox(height: 6),
                _RouteInfoRow(
                  icon: Icons.place_outlined,
                  text: '${trip['depart_name']} → ${trip['arrival_name']}',
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _RouteInfoRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _RouteInfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.greyText),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: TextStyle(color: AppColors.greyText, fontSize: 13)),
        ),
      ],
    );
  }
}