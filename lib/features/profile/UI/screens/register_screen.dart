import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/core/utils/ic_no_formatter.dart';
import 'package:nak_tumpang/core/utils/validators.dart';
import 'package:nak_tumpang/features/profile/UI/screens/profile_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameController = TextEditingController();
  final _icController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _phoneFocusNode = FocusNode();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;
  bool _autoValidate = false;
  String? _errorMessage;
  String? _nameError;

  String? _icError;
  String? _phoneError;
  String? _emailError;
  String? _passwordError;
  String? _confirmError;

  final supabase = Supabase.instance.client;

  @override
  void dispose() {
    _nameController.dispose();
    _icController.dispose();
    _phoneController.dispose();
    _phoneFocusNode.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  String? _validateName(String? v) => Validators.name(v);

  String? _validateIC(String? v) => Validators.ic(v);

  String? _validatePhone(String? v) => Validators.phoneLocal(v);

  String? _validateEmail(String? v) => Validators.email(v);

  String? _validatePassword(String? v) => Validators.password(v);

  String? _validateConfirmPassword(String? v) =>
      Validators.confirmPassword(v, _passwordController.text);

  void _revalidateIfNeeded() {
    if (!_autoValidate) return;
    setState(() {
      _nameError = _validateName(_nameController.text);
      _icError = _validateIC(_icController.text);
      _phoneError = _validatePhone(_phoneController.text);
      _emailError = _validateEmail(_emailController.text);
      _passwordError = _validatePassword(_passwordController.text);
      _confirmError = _validateConfirmPassword(_confirmPasswordController.text);
    });
  }

  Future<void> _register() async {
    setState(() {
      _autoValidate = true;
      _nameError = _validateName(_nameController.text);
      _icError = _validateIC(_icController.text);
      _phoneError = _validatePhone(_phoneController.text);
      _emailError = _validateEmail(_emailController.text);
      _passwordError = _validatePassword(_passwordController.text);
      _confirmError = _validateConfirmPassword(_confirmPasswordController.text);
    });

    if (_nameError != null ||
        _icError != null ||
        _phoneError != null ||
        _emailError != null ||
        _passwordError != null ||
        _confirmError != null) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final fullPhoneForStorage = Validators.toStoredPhone(_phoneController.text);
    final cleanedIC = _icController.text.replaceAll(RegExp(r'[^0-9]'), '');
    try {
      final response = await supabase.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        data: {
          'name': _nameController.text.trim(),
          'ic_number': cleanedIC,
          'phone': fullPhoneForStorage,
          'role': 'passenger', // placeholder; the popup below sets the real one
        },
      );

      // double check if email exists
      final identities = response.user?.identities;
      if (identities != null && identities.isEmpty) {
        setState(() => _errorMessage =
        'An account with this email already exists. Please log in instead.');
        return;
      }

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const ProfileScreen(isFirstTimeSetup: true),
        ),
      );
    } on AuthException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (e) {
      setState(() => _errorMessage = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: _fieldDecoration(),
                onChanged: (_) => _revalidateIfNeeded(),
              ),
              _errorText(_nameError),
              const SizedBox(height: 18),

              Text('IC Number', style: TextStyle(color: AppColors.greyText, fontSize: 13)),
              const SizedBox(height: 6),
              TextField(
                controller: _icController,
                keyboardType: TextInputType.number,
                inputFormatters: [MalaysianICInputFormatter()],
                decoration: _fieldDecoration().copyWith(
                  hintText: '990101-14-5678',
                  hintStyle: TextStyle(color: AppColors.greyText.withValues(alpha: 0.6)),
                ),
                onChanged: (_) => _revalidateIfNeeded(),
              ),
              _errorText(_icError),
              const SizedBox(height: 18),

              Text('Phone Number', style: TextStyle(color: AppColors.greyText, fontSize: 13)),
              const SizedBox(height: 6),
              AnimatedBuilder(
                animation: _phoneFocusNode,
                builder: (context, child) {
                  return Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _phoneFocusNode.hasFocus
                            ? AppColors.primaryYellow
                            : AppColors.greyBorder,
                        width: _phoneFocusNode.hasFocus ? 1.5 : 1,
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
                        controller: _phoneController,
                        focusNode: _phoneFocusNode,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(11),
                        ],
                        style: TextStyle(color: AppColors.black),
                        decoration: InputDecoration(
                          hintText: '0123456789',
                          hintStyle: TextStyle(color: AppColors.greyText.withValues(alpha: 0.5)),
                          contentPadding: const EdgeInsets.symmetric(vertical: 12),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                        ),
                        onChanged: (_) => _revalidateIfNeeded(),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
              _errorText(_phoneError),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'Enter your number starting with 01, e.g. 0123456789',
                  style: TextStyle(color: AppColors.greyText, fontSize: 11),
                ),
              ),
              const SizedBox(height: 18),

              Text('Email', style: TextStyle(color: AppColors.greyText, fontSize: 13)),
              const SizedBox(height: 6),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: _fieldDecoration(),
                onChanged: (_) => _revalidateIfNeeded(),
              ),
              _errorText(_emailError),
              const SizedBox(height: 18),

              Text('Password', style: TextStyle(color: AppColors.greyText, fontSize: 13)),
              const SizedBox(height: 6),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: _fieldDecoration(
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_off : Icons.visibility,
                      color: AppColors.greyText,
                      size: 20,
                    ),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                onChanged: (_) => _revalidateIfNeeded(),
              ),
              _errorText(_passwordError),
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
                controller: _confirmPasswordController,
                obscureText: _obscureConfirmPassword,
                decoration: _fieldDecoration(
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirmPassword ? Icons.visibility_off : Icons.visibility,
                      color: AppColors.greyText,
                      size: 20,
                    ),
                    onPressed: () =>
                        setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                  ),
                ),
                onChanged: (_) => _revalidateIfNeeded(),
              ),
              _errorText(_confirmError),

              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Text(_errorMessage!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
              ],

              const SizedBox(height: 28),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryYellow,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: _isLoading ? null : _register,
                  child: _isLoading
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