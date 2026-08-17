import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Tenant JazzCash / EasyPaisa numbers for parcel (order) payments.
class ParcelPaymentConfig {
  final String jazzcashNumber;
  final String jazzcashAccountName;
  final String easypaisaNumber;
  final String easypaisaAccountName;
  final String note;

  const ParcelPaymentConfig({
    this.jazzcashNumber = '',
    this.jazzcashAccountName = '',
    this.easypaisaNumber = '',
    this.easypaisaAccountName = '',
    this.note = 'Payment ke baad screenshot bhej dein.',
  });

  factory ParcelPaymentConfig.fromMap(Map<String, dynamic>? data) {
    if (data == null) return const ParcelPaymentConfig();
    return ParcelPaymentConfig(
      jazzcashNumber: (data['jazzcashNumber'] as String?)?.trim() ?? '',
      jazzcashAccountName: (data['jazzcashAccountName'] as String?)?.trim() ?? '',
      easypaisaNumber: (data['easypaisaNumber'] as String?)?.trim() ?? '',
      easypaisaAccountName: (data['easypaisaAccountName'] as String?)?.trim() ?? '',
      note: (data['note'] as String?)?.trim().isNotEmpty == true
          ? (data['note'] as String).trim()
          : 'Payment ke baad screenshot bhej dein.',
    );
  }

  Map<String, dynamic> toMap() => {
        'jazzcashNumber': jazzcashNumber,
        'jazzcashAccountName': jazzcashAccountName,
        'easypaisaNumber': easypaisaNumber,
        'easypaisaAccountName': easypaisaAccountName,
        'note': note,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  bool get hasJazzcash => jazzcashNumber.isNotEmpty;
  bool get hasEasypaisa => easypaisaNumber.isNotEmpty;
}

class ParcelPaymentService {
  final _firestore = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _ref(String tenantId) {
    return _firestore.collection('tenants').doc(tenantId).collection('settings').doc('parcelPayment');
  }

  Stream<ParcelPaymentConfig> watch(String tenantId) {
    return _ref(tenantId).snapshots().map((s) => ParcelPaymentConfig.fromMap(s.data()));
  }

  Future<ParcelPaymentConfig> load(String tenantId) async {
    final snap = await _ref(tenantId).get();
    return ParcelPaymentConfig.fromMap(snap.data());
  }

  Future<void> save(String tenantId, ParcelPaymentConfig config) {
    return _ref(tenantId).set(config.toMap(), SetOptions(merge: true));
  }
}

Future<void> openParcelPaymentSettings(BuildContext context, String tenantId) {
  return Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => ParcelPaymentSettingsScreen(tenantId: tenantId)),
  );
}

class ParcelPaymentSettingsScreen extends StatefulWidget {
  final String tenantId;

  const ParcelPaymentSettingsScreen({super.key, required this.tenantId});

  @override
  State<ParcelPaymentSettingsScreen> createState() => _ParcelPaymentSettingsScreenState();
}

class _ParcelPaymentSettingsScreenState extends State<ParcelPaymentSettingsScreen> {
  final _jazz = TextEditingController();
  final _jazzName = TextEditingController();
  final _easy = TextEditingController();
  final _easyName = TextEditingController();
  final _note = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _jazz.dispose();
    _jazzName.dispose();
    _easy.dispose();
    _easyName.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final c = await ParcelPaymentService().load(widget.tenantId);
    if (!mounted) return;
    setState(() {
      _jazz.text = c.jazzcashNumber;
      _jazzName.text = c.jazzcashAccountName;
      _easy.text = c.easypaisaNumber;
      _easyName.text = c.easypaisaAccountName;
      _note.text = c.note;
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ParcelPaymentService().save(
        widget.tenantId,
        ParcelPaymentConfig(
          jazzcashNumber: _jazz.text.trim(),
          jazzcashAccountName: _jazzName.text.trim(),
          easypaisaNumber: _easy.text.trim(),
          easypaisaAccountName: _easyName.text.trim(),
          note: _note.text.trim(),
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Parcel payment numbers saved')));
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Parcel payment (JazzCash / EasyPaisa)')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Ye numbers order WhatsApp / order detail pe customer ko dikhenge. Courier COD amount paid balance ke mutabiq set hoga.',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13, height: 1.35),
                ),
                const SizedBox(height: 20),
                const Text('JazzCash', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 8),
                TextField(
                  controller: _jazz,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d+]'))],
                  decoration: const InputDecoration(
                    labelText: 'JazzCash number',
                    hintText: '03XXXXXXXXX',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _jazzName,
                  decoration: const InputDecoration(
                    labelText: 'Account title (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                const Text('EasyPaisa', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 8),
                TextField(
                  controller: _easy,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d+]'))],
                  decoration: const InputDecoration(
                    labelText: 'EasyPaisa number',
                    hintText: '03XXXXXXXXX',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _easyName,
                  decoration: const InputDecoration(
                    labelText: 'Account title (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _note,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Note on WhatsApp',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Save'),
                ),
              ],
            ),
    );
  }
}
