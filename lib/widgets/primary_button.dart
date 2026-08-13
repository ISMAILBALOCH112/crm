import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A gradient, glowing button that shrinks slightly on press and swaps its
/// label for a spinner while [isLoading] is true.
class PrimaryButton extends StatefulWidget {
  final String label;
  final bool isLoading;
  final VoidCallback? onPressed;

  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
  });

  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton> {
  double _scale = 1;

  void _setScale(double value) {
    if (widget.onPressed == null || widget.isLoading) return;
    setState(() => _scale = value);
  }

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onPressed == null || widget.isLoading;

    return GestureDetector(
      onTapDown: (_) => _setScale(0.97),
      onTapUp: (_) => _setScale(1),
      onTapCancel: () => _setScale(1),
      onTap: widget.isLoading ? null : widget.onPressed,
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 100),
        child: Container(
          height: 54,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: AppColors.primaryGradient,
            boxShadow: disabled
                ? []
                : [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.4),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
          ),
          alignment: Alignment.center,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: widget.isLoading
                ? const SizedBox(
                    key: ValueKey('loading'),
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                  )
                : Text(
                    widget.label,
                    key: const ValueKey('label'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
