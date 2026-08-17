import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../services/invite_session.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';
import 'signup_screen.dart';

class GetStartedScreen extends StatelessWidget {
  const GetStartedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: const [
          _TopRightOrb(),
          _BottomCurve(),
          _Content(),
        ],
      ),
    );
  }
}

class _TopRightOrb extends StatelessWidget {
  const _TopRightOrb();

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final size = width * 0.88;

    return Positioned(
      top: -size * 0.36,
      right: -size * 0.26,
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.accentPinkLight,
        ),
      ),
    );
  }
}

class _BottomCurve extends StatelessWidget {
  const _BottomCurve();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(child: CustomPaint(painter: _BottomWavePainter()));
  }
}

class _BottomWavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final back = Paint()..color = AppColors.accent.withValues(alpha: 0.85);
    final front = Paint()..color = const Color(0xFFFF6B9A);

    final backPath = Path()
      ..moveTo(0, size.height * 0.62)
      ..quadraticBezierTo(size.width * 0.28, size.height * 0.48, size.width * 0.55, size.height * 0.58)
      ..quadraticBezierTo(size.width * 0.82, size.height * 0.68, size.width, size.height * 0.52)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    final frontPath = Path()
      ..moveTo(0, size.height * 0.72)
      ..quadraticBezierTo(size.width * 0.22, size.height * 0.58, size.width * 0.50, size.height * 0.66)
      ..quadraticBezierTo(size.width * 0.76, size.height * 0.74, size.width, size.height * 0.60)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(backPath, back);
    canvas.drawPath(frontPath, front);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Content extends StatelessWidget {
  const _Content();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 20, 28, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: AppColors.cardShadow(AppColors.primary),
                  ),
                  child: const Icon(Icons.chat_rounded, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                const Text(
                  'WaTech',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ).animate().fadeIn(duration: 400.ms),
            const Spacer(flex: 2),
            const Text(
              'Manage your\nWhatsApp business',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 34,
                fontWeight: FontWeight.w700,
                height: 1.15,
                letterSpacing: -0.6,
              ),
            ).animate().fadeIn(delay: 80.ms, duration: 450.ms).slideY(begin: 0.1, end: 0),
            const SizedBox(height: 14),
            Text(
              'Chat with customers, track orders,\nand automate replies — all in one app.',
              style: TextStyle(
                color: AppColors.textSecondary.withValues(alpha: 0.95),
                fontSize: 15,
                height: 1.5,
                fontWeight: FontWeight.w400,
              ),
            ).animate().fadeIn(delay: 160.ms, duration: 450.ms),
            const Spacer(flex: 3),
            _PillButton(
              label: InviteSession.peek() != null ? 'Join with invite' : 'Create account',
              filled: true,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SignupScreen(inviteToken: InviteSession.peek()),
                ),
              ),
            ).animate().fadeIn(delay: 240.ms, duration: 400.ms).slideY(begin: 0.12, end: 0),
            const SizedBox(height: 14),
            _PillButton(
              label: 'Sign in',
              filled: false,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LoginScreen(showBack: true)),
              ),
            ).animate().fadeIn(delay: 300.ms, duration: 400.ms).slideY(begin: 0.12, end: 0),
          ],
        ),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  final String label;
  final bool filled;
  final VoidCallback onPressed;

  const _PillButton({required this.label, required this.filled, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(28),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: filled ? AppColors.primaryGradient : null,
              color: filled ? null : Colors.white.withValues(alpha: 0.96),
              border: filled ? null : Border.all(color: Colors.white.withValues(alpha: 0.9), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: (filled ? AppColors.primary : Colors.black).withValues(alpha: filled ? 0.25 : 0.07),
                  blurRadius: filled ? 18 : 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: filled ? Colors.white : AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
