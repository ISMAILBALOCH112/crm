import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/whatsapp_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/primary_button.dart';

/// Bottom sheet where a tenant admin pastes their own Meta App Secret /
/// Phone Number ID / Access Token to connect their WhatsApp number.
Future<void> showConnectWhatsappSheet(BuildContext context, String tenantId) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _ConnectWhatsappSheet(tenantId: tenantId),
  );
}

class _ConnectWhatsappSheet extends StatefulWidget {
  final String tenantId;

  const _ConnectWhatsappSheet({required this.tenantId});

  @override
  State<_ConnectWhatsappSheet> createState() => _ConnectWhatsappSheetState();
}

class _ConnectWhatsappSheetState extends State<_ConnectWhatsappSheet> {
  final _formKey = GlobalKey<FormState>();
  final _phoneNumberIdController = TextEditingController();
  final _accessTokenController = TextEditingController();
  final _appSecretController = TextEditingController();
  final _wabaIdController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _phoneNumberIdController.dispose();
    _accessTokenController.dispose();
    _appSecretController.dispose();
    _wabaIdController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await WhatsappService().connect(
        tenantId: widget.tenantId,
        phoneNumberId: _phoneNumberIdController.text.trim(),
        accessToken: _accessTokenController.text.trim(),
        appSecret: _appSecretController.text.trim(),
        wabaId: _wabaIdController.text.trim().isEmpty ? null : _wabaIdController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      _showFinishSetupDialog(context, result);
    } catch (e) {
      setState(() => _errorMessage = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceBorder,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Connect WhatsApp',
                  style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 18),
                ),
                const SizedBox(height: 6),
                Text(
                  'Paste the credentials from your Meta App (WhatsApp → API Setup).',
                  style: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.9), fontSize: 13),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _phoneNumberIdController,
                  decoration: const InputDecoration(labelText: 'Phone Number ID'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Phone Number ID is required' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _accessTokenController,
                  decoration: const InputDecoration(labelText: 'Access Token'),
                  maxLines: 2,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Access Token is required' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _appSecretController,
                  decoration: const InputDecoration(labelText: 'App Secret'),
                  obscureText: true,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'App Secret is required' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _wabaIdController,
                  decoration: const InputDecoration(
                    labelText: 'WhatsApp Business Account ID (optional)',
                    helperText: 'Needed for templates. Meta Business Suite → WhatsApp accounts.',
                  ),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 14),
                  Text(_errorMessage!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
                ],
                const SizedBox(height: 22),
                PrimaryButton(label: 'Connect', isLoading: _isLoading, onPressed: _submit),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void _showFinishSetupDialog(BuildContext context, WhatsappConnectResult result) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppColors.surfaceSolid,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Almost Done', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${result.phoneNumber} is verified. Now paste these into your Meta App Dashboard '
            '(WhatsApp → Configuration → Webhook) and subscribe to messages:',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 16),
          _CopyableField(label: 'Callback URL', value: result.webhookUrl),
          const SizedBox(height: 12),
          _CopyableField(label: 'Verify Token', value: result.verifyToken),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
      ],
    ),
  );
}

class _CopyableField extends StatelessWidget {
  final String label;
  final String value;

  const _CopyableField({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: () {
            Clipboard.setData(ClipboardData(text: value));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('$label copied'), duration: const Duration(seconds: 2)),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.surfaceBorder),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 12.5),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.copy_rounded, color: AppColors.primary, size: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
