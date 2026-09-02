import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/core/utils/ic_no_formatter.dart';
import 'package:nak_tumpang/features/profile/UI/screens/profile_screen.dart';
import 'package:nak_tumpang/features/profile/view_models/register_view_model.dart';

class RegisterScreen extends StatelessWidget {
  const RegisterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => RegisterViewModel(),
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
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => const ProfileScreen(isFirstTimeSetup: true),
      ),
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
              Text('Full Name (as per IC)', style: TextStyle(color: AppColors.greyText, fontSize: 13)),
              const SizedBox(height: 6),
              TextField(
                controller: vm.nameController,
                textCapitalization: TextCapitalization.words,
                decoration: _fieldDecoration(),
                onChanged: (_) => vm.revalidateIfNeeded(),
              ),
              _errorText(vm.nameError),
              const SizedBox(height: 18),

              Text('IC Number', style: TextStyle(color: AppColors.greyText, fontSize: 13)),
              const SizedBox(height: 6),
              TextField(
                controller: vm.icController,
                keyboardType: TextInputType.number,
                inputFormatters: [MalaysianICInputFormatter()],
                decoration: _fieldDecoration().copyWith(
                  hintText: '990101-14-5678',
                  hintStyle: TextStyle(color: AppColors.greyText.withValues(alpha: 0.6)),
                ),
                onChanged: (_) => vm.revalidateIfNeeded(),
              ),
              _errorText(vm.icError),
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
                  'At least 6 characters, with a letter and a number',
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
                    'Create Account',
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
