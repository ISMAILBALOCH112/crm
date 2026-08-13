import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../services/auth_service.dart';
import '../services/tenant_service.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/primary_button.dart';

/// Shown while a join request is awaiting admin approval, or after it's
/// been declined. AuthGate watches both the requester's membership doc and
/// their pending-request doc, so this screen updates automatically — it
/// never needs to poll or be manually refreshed.
class PendingApprovalScreen extends StatelessWidget {
  final bool isRejected;

  const PendingApprovalScreen({super.key, this.isRejected = false});

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();

    return AuthScaffold(
      icon: isRejected ? Icons.block_rounded : Icons.hourglass_top_rounded,
      title: isRejected ? 'Request Declined' : 'Request Sent',
      subtitle: isRejected
          ? "The business admin didn't approve your request to join"
          : 'Waiting for an admin to approve your request to join',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            isRejected ? Icons.cancel_outlined : Icons.mark_email_read_outlined,
            size: 56,
            color: isRejected ? AppColors.error : AppColors.primaryLight,
          ).animate().fadeIn(duration: 400.ms).scale(duration: 400.ms, curve: Curves.easeOut),
          const SizedBox(height: 20),
          Text(
            isRejected
                ? 'You can try again with a different invite code, or contact the business to ask them to approve you.'
                : "You'll be let in automatically once approved. No need to keep checking.",
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ).animate().fadeIn(delay: 150.ms, duration: 350.ms),
          const SizedBox(height: 28),
          if (isRejected)
            PrimaryButton(
              label: 'Try Again',
              onPressed: TenantService().clearPendingRequest,
            ).animate().fadeIn(delay: 250.ms, duration: 350.ms),
          const SizedBox(height: 12),
          TextButton(
            onPressed: authService.logout,
            child: const Text('Log Out'),
          ).animate().fadeIn(delay: 300.ms, duration: 350.ms),
        ],
      ),
    );
  }
}
