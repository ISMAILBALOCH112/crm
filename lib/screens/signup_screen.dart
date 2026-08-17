import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../services/auth_service.dart';
import '../services/invite_session.dart';
import '../services/tenant_service.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/primary_button.dart';

class SignupScreen extends StatefulWidget {
  final String? inviteToken;

  const SignupScreen({super.key, this.inviteToken});

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
  final _inviteController = TextEditingController();
  final _authService = AuthService();
  final _tenantService = TenantService();

  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMessage;

  String? get _resolvedInviteToken {
    final fromField = InviteSession.extractToken(_inviteController.text);
    if (fromField != null) return fromField;
    final fromWidget = InviteSession.extractToken(widget.inviteToken);
    if (fromWidget != null) return fromWidget;
    return InviteSession.extractToken(InviteSession.peek());
  }

  bool get _isInviteSignup => (_resolvedInviteToken ?? '').isNotEmpty;

  @override
  void initState() {
    super.initState();
    final seed = widget.inviteToken ?? InviteSession.peek();
    if (seed != null && seed.trim().isNotEmpty) {
      _inviteController.text = seed.contains('://') ? seed : TenantService.inviteLinkUrl(seed.trim());
    }
    _inviteController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _inviteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final email = _emailController.text.trim();
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final password = _passwordController.text;
    final inviteToken = _resolvedInviteToken;

    try {
      await _authService.createAccount(
        name: name,
        email: email,
        phone: phone,
        password: password,
      );

      if (inviteToken != null && inviteToken.isNotEmpty) {
        await _tenantService.acceptInviteLink(inviteToken);
        InviteSession.take();
      }

      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = _authService.messageForError(e));
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      setState(() {
        _errorMessage = msg.isNotEmpty ? msg : 'Could not create account. Please try again.';
      });
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
      subtitle: _isInviteSignup ? 'Join the team with your invite link' : 'Create your WaTech account',
      showBack: true,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _staggered(
              TextFormField(
                controller: _inviteController,
                decoration: InputDecoration(
                  labelText: 'Team invite link (optional)',
                  hintText: 'Paste https://…/invite/… or watech://…',
                  prefixIcon: const Icon(Icons.link_rounded),
                  helperText: _isInviteSignup
                      ? 'You will join the team right after signup'
                      : 'Optional — paste invite if joining an existing team',
                  helperMaxLines: 2,
                ),
              ),
              0,
            ),
            const SizedBox(height: 14),
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
              1,
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
              2,
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
              3,
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
              4,
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
              5,
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 14),
              Text(_errorMessage!, style: const TextStyle(color: AppColors.error, fontSize: 13)).animate().shake(),
            ],
            const SizedBox(height: 24),
            _staggered(
              PrimaryButton(
                label: _isInviteSignup ? 'Create account & join' : 'Create account',
                isLoading: _isLoading,
                onPressed: _submit,
              ),
              6,
            ),
          ],
        ),
      ),
    );
  }
}
