import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/features/home/UI/screens/home_screen.dart';
import 'package:nak_tumpang/features/profile/UI/components/get_started_dialog.dart';
import 'package:nak_tumpang/features/profile/UI/screens/post_signup_driver_screen.dart';
import 'package:nak_tumpang/features/profile/UI/screens/profile_screen.dart' show UpperCaseTextFormatter;
import 'package:nak_tumpang/features/profile/view_models/register_view_model.dart';

class RegisterScreen extends StatelessWidget {
  // role can still be changed before submitting
  final String initialRole;

  const RegisterScreen({super.key, this.initialRole = 'passenger'});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => RegisterViewModel(initialRole: initialRole),
      child: const _RegisterView(),
    );
  }
}

class _RegisterView extends StatefulWidget {
  const _RegisterView();

  @override
  State<_RegisterView> createState() => _RegisterViewState();
}

class _RegisterViewState extends State<_RegisterView> {
  Future<void> _register(RegisterViewModel vm) async {
    final success = await vm.submit();
    if (!mounted || !success) return;

    // Account exists at this point — show the "Let's get started!"
    // popup so they can optionally add a trip now.
    final choice = await GetStartedDialog.show(context);
    if (!mounted) return;

    if (choice == 'add_trip' && vm.role == 'driver') {
      // Land on Home first (replacing RegisterScreen, whose only path
      // back is LoginScreen — confusing to land on once already
      // registered and signed in), then push the route-setup screen on
      // top of it. That way the back stack is [Home, PostSignupDriver],
      // so backing out of route setup lands on Home instead of Login.
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PostSignupDriverScreen(
          userId: vm.registeredUserId!,
        )),
      );
      return;
    }

    // 'later', or a passenger choosing 'add_trip' — the real passenger
    // add-trip flow doesn't exist yet, so fall through to home for now.
    // TODO: once the real add-trip screen exists, push into that flow
    // instead of the home page placeholder.
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<RegisterViewModel>();

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        title: const Text('Create Account'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('I am a...', style: TextStyle(color: AppColors.greyText, fontSize: 13)),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: _RoleToggleButton(
                      label: 'Driver',
                      selected: vm.role == 'driver',
                      onTap: () => vm.setRole('driver'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _RoleToggleButton(
                      label: 'Passenger',
                      selected: vm.role == 'passenger',
                      onTap: () => vm.setRole('passenger'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.info_outline, size: 14, color: AppColors.greyText),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      "You can't change this after your account is created.",
                      style: TextStyle(color: AppColors.greyText, fontSize: 11.5),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              Text('Full Name', style: TextStyle(color: AppColors.greyText, fontSize: 13)),
              const SizedBox(height: 6),
              TextField(
                controller: vm.nameController,
                textCapitalization: TextCapitalization.words,
                decoration: _fieldDecoration(),
                onChanged: (_) => vm.revalidateIfNeeded(),
              ),
              _errorText(vm.nameError),
              const SizedBox(height: 18),

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
                        onChanged: (_) => vm.revalidateIfNeeded(),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
              _errorText(vm.phoneError),
              const SizedBox(height: 18),

              Text('Email', style: TextStyle(color: AppColors.greyText, fontSize: 13)),
              const SizedBox(height: 6),
              TextField(
                controller: vm.emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: _fieldDecoration(),
                onChanged: (_) => vm.revalidateIfNeeded(),
              ),
              _errorText(vm.emailError),
              const SizedBox(height: 18),

              Text('Password', style: TextStyle(color: AppColors.greyText, fontSize: 13)),
              const SizedBox(height: 6),
              TextField(
                controller: vm.passwordController,
                obscureText: vm.obscurePassword,
                decoration: _fieldDecoration(
                  suffixIcon: IconButton(
                    icon: Icon(
                      vm.obscurePassword ? Icons.visibility_off : Icons.visibility,
                      color: AppColors.greyText,
                      size: 20,
                    ),
                    onPressed: vm.toggleObscurePassword,
                  ),
                ),
                onChanged: (_) => vm.revalidateIfNeeded(),
              ),
              _errorText(vm.passwordError),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'At least 6 characters, with an uppercase letter, a number and a special character',
                  style: TextStyle(color: AppColors.greyText, fontSize: 11),
                ),
              ),
              const SizedBox(height: 18),

              Text('Confirm Password', style: TextStyle(color: AppColors.greyText, fontSize: 13)),
              const SizedBox(height: 6),
              TextField(
                controller: vm.confirmPasswordController,
                obscureText: vm.obscureConfirmPassword,
                decoration: _fieldDecoration(
                  suffixIcon: IconButton(
                    icon: Icon(
                      vm.obscureConfirmPassword ? Icons.visibility_off : Icons.visibility,
                      color: AppColors.greyText,
                      size: 20,
                    ),
                    onPressed: vm.toggleObscureConfirmPassword,
                  ),
                ),
                onChanged: (_) => vm.revalidateIfNeeded(),
              ),
              _errorText(vm.confirmError),

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
                  decoration: _fieldDecoration().copyWith(
                    hintText: 'e.g. D1234567',
                    hintStyle: TextStyle(color: AppColors.greyText.withValues(alpha: 0.5)),
                  ),
                  onChanged: (_) => vm.revalidateIfNeeded(),
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
                    child: Stack(
                      children: [
                        if (vm.isUploadingLicense)
                          const Center(child: CircularProgressIndicator())
                        else if (vm.licenseBytes != null)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.memory(vm.licenseBytes!, fit: BoxFit.cover, width: double.infinity, height: double.infinity),
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
                _errorText(vm.licenseError),
              ],

              if (vm.errorMessage != null) ...[
                const SizedBox(height: 16),
                Text(vm.errorMessage!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
              ],

              const SizedBox(height: 28),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryYellow,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: vm.isLoading ? null : () => _register(vm),
                  child: vm.isLoading
                      ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                      : const Text(
                    'Complete',
                    style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // error messages aligned left to the box edge
  // no changes if no error
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

  InputDecoration _fieldDecoration({Widget? suffixIcon}) {
    return InputDecoration(
      suffixIcon: suffixIcon,
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

class _RoleToggleButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _RoleToggleButton({required this.label, required this.selected, required this.onTap});

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