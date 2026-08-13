import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../services/auth_service.dart';
import '../services/otp_service.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/primary_button.dart';

class OtpVerificationScreen extends StatefulWidget {
  final String name;
  final String email;
  final String phone;
  final String password;

  const OtpVerificationScreen({
    super.key,
    required this.name,
    required this.email,
    required this.phone,
    required this.password,
  });

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  static const _digits = 6;
  final _controllers = List.generate(_digits, (_) => TextEditingController());
  final _focusNodes = List.generate(_digits, (_) => FocusNode());

  final _otpService = OtpService();
  final _authService = AuthService();

  bool _isVerifying = false;
  bool _isResending = false;
  String? _errorMessage;
  bool _shake = false;

  int _resendCooldown = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  void _startCooldown() {
    _resendCooldown = 60;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendCooldown <= 1) {
        timer.cancel();
        setState(() => _resendCooldown = 0);
      } else {
        setState(() => _resendCooldown--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String get _code => _controllers.map((c) => c.text).join();

  void _triggerShake() {
    setState(() => _shake = true);
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _shake = false);
    });
  }

  Future<void> _verify() async {
    final code = _code;
    if (code.length != _digits) {
      setState(() => _errorMessage = 'Enter the 6-digit code');
      _triggerShake();
      return;
    }

    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });

    try {
      final isValid = await _otpService.verifyOtp(widget.email, code);
      if (!isValid) {
        setState(() => _errorMessage = 'Code is invalid or has expired');
        _triggerShake();
        for (final c in _controllers) {
          c.clear();
        }
        _focusNodes.first.requestFocus();
        return;
      }

      await _authService.createAccount(
        name: widget.name,
        email: widget.email,
        phone: widget.phone,
        password: widget.password,
      );
      // AuthGate listens for the auth state change and swaps to Home itself.
    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = _authService.messageForError(e));
    } catch (e) {
      setState(() => _errorMessage = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  Future<void> _resend() async {
    setState(() => _isResending = true);
    try {
      await _otpService.sendSignupOtp(widget.email);
      _startCooldown();
    } catch (e) {
      setState(() => _errorMessage = 'Could not resend the code');
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  void _onDigitChanged(int index, String value) {
    if (value.isNotEmpty && index < _digits - 1) {
      _focusNodes[index + 1].requestFocus();
    }
    if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
    if (_code.length == _digits) {
      FocusScope.of(context).unfocus();
      _verify();
    }
  }

  Widget _digitBox(int index) {
    return SizedBox(
      width: 46,
      height: 58,
      child: TextField(
        controller: _controllers[index],
        focusNode: _focusNodes[index],
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        maxLength: 1,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(counterText: '', contentPadding: EdgeInsets.zero),
        onChanged: (value) => _onDigitChanged(index, value),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final boxes = Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(_digits, _digitBox),
    ).animate(target: _shake ? 1 : 0).shake(hz: 4, curve: Curves.easeInOut);

    return AuthScaffold(
      icon: Icons.shield_outlined,
      title: 'Verify Your Email',
      subtitle: 'Code sent to ${widget.email}',
      showBack: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          boxes.animate().fadeIn(delay: 220.ms, duration: 350.ms),
          if (_errorMessage != null) ...[
            const SizedBox(height: 14),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.error, fontSize: 13),
            ),
          ],
          const SizedBox(height: 28),
          PrimaryButton(
            label: 'Verify',
            isLoading: _isVerifying,
            onPressed: _verify,
          ).animate().fadeIn(delay: 380.ms, duration: 350.ms),
          const SizedBox(height: 18),
          Center(
            child: TextButton(
              onPressed: (_resendCooldown == 0 && !_isResending) ? _resend : null,
              child: Text(
                _resendCooldown == 0
                    ? (_isResending ? 'Sending...' : 'Resend code')
                    : 'Resend in ${_resendCooldown}s',
                style: TextStyle(
                  color: _resendCooldown == 0 ? AppColors.primaryLight : AppColors.textSecondary,
                ),
              ),
            ),
          ).animate().fadeIn(delay: 440.ms, duration: 350.ms),
        ],
      ),
    );
  }
}
