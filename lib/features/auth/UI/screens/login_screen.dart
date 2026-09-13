import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nak_tumpang/features/home/UI/screens/home_screen.dart';
import 'package:nak_tumpang/features/profile/UI/components/role_selection_dialog.dart';
import 'package:nak_tumpang/features/profile/UI/screens/register_screen.dart';
import 'package:nak_tumpang/features/auth/view_models/login_view_model.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => LoginViewModel(),
      child: const _LoginView(),
    );
  }
}

class _LoginView extends StatefulWidget {
  const _LoginView();

  @override
  State<_LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<_LoginView> {
  bool _isHoveringRegister = false;

  Future<void> _submit(LoginViewModel vm) async {
    final success = await vm.submit();
    if (!mounted || !success) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  void _startRegister() async {
    final role = await RoleSelectionDialog.show(context);
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RegisterScreen(initialRole: role)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<LoginViewModel>();

    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Logo
                Center(
                  child: Image.asset(
                    'assets/launch_app_logo.png',
                    width: 100,
                    height: 100,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 20),

                // Title
                Text(
                  'Nak',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.primaryYellow,
                    fontWeight: FontWeight.bold,
                    fontSize: 32,
                  ),
                ),
                Text(
                  'Tumpang',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 32,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tumpang Senang, Sampai Je Senang',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.greyText, fontSize: 13),
                ),
                const SizedBox(height: 36),

                // Email
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

                // Password
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

                if (vm.errorMessage != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    vm.errorMessage!,
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                ],

                const SizedBox(height: 28),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryYellow,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: vm.isLoading ? null : () => _submit(vm),
                    child: vm.isLoading
                        ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                        : const Text(
                      'Log In',
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  onEnter: (_) => setState(() => _isHoveringRegister = true),
                  onExit: (_) => setState(() => _isHoveringRegister = false),
                  child: GestureDetector(
                    onTap: vm.isLoading ? null : _startRegister,
                    child: Column(
                      children: [
                        Text('New here?', style: TextStyle(color: AppColors.greyText, fontSize: 12)),
                        AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 150),
                          style: TextStyle(
                            color: _isHoveringRegister ? AppColors.greyText : AppColors.primaryYellow,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          child: const Text('Tap to create an account'),
                        ),
                      ],
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

  /// Renders a validation error flush-left, aligned with the field's
  /// label and box edge above it. Returns an empty (zero-height) widget
  /// when there's no error, so nothing shifts when errors appear/disappear.
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
