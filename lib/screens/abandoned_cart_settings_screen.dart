import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/chat_service.dart';
import '../theme/app_theme.dart';

Future<void> openAbandonedCartSettings(BuildContext context, String tenantId) {
  return Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => AbandonedCartSettingsScreen(tenantId: tenantId)),
  );
}

class AbandonedCartSettingsScreen extends StatefulWidget {
  final String tenantId;

  const AbandonedCartSettingsScreen({super.key, required this.tenantId});

  @override
  State<AbandonedCartSettingsScreen> createState() => _AbandonedCartSettingsScreenState();
}

class _AbandonedCartSettingsScreenState extends State<AbandonedCartSettingsScreen> {
  final _delayController = TextEditingController(text: '60');
  final _messageController = TextEditingController(
    text:
        'Assalam o Alaikum! Aap se contact kiya tha — koi reply nahi aaya. Order / madad chahiye to reply karein, ya "agent" likhein.',
  );
  final _templateController = TextEditingController();
  final _langController = TextEditingController(text: 'en_US');

  bool _enabled = false;
  bool _onManualSend = true;
  bool _onCatalog = true;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<WaTemplate> _templates = [];

  DocumentReference<Map<String, dynamic>> get _ref => FirebaseFirestore.instance
      .collection('tenants')
      .doc(widget.tenantId)
      .collection('settings')
      .doc('abandonedCart');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _delayController.dispose();
    _messageController.dispose();
    _templateController.dispose();
    _langController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final snap = await _ref.get();
      final data = snap.data() ?? {};
      List<WaTemplate> templates = [];
      try {
        templates = await ChatService().listWaTemplates(widget.tenantId);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _enabled = data['enabled'] == true;
        _onManualSend = data['onManualSend'] != false;
        _onCatalog = data['onCatalog'] != false;
        _delayController.text = '${(data['delayMinutes'] as num?)?.toInt() ?? 60}';
        final msg = (data['message'] as String?)?.trim();
        if (msg != null && msg.isNotEmpty) _messageController.text = msg;
        _templateController.text = (data['templateName'] as String?)?.trim() ?? '';
        _langController.text = (data['templateLanguage'] as String?)?.trim().isNotEmpty == true
            ? (data['templateLanguage'] as String).trim()
            : 'en_US';
        _templates = templates;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _save() async {
    final delay = int.tryParse(_delayController.text.trim()) ?? 60;
    if (_messageController.text.trim().isEmpty) {
      setState(() => _error = 'Open-window message is required');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _ref.set({
        'enabled': _enabled,
        'onManualSend': _onManualSend,
        'onCatalog': _onCatalog,
        'delayMinutes': delay.clamp(5, 24 * 60),
        'message': _messageController.text.trim(),
        'templateName': _templateController.text.trim(),
        'templateLanguage': _langController.text.trim().isEmpty ? 'en_US' : _langController.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Auto follow-up settings saved')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
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
        title: const Text('Auto follow-up', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'Auto reminder un chats pe jahan tumne (ya bot ne) msg bheja, customer ne reply / order nahi diya. '
                  'Jis chat mein order create ho chuka ho us pe msg nahi jayega. '
                  '24h band hone pe Meta template use hoga.',
                  style: TextStyle(color: AppColors.textSecondary, height: 1.4),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Enable auto follow-up', style: TextStyle(fontWeight: FontWeight.w600)),
                  value: _enabled,
                  activeThumbColor: AppColors.primary,
                  onChanged: (v) => setState(() => _enabled = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('After manual CRM send', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Catalog / chat se jab tum msg bhejo'),
                  value: _onManualSend,
                  activeThumbColor: AppColors.primary,
                  onChanged: (v) => setState(() => _onManualSend = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('After bot catalog', style: TextStyle(fontWeight: FontWeight.w600)),
                  value: _onCatalog,
                  activeThumbColor: AppColors.primary,
                  onChanged: (v) => setState(() => _onCatalog = v),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _delayController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Delay (minutes)',
                    helperText: 'Min 5 — no reply / no order ke baad follow-up',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _messageController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Message (when 24h window is open)',
                  ),
                ),
                const SizedBox(height: 16),
                const Text('24h closed → Meta template', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                if (_templates.isNotEmpty)
                  DropdownButtonFormField<String>(
                    value: _templateController.text.isEmpty
                        ? null
                        : _templates.any((t) => t.name == _templateController.text)
                            ? _templateController.text
                            : null,
                    decoration: const InputDecoration(labelText: 'Template'),
                    items: [
                      for (final t in _templates)
                        DropdownMenuItem(value: t.name, child: Text('${t.name} (${t.language})')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      final t = _templates.firstWhere((e) => e.name == v);
                      setState(() {
                        _templateController.text = t.name;
                        _langController.text = t.language;
                      });
                    },
                  )
                else
                  TextField(
                    controller: _templateController,
                    decoration: const InputDecoration(
                      labelText: 'Template name',
                      helperText: 'Required for outside-24h follow-ups',
                    ),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: _langController,
                  decoration: const InputDecoration(labelText: 'Template language', hintText: 'en_US'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: AppColors.error)),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Save'),
                ),
              ],
            ),
    );
  }
}
