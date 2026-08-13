import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/primary_button.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _authService = AuthService();

  bool _isLoading = false;
  String? _errorMessage;
  bool _emailSent = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _authService.sendPasswordResetEmail(_emailController.text.trim());
      setState(() => _emailSent = true);
    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = _authService.messageForError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      icon: Icons.autorenew_rounded,
      title: 'Reset Password',
      subtitle: "We'll email you a reset link",
      showBack: true,
      child: _emailSent ? _buildSuccess() : _buildForm(),
    );
  }

  Widget _buildSuccess() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_rounded, size: 40, color: AppColors.primaryLight),
        ).animate().scale(duration: 450.ms, curve: Curves.elasticOut),
        const SizedBox(height: 18),
        Text(
          'Link sent to ${_emailController.text.trim()}',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 15, color: AppColors.textSecondary),
        ).animate().fadeIn(delay: 180.ms, duration: 350.ms),
        const SizedBox(height: 28),
        PrimaryButton(
          label: 'Back to Sign In',
          onPressed: () => Navigator.of(context).pop(),
        ).animate().fadeIn(delay: 280.ms, duration: 350.ms),
      ],
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
          ).animate().fadeIn(delay: 240.ms, duration: 350.ms).slideX(begin: -0.05, end: 0, delay: 240.ms, duration: 350.ms),
          if (_errorMessage != null) ...[
            const SizedBox(height: 14),
            Text(_errorMessage!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
          ],
          const SizedBox(height: 24),
          PrimaryButton(
            label: 'Send Reset Link',
            isLoading: _isLoading,
            onPressed: _submit,
          ).animate().fadeIn(delay: 320.ms, duration: 350.ms),
        ],
      ),
    );
  }
}
