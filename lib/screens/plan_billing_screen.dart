import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/subscription_service.dart';
import '../theme/app_theme.dart';
import '../widgets/plan_payment_warning.dart';

Future<void> openPlanBillingScreen(BuildContext context, String tenantId) {
  return Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => PlanBillingScreen(tenantId: tenantId)),
  );
}

class PlanBillingScreen extends StatefulWidget {
  final String tenantId;

  const PlanBillingScreen({super.key, required this.tenantId});

  @override
  State<PlanBillingScreen> createState() => _PlanBillingScreenState();
}

class _PlanBillingScreenState extends State<PlanBillingScreen> {
  final _keyController = TextEditingController();
  final _sub = SubscriptionService();
  bool _redeeming = false;
  String? _error;

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _redeem() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      setState(() => _error = 'Enter a license key');
      return;
    }
    setState(() {
      _redeeming = true;
      _error = null;
    });
    try {
      await _sub.redeemKey(tenantId: widget.tenantId, key: key);
      if (!mounted) return;
      _keyController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Plan activated')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _redeeming = false);
    }
  }

  Future<void> _showWarning(TenantBilling billing, BillingPaymentInfo payment) {
    return showPlanPaymentWarningDialog(
      context,
      billing: billing,
      payment: payment,
      onRenew: () {},
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text('Plan & billing', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: StreamBuilder<TenantBilling>(
        stream: _sub.watchBilling(widget.tenantId),
        builder: (context, snap) {
          final billing = snap.data ??
              const TenantBilling(planId: null, planStatus: 'active', planExpiresAt: null, writeAllowed: true);
          return StreamBuilder<BillingPaymentInfo>(
            stream: watchBillingPaymentInfo(),
            builder: (context, paySnap) {
              final payment = paySnap.data ?? BillingPaymentInfo.defaults;
              return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (!billing.writeAllowed || billing.isExpiringSoon) ...[
                    _StatusBanner(
                      expired: !billing.writeAllowed,
                      daysLeft: billing.daysLeft,
                      title: billing.warningTitle,
                      subtitle: billing.wasKeyLocked
                          ? 'Tap for payment guide & renew steps'
                          : (!billing.writeAllowed
                              ? 'Tap for payment warning & renew steps'
                              : 'Tap to see payment guide'),
                      onTap: () => _showWarning(billing, payment),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceSolid,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.surfaceBorder),
                      boxShadow: AppColors.cardShadow(AppColors.accent),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          billing.writeAllowed ? 'Active' : 'Expired — read only',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: billing.writeAllowed ? AppColors.primary : AppColors.error,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text('Plan: ${billing.planLabel}', style: const TextStyle(color: AppColors.textPrimary)),
                        const SizedBox(height: 4),
                        Text('Expires: ${billing.expiryLabel}', style: const TextStyle(color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  BillingPaymentGuideCard(
                    payment: payment,
                    onHowToPay: () => _showWarning(billing, payment),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Payment ke baad milne wali license key yahan enter karein.',
                    style: TextStyle(color: AppColors.textSecondary, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _keyController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'License key',
                      hintText: 'WT-M1-XXXX-XXXX',
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(_error!, style: const TextStyle(color: AppColors.error)),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _redeeming ? null : _redeem,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _redeeming
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Activate key'),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final bool expired;
  final int? daysLeft;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _StatusBanner({
    required this.expired,
    required this.daysLeft,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = expired ? AppColors.error : AppColors.accentWarm;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: expired
                  ? [const Color(0xFFFFE8E8), const Color(0xFFFFF0F0)]
                  : [const Color(0xFFFFF0E0), const Color(0xFFFFF8F0)],
            ),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Icon(expired ? Icons.warning_amber_rounded : Icons.timelapse_rounded, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: color)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> openPlatformKeysScreen(BuildContext context) {
  return Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const PlatformKeysScreen()),
  );
}

class PlatformKeysScreen extends StatefulWidget {
  const PlatformKeysScreen({super.key});

  @override
  State<PlatformKeysScreen> createState() => _PlatformKeysScreenState();
}

class _PlatformKeysScreenState extends State<PlatformKeysScreen> {
  final _sub = SubscriptionService();
  final _jazzController = TextEditingController();
  final _nameController = TextEditingController();
  final _noteController = TextEditingController();
  final _waController = TextEditingController();
  final _priceControllers = <String, TextEditingController>{
    'd7': TextEditingController(),
    'd15': TextEditingController(),
    'm1': TextEditingController(),
    'm6': TextEditingController(),
    'm12': TextEditingController(),
  };

  List<BillingPlanOption> _plans = const [];
  List<LicenseKeyRow> _keys = const [];
  String _planId = 'm1';
  int _count = 1;
  bool _loading = true;
  bool _creating = false;
  bool _savingPay = false;
  String? _error;
  List<String> _lastCreated = const [];
  final _customDaysController = TextEditingController(text: '45');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _jazzController.dispose();
    _nameController.dispose();
    _noteController.dispose();
    _waController.dispose();
    _customDaysController.dispose();
    for (final c in _priceControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final plans = await _sub.listPlans();
      final keys = await _sub.listLicenseKeys();
      final pay = await fetchBillingPaymentInfo();
      if (!mounted) return;
      _jazzController.text = pay.jazzcashNumber;
      _nameController.text = pay.accountName;
      _noteController.text = pay.note;
      _waController.text = pay.whatsappSupport;
      for (final e in _priceControllers.entries) {
        e.value.text = '${pay.pricesPkr[e.key] ?? ''}';
      }
      setState(() {
        _plans = plans;
        _keys = keys;
        if (_plans.isNotEmpty && !_plans.any((p) => p.planId == _planId)) {
          _planId = _plans.first.planId;
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _savePayment() async {
    setState(() => _savingPay = true);
    try {
      final prices = <String, int>{};
      for (final e in _priceControllers.entries) {
        prices[e.key] = int.tryParse(e.value.text.trim()) ?? BillingPaymentInfo.defaults.pricesPkr[e.key] ?? 0;
      }
      await saveBillingPaymentInfo(
        BillingPaymentInfo(
          accountName: _nameController.text.trim().isEmpty ? 'WaTech' : _nameController.text.trim(),
          jazzcashNumber: _jazzController.text.trim().isEmpty ? '03XXXXXXXXX' : _jazzController.text.trim(),
          bankName: 'JazzCash',
          whatsappSupport: _waController.text.trim(),
          note: _noteController.text.trim(),
          pricesPkr: prices,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment guide saved')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _savingPay = false);
    }
  }

  Future<void> _create() async {
    setState(() {
      _creating = true;
      _error = null;
      _lastCreated = const [];
    });
    try {
      int? customDays;
      if (_planId == 'custom') {
        customDays = int.tryParse(_customDaysController.text.trim());
        if (customDays == null || customDays < 1 || customDays > 3650) {
          setState(() {
            _creating = false;
            _error = 'Custom days 1–3650 likho';
          });
          return;
        }
      }
      final keys = await _sub.createLicenseKeys(
        planId: _planId,
        count: _count,
        durationDays: customDays,
      );
      if (!mounted) return;
      setState(() => _lastCreated = keys);
      await Clipboard.setData(ClipboardData(text: keys.join('\n')));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${keys.length} key(s) created & copied')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text('License keys', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        actions: [
          IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text('Payment details (customers ko dikhega)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 10),
                TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'Account name')),
                const SizedBox(height: 10),
                TextField(
                  controller: _jazzController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'JazzCash number'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _waController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Support WhatsApp (optional)'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _noteController,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Note for customers'),
                ),
                const SizedBox(height: 12),
                const Text('Prices (PKR)', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                for (final id in _priceControllers.keys) ...[
                  TextField(
                    controller: _priceControllers[id],
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: BillingPaymentInfo.planTitle(id)),
                  ),
                  const SizedBox(height: 8),
                ],
                FilledButton(
                  onPressed: _savingPay ? null : _savePayment,
                  style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                  child: _savingPay
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Save payment guide'),
                ),
                const SizedBox(height: 28),
                const Divider(),
                const SizedBox(height: 12),
                const Text(
                  'Generate keys after offline payment. Customer redeems in Settings → Plan & billing.',
                  style: TextStyle(color: AppColors.textSecondary, height: 1.4),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _planId,
                  decoration: const InputDecoration(labelText: 'Plan'),
                  items: [
                    for (final p in _plans)
                      DropdownMenuItem(value: p.planId, child: Text('${p.label} (${p.durationDays}d)')),
                    const DropdownMenuItem(value: 'custom', child: Text('Custom days')),
                  ],
                  onChanged: (v) => setState(() => _planId = v ?? _planId),
                ),
                if (_planId == 'custom') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _customDaysController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Custom days',
                      helperText: '1–3650 (jitne din chaho)',
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: _count,
                  decoration: const InputDecoration(labelText: 'How many keys'),
                  items: [
                    for (final n in [1, 2, 3, 5, 10]) DropdownMenuItem(value: n, child: Text('$n')),
                  ],
                  onChanged: (v) => setState(() => _count = v ?? 1),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!, style: const TextStyle(color: AppColors.error)),
                ],
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: _creating ? null : _create,
                  style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                  child: _creating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Generate keys'),
                ),
                if (_lastCreated.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  SelectableText(
                    _lastCreated.join('\n'),
                    style: const TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.5),
                  ),
                ],
                const SizedBox(height: 28),
                const Text('Recent keys', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 6),
                const Text(
                  'Revoke / Delete used key → us account read-only lock ho jata hai.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.35),
                ),
                const SizedBox(height: 10),
                for (final k in _keys)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    elevation: 0,
                    color: AppColors.surfaceMuted,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(k.key, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                                const SizedBox(height: 2),
                                Text(
                                  '${k.label ?? k.planId} · ${k.status}'
                                  '${k.usedByTenantId != null ? ' · tenant ${k.usedByTenantId!.length > 8 ? k.usedByTenantId!.substring(0, 8) : k.usedByTenantId}…' : ''}',
                                  style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Copy',
                            icon: const Icon(Icons.copy_rounded, size: 18),
                            onPressed: () async {
                              await Clipboard.setData(ClipboardData(text: k.key));
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Copied'), duration: Duration(seconds: 1)),
                              );
                            },
                          ),
                          if (k.status != 'revoked')
                            IconButton(
                              tooltip: 'Revoke (locks account if used)',
                              icon: const Icon(Icons.block_rounded, size: 18, color: AppColors.accentWarm),
                              onPressed: () => _revokeKey(k),
                            ),
                          IconButton(
                            tooltip: 'Delete (locks account if used)',
                            icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.error),
                            onPressed: () => _deleteKey(k),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Future<void> _revokeKey(LicenseKeyRow k) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revoke key?'),
        content: Text(
          k.usedByTenantId != null
              ? 'Yeh key use ho chuki hai. Revoke ke baad us account read-only lock ho jayega.'
              : 'Key revoke ho jayegi (unused).',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.accentWarm),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final locked = await _sub.revokeLicenseKey(k.key);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            locked != null && locked.isNotEmpty
                ? 'Key revoked · account locked (read-only)'
                : 'Key revoked',
          ),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _deleteKey(LicenseKeyRow k) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete key?'),
        content: Text(
          k.usedByTenantId != null
              ? 'Delete ke baad us account read-only lock ho jayega. Key list se hata di jayegi.'
              : 'Key permanently delete ho jayegi.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final locked = await _sub.deleteLicenseKey(k.key);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            locked != null && locked.isNotEmpty
                ? 'Key deleted · account locked (read-only)'
                : 'Key deleted',
          ),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }
}
