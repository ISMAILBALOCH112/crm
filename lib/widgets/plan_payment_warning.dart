import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../services/subscription_service.dart';
import '../theme/app_theme.dart';

/// Offline payment details shown to tenants (JazzCash etc.).
class BillingPaymentInfo {
  final String accountName;
  final String jazzcashNumber;
  final String bankName;
  final String whatsappSupport;
  final String note;
  final Map<String, int> pricesPkr;

  const BillingPaymentInfo({
    required this.accountName,
    required this.jazzcashNumber,
    required this.bankName,
    required this.whatsappSupport,
    required this.note,
    required this.pricesPkr,
  });

  static const defaults = BillingPaymentInfo(
    accountName: 'WaTech',
    jazzcashNumber: '03XXXXXXXXX',
    bankName: 'JazzCash',
    whatsappSupport: '',
    note: 'Payment ke baad screenshot WhatsApp pe bhejein. Key milne ke baad Plan & billing mein activate karein.',
    pricesPkr: {
      'd7': 500,
      'd15': 900,
      'm1': 2000,
      'm6': 9000,
      'm12': 15000,
    },
  );

  factory BillingPaymentInfo.fromMap(Map<String, dynamic>? data) {
    if (data == null) return defaults;
    final rawPrices = data['pricesPkr'];
    final prices = <String, int>{...defaults.pricesPkr};
    if (rawPrices is Map) {
      for (final e in rawPrices.entries) {
        final v = e.value;
        if (v is num) prices[e.key.toString()] = v.toInt();
      }
    }
    return BillingPaymentInfo(
      accountName: (data['accountName'] as String?)?.trim().isNotEmpty == true
          ? (data['accountName'] as String).trim()
          : defaults.accountName,
      jazzcashNumber: (data['jazzcashNumber'] as String?)?.trim().isNotEmpty == true
          ? (data['jazzcashNumber'] as String).trim()
          : defaults.jazzcashNumber,
      bankName: (data['bankName'] as String?)?.trim().isNotEmpty == true
          ? (data['bankName'] as String).trim()
          : defaults.bankName,
      whatsappSupport: (data['whatsappSupport'] as String?)?.trim() ?? '',
      note: (data['note'] as String?)?.trim().isNotEmpty == true
          ? (data['note'] as String).trim()
          : defaults.note,
      pricesPkr: prices,
    );
  }

  Map<String, dynamic> toMap() => {
        'accountName': accountName,
        'jazzcashNumber': jazzcashNumber,
        'bankName': bankName,
        'whatsappSupport': whatsappSupport,
        'note': note,
        'pricesPkr': pricesPkr,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  static String planTitle(String planId) {
    switch (planId) {
      case 'd7':
        return '7 days';
      case 'd15':
        return '15 days';
      case 'm1':
        return '1 month';
      case 'm6':
        return '6 months';
      case 'm12':
        return '12 months';
      default:
        return planId;
    }
  }

  String priceLabel(String planId) {
    final p = pricesPkr[planId];
    if (p == null) return '—';
    return 'PKR ${p.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}';
  }
}

Stream<BillingPaymentInfo> watchBillingPaymentInfo() {
  return FirebaseFirestore.instance.collection('platform').doc('billing').snapshots().map(
        (s) => BillingPaymentInfo.fromMap(s.data()),
      );
}

Future<BillingPaymentInfo> fetchBillingPaymentInfo() async {
  final snap = await FirebaseFirestore.instance.collection('platform').doc('billing').get();
  return BillingPaymentInfo.fromMap(snap.data());
}

Future<void> saveBillingPaymentInfo(BillingPaymentInfo info) {
  return FirebaseFirestore.instance.collection('platform').doc('billing').set(info.toMap(), SetOptions(merge: true));
}

/// Polished expiry / renew warning with payment steps.
Future<void> showPlanPaymentWarningDialog(
  BuildContext context, {
  required TenantBilling billing,
  BillingPaymentInfo? payment,
  required VoidCallback onRenew,
}) async {
  final info = payment ?? await fetchBillingPaymentInfo();
  if (!context.mounted) return;

  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Plan warning',
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (ctx, anim, _) {
      return const SizedBox.shrink();
    },
    transitionBuilder: (ctx, anim, _, __) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
          child: _PlanPaymentWarningBody(
            billing: billing,
            payment: info,
            onRenew: onRenew,
          ),
        ),
      );
    },
  );
}

class _PlanPaymentWarningBody extends StatelessWidget {
  final TenantBilling billing;
  final BillingPaymentInfo payment;
  final VoidCallback onRenew;

  const _PlanPaymentWarningBody({
    required this.billing,
    required this.payment,
    required this.onRenew,
  });

  @override
  Widget build(BuildContext context) {
    final expired = !billing.writeAllowed;
    final accent = expired ? AppColors.error : AppColors.accentWarm;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 22),
          constraints: const BoxConstraints(maxWidth: 400),
          decoration: BoxDecoration(
            color: AppColors.surfaceSolid,
            borderRadius: BorderRadius.circular(28),
            boxShadow: AppColors.floatShadow(accent),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: expired
                          ? [const Color(0xFFFFF1F0), const Color(0xFFFFE4E6)]
                          : [const Color(0xFFFFF6EB), const Color(0xFFFFE8D6)],
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: AppColors.cardShadow(accent),
                        ),
                        child: Icon(
                          billing.wasKeyLocked
                              ? Icons.gpp_bad_rounded
                              : (expired ? Icons.lock_clock_rounded : Icons.schedule_rounded),
                          color: accent,
                          size: 32,
                        ),
                      ).animate().fadeIn(duration: 350.ms).scale(begin: const Offset(0.8, 0.8)),
                      const SizedBox(height: 14),
                      Text(
                        billing.warningTitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        billing.warningBody,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.45,
                          color: AppColors.textSecondary.withValues(alpha: 0.95),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _InfoChip(
                        icon: Icons.workspace_premium_outlined,
                        label: '${billing.planLabel} · ${billing.expiryLabel}',
                      ),
                      const SizedBox(height: 12),
                      _PaymentMiniCard(payment: payment),
                      const SizedBox(height: 14),
                      const Text(
                        'Steps',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 8),
                      const _StepRow(n: '1', text: 'JazzCash / bank pe payment karein'),
                      const _StepRow(n: '2', text: 'Screenshot bhejein — key mil jayegi'),
                      const _StepRow(n: '3', text: 'Settings → Plan & billing mein key enter'),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            onRenew();
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: Text(expired ? 'Renew now' : 'View plans & pay'),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Later', style: TextStyle(color: AppColors.textSecondary)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class _PaymentMiniCard extends StatelessWidget {
  final BillingPaymentInfo payment;

  const _PaymentMiniCard({required this.payment});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceBorder),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF7F9FF), Color(0xFFFFF8F5)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.account_balance_wallet_outlined, color: AppColors.primary, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(payment.bankName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    Text(payment.accountName, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Copy number',
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: payment.jazzcashNumber));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Number copied'), duration: Duration(seconds: 1)),
                  );
                },
                icon: const Icon(Icons.copy_rounded, size: 18, color: AppColors.primary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            payment.jazzcashNumber,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final String n;
  final String text;

  const _StepRow({required this.n, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(n, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.primary)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13.2, height: 1.35))),
        ],
      ),
    );
  }
}

/// Compact payment + pricing card for Plan & billing screen.
class BillingPaymentGuideCard extends StatelessWidget {
  final BillingPaymentInfo payment;
  final VoidCallback? onHowToPay;

  const BillingPaymentGuideCard({super.key, required this.payment, this.onHowToPay});

  @override
  Widget build(BuildContext context) {
    final order = ['d7', 'd15', 'm1', 'm6', 'm12'];
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.surfaceBorder),
        color: AppColors.surfaceSolid,
        boxShadow: AppColors.cardShadow(AppColors.primary),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              gradient: LinearGradient(
                colors: [Color(0xFFEEF2FF), Color(0xFFFFF8F5)],
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.payments_outlined, color: AppColors.primary),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Payment guide', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
                if (onHowToPay != null)
                  TextButton(onPressed: onHowToPay, child: const Text('How to pay')),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${payment.bankName} · ${payment.accountName}',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        payment.jazzcashNumber,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 0.6),
                      ),
                    ),
                    IconButton(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: payment.jazzcashNumber));
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Copied'), duration: Duration(seconds: 1)),
                        );
                      },
                      icon: const Icon(Icons.copy_rounded, color: AppColors.primary),
                    ),
                  ],
                ),
                if (payment.note.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(payment.note, style: const TextStyle(color: AppColors.textSecondary, height: 1.4, fontSize: 12.5)),
                ],
                const SizedBox(height: 14),
                const Text('Prices', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final id in order)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceMuted,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${BillingPaymentInfo.planTitle(id)} · ${payment.priceLabel(id)}',
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
