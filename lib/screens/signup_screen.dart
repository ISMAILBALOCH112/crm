import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../services/otp_service.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/primary_button.dart';
import 'otp_verification_screen.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _otpService = OtpService();

  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final email = _emailController.text.trim();

    try {
      await _otpService.sendSignupOtp(email);
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OtpVerificationScreen(
            name: _nameController.text.trim(),
            email: email,
            phone: _phoneController.text.trim(),
            password: _passwordController.text,
          ),
        ),
      );
    } catch (e) {
      setState(() => _errorMessage = 'Could not send OTP. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _staggered(Widget child, int index) {
    final delay = Duration(milliseconds: 240 + index * 60);
    return child.animate().fadeIn(delay: delay, duration: 350.ms).slideX(begin: -0.05, end: 0, delay: delay, duration: 350.ms);
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      icon: Icons.rocket_launch_rounded,
      title: 'Create Account',
      subtitle: 'Get started with your CRM',
      showBack: true,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _staggered(
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Full Name',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? 'Name is required' : null,
              ),
              0,
            ),
            const SizedBox(height: 14),
            _staggered(
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.mail_outline_rounded),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return 'Email is required';
                  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim())) {
                    return 'Enter a valid email';
                  }
                  return null;
                },
              ),
              1,
            ),
            const SizedBox(height: 14),
            _staggered(
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? 'Phone number is required' : null,
              ),
              2,
            ),
            const SizedBox(height: 14),
            _staggered(
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      color: AppColors.textSecondary,
                    ),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Password is required';
                  if (value.length < 6) return 'Must be at least 6 characters';
                  return null;
                },
              ),
              3,
            ),
            const SizedBox(height: 14),
            _staggered(
              TextFormField(
                controller: _confirmPasswordController,
                obscureText: _obscurePassword,
                decoration: const InputDecoration(
                  labelText: 'Confirm Password',
                  prefixIcon: Icon(Icons.lock_outline_rounded),
                ),
                validator: (value) {
                  if (value != _passwordController.text) return 'Passwords do not match';
                  return null;
                },
              ),
              4,
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 14),
              Text(_errorMessage!, style: const TextStyle(color: AppColors.error, fontSize: 13)).animate().shake(),
            ],
            const SizedBox(height: 24),
            _staggered(
              PrimaryButton(
                label: 'Send OTP',
                isLoading: _isLoading,
                onPressed: _submit,
              ),
              5,
            ),
          ],
        ),
      ),
    );
  }
}
