import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../theme/app_theme.dart';

/// Shared shell for auth screens: soft canvas with glow blobs behind a
/// gradient icon badge, bold title/subtitle, then the screen's own form
/// content.
///
/// The icon/title/subtitle header collapses away while the keyboard is open
/// so forms with several fields always have room to show their button above
/// the keyboard instead of the two overlapping.
class AuthScaffold extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;
  final bool showBack;

  const AuthScaffold({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
    this.showBack = false,
  });

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Positioned(
            top: -120,
            right: -80,
            child: _glow(280, AppColors.primary.withValues(alpha: 0.18)),
          ),
          Positioned(
            bottom: -100,
            left: -100,
            child: _glow(240, AppColors.accent.withValues(alpha: 0.10)),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 8, 28, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 44,
                    child: showBack
                        ? IconButton(
                            alignment: Alignment.centerLeft,
                            padding: EdgeInsets.zero,
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textSecondary, size: 20),
                          )
                        : null,
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    alignment: Alignment.topCenter,
                    child: keyboardOpen
                        ? const SizedBox(height: 12, width: double.infinity)
                        : Column(
                            children: [
                              const SizedBox(height: 12),
                              Center(
                                child: Container(
                                  width: 68,
                                  height: 68,
                                  decoration: BoxDecoration(
                                    gradient: AppColors.primaryGradient,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.primary.withValues(alpha: 0.35),
                                        blurRadius: 24,
                                        offset: const Offset(0, 10),
                                      ),
                                    ],
                                  ),
                                  child: Icon(icon, color: Colors.white, size: 32),
                                ).animate().scale(duration: 500.ms, curve: Curves.elasticOut),
                              ),
                              const SizedBox(height: 24),
                              Text(
                                title,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 28,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.5,
                                ),
                              ).animate().fadeIn(delay: 120.ms, duration: 400.ms).slideY(begin: 0.15, end: 0, delay: 120.ms, duration: 400.ms),
                              const SizedBox(height: 8),
                              Text(
                                subtitle,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: AppColors.textSecondary, fontSize: 14.5),
                              ).animate().fadeIn(delay: 200.ms, duration: 400.ms),
                              const SizedBox(height: 36),
                            ],
                          ),
                  ),
                  child,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _glow(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}
