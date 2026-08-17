import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/invoice_branding.dart';
import '../services/media_upload_service.dart';
import '../theme/app_theme.dart';

Future<void> openInvoiceBrandingScreen(BuildContext context, String tenantId) {
  return Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => InvoiceBrandingScreen(tenantId: tenantId)),
  );
}

class InvoiceBrandingScreen extends StatefulWidget {
  final String tenantId;

  const InvoiceBrandingScreen({super.key, required this.tenantId});

  @override
  State<InvoiceBrandingScreen> createState() => _InvoiceBrandingScreenState();
}

class _InvoiceBrandingScreenState extends State<InvoiceBrandingScreen> {
  final _colorController = TextEditingController(text: '#5B7FFF');
  String? _logoUrl;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  static const _presets = ['#5B7FFF', '#25D366', '#E85D75', '#0F766E', '#7C3AED', '#EA580C'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _colorController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final snap = await FirebaseFirestore.instance.collection('tenants').doc(widget.tenantId).get();
    final data = snap.data() ?? {};
    final branding = InvoiceBranding.fromTenant(data);
    if (!mounted) return;
    setState(() {
      _logoUrl = branding.logoUrl;
      _colorController.text = branding.brandColorHex;
      _loading = false;
    });
  }

  Future<void> _pickLogo() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 800);
    if (picked == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final url = await MediaUploadService().uploadImage(picked);
      await FirebaseFirestore.instance.collection('tenants').doc(widget.tenantId).set(
        {'invoiceLogoUrl': url, 'updatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
      if (!mounted) return;
      setState(() => _logoUrl = url);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveColor() async {
    var hex = _colorController.text.trim();
    if (!hex.startsWith('#')) hex = '#$hex';
    if (!RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(hex)) {
      setState(() => _error = 'Use a hex color like #5B7FFF');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await FirebaseFirestore.instance.collection('tenants').doc(widget.tenantId).set(
        {'invoiceBrandColor': hex.toUpperCase(), 'updatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invoice brand color saved'), duration: Duration(seconds: 2)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _clearLogo() async {
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance.collection('tenants').doc(widget.tenantId).set(
        {'invoiceLogoUrl': FieldValue.delete()},
        SetOptions(merge: true),
      );
      if (!mounted) return;
      setState(() => _logoUrl = null);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text('Invoice branding', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'Logo and color appear on shared / WhatsApp invoices.',
                  style: TextStyle(color: AppColors.textSecondary, height: 1.35),
                ),
                const SizedBox(height: 20),
                Center(
                  child: CircleAvatar(
                    radius: 44,
                    backgroundColor: AppColors.surfaceSolid,
                    backgroundImage: _logoUrl != null ? NetworkImage(_logoUrl!) : null,
                    child: _logoUrl == null
                        ? const Icon(Icons.storefront_rounded, color: AppColors.primary, size: 36)
                        : null,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: _saving ? null : _pickLogo,
                        style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                        child: const Text('Upload logo'),
                      ),
                    ),
                    if (_logoUrl != null) ...[
                      const SizedBox(width: 10),
                      TextButton(onPressed: _saving ? null : _clearLogo, child: const Text('Remove')),
                    ],
                  ],
                ),
                const SizedBox(height: 28),
                const Text('Brand color', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final c in _presets)
                      GestureDetector(
                        onTap: () => setState(() => _colorController.text = c),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Color(InvoiceBranding(brandColorHex: c).brandColorInt),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _colorController.text.toUpperCase() == c
                                  ? AppColors.textPrimary
                                  : AppColors.surfaceBorder,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _colorController,
                  decoration: const InputDecoration(
                    labelText: 'Hex color',
                    hintText: '#5B7FFF',
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: AppColors.error)),
                ],
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: _saving ? null : _saveColor,
                  style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Save color'),
                ),
              ],
            ),
    );
  }
}
