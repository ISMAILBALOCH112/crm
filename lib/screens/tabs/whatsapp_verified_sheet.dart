import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Scalloped "verified" seal badge, styled after Meta/Instagram's blue
/// verified checkmark — shown once Meta confirms the connected WhatsApp
/// number (`code_verification_status == 'VERIFIED'`).
class VerifiedBadge extends StatelessWidget {
  final double size;

  const VerifiedBadge({super.key, this.size = 17});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: const Color(0xFF0095F6).withValues(alpha: 0.35), blurRadius: 5, offset: const Offset(0, 1)),
        ],
      ),
      child: ShaderMask(
        shaderCallback: (bounds) => const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF5AC8FA), Color(0xFF0095F6)],
        ).createShader(bounds),
        child: Icon(Icons.verified_rounded, size: size, color: Colors.white),
      ),
    );
  }
}

/// Tap-to-view detail sheet for the connected WhatsApp number, showing the
/// real values Meta returned at connect time (verified business name,
/// messaging quality rating) — not placeholder text.
void showWhatsappVerifiedDetails(
  BuildContext context, {
  required String? phoneDisplay,
  required String? verifiedName,
  required String? qualityRating,
  required String? codeVerificationStatus,
}) {
  final isVerified = codeVerificationStatus == 'VERIFIED';
  final quality = _qualityInfo(qualityRating);

  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) => Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: AppColors.surfaceBorder, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.chat_bubble_rounded, color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            verifiedName?.isNotEmpty == true ? verifiedName! : 'WhatsApp Business',
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 17,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isVerified) ...[const SizedBox(width: 6), const VerifiedBadge(size: 16)],
                      ],
                    ),
                    if (phoneDisplay?.isNotEmpty == true)
                      Text(
                        phoneDisplay!,
                        style: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.9), fontSize: 13.5),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _DetailRow(
            label: 'Verification status',
            value: isVerified ? 'Verified by Meta' : (codeVerificationStatus ?? 'Not available'),
            valueColor: isVerified ? const Color(0xFF1E88E5) : AppColors.textSecondary,
          ),
          const SizedBox(height: 14),
          _DetailRow(label: 'Messaging quality', value: quality.label, dotColor: quality.color),
          const SizedBox(height: 20),
          Text(
            'Pulled from Meta WhatsApp Cloud API when this number was connected. '
            'Inbound chats need webhook field “messages” subscribed.',
            style: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.7), fontSize: 11.5),
          ),
        ],
      ),
    ),
  );
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final Color? dotColor;

  const _DetailRow({required this.label, required this.value, this.valueColor, this.dotColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(label, style: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.9), fontSize: 13.5)),
        ),
        if (dotColor != null) ...[
          Container(width: 8, height: 8, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
          const SizedBox(width: 6),
        ],
        Text(
          value,
          style: TextStyle(color: valueColor ?? AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 13.5),
        ),
      ],
    );
  }
}

class _QualityInfo {
  final String label;
  final Color color;
  const _QualityInfo(this.label, this.color);
}

_QualityInfo _qualityInfo(String? rating) {
  switch (rating) {
    case 'GREEN':
      return const _QualityInfo('High', Color(0xFF34C759));
    case 'YELLOW':
      return const _QualityInfo('Medium', Color(0xFFFFB020));
    case 'RED':
      return const _QualityInfo('Low', Color(0xFFE85D75));
    default:
      return const _QualityInfo('Not available', AppColors.textSecondary);
  }
}
