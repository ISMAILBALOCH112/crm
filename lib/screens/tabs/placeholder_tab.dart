import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Temporary body for a bottom-nav tab until its real content is built.
class PlaceholderTab extends StatelessWidget {
  final IconData icon;
  final String title;

  const PlaceholderTab({super.key, required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: AppColors.textSecondary.withValues(alpha: 0.35)),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(color: AppColors.textSecondary, fontSize: 15)),
        ],
      ),
    );
  }
}
