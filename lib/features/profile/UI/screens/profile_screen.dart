import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nak_tumpang/features/auth/UI/screens/login_screen.dart';
import 'package:nak_tumpang/features/home/UI/screens/home_screen.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';

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

  // Malaysian mobile number: optional +60 or 0, then 1, then 8-9 digits.
  // Matches formats like 0123456789, +60123456789, 60123456789.
  final _phoneRegex = RegExp(r'^(\+?60|0)1[0-46-9][0-9]{6,8}$');

  String _role = 'passenger';
  String? _email;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;
  String? _successMessage;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final data = await supabase
          .from('users')
          .select()
          .eq('id', userId)
          .single();

      setState(() {
        _nameController.text = data['name'] ?? '';
        _phoneController.text = data['phone'] ?? '';
        _role = data['role'] ?? 'passenger';
        _email = data['email'] ?? supabase.auth.currentUser?.email;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _email = supabase.auth.currentUser?.email;
        _isLoading = false;
      });
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      await supabase.from('users').update({
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'role': _role,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', userId);

      if (!mounted) return;

      if (widget.isFirstTimeSetup) {
        // First-time setup complete -> continue into the app.
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      } else {
        setState(() => _successMessage = 'Profile updated.');
      }
    } catch (e) {
      setState(() => _errorMessage = 'Could not save. Please try again.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
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
        backgroundColor: AppColors.white,
        elevation: 0,
        title: Text(
          widget.isFirstTimeSetup ? 'Complete your profile' : 'My Profile',
          style: TextStyle(color: AppColors.black),
        ),
        automaticallyImplyLeading: !widget.isFirstTimeSetup,
        actions: [
          if (!widget.isFirstTimeSetup)
            IconButton(
              icon: Icon(Icons.logout, color: AppColors.greyText),
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
                // Avatar (initials-based, no upload)
                Center(
                  child: CircleAvatar(
                    radius: 44,
                    backgroundColor: AppColors.primaryYellow,
                    child: Text(
                      _initials,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (_email != null)
                  Center(
                    child: Text(
                      _email!,
                      style: TextStyle(color: AppColors.greyText, fontSize: 13),
                    ),
                  ),
                const SizedBox(height: 28),

                // Name
                Text('name', style: TextStyle(color: AppColors.greyText, fontSize: 13)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _nameController,
                  decoration: _fieldDecoration(),
                  onChanged: (_) => setState(() {}), // updates avatar initials live
                  validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                ),
                const SizedBox(height: 18),

                // Phone
                Text('phone number', style: TextStyle(color: AppColors.greyText, fontSize: 13)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: _fieldDecoration(hint: 'e.g. 0123456789'),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Phone number is required';
                    final cleaned = v.trim().replaceAll(RegExp(r'[\s-]'), '');
                    if (!_phoneRegex.hasMatch(cleaned)) {
                      return 'Enter a valid Malaysian phone number';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 18),

                // Role
                Text('I am a', style: TextStyle(color: AppColors.greyText, fontSize: 13)),
                const SizedBox(height: 6),
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
                ),

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

  InputDecoration _fieldDecoration({String? hint}) {
    return InputDecoration(
      hintText: hint,
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