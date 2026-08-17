import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../config/backend_config.dart';
import '../services/chat_service.dart';
import '../services/subscription_service.dart';
import '../theme/app_theme.dart';

Future<void> openBroadcastScreen(BuildContext context, String tenantId) {
  return Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => BroadcastScreen(tenantId: tenantId)),
  );
}

class BroadcastScreen extends StatefulWidget {
  final String tenantId;

  const BroadcastScreen({super.key, required this.tenantId});

  @override
  State<BroadcastScreen> createState() => _BroadcastScreenState();
}

class _BroadcastScreenState extends State<BroadcastScreen> {
  final _nameController = TextEditingController();
  final _textController = TextEditingController();
  final _tagController = TextEditingController();

  String _audience = 'all';
  String _mode = 'template';
  WaTemplate? _selectedTemplate;
  List<WaTemplate> _templates = [];
  List<Map<String, dynamic>> _history = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _textController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final chat = ChatService();
      final templates = await chat.listWaTemplates(widget.tenantId);
      final history = await _listBroadcasts();
      if (!mounted) return;
      setState(() {
        _templates = templates;
        _history = history;
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

  Future<List<Map<String, dynamic>>> _listBroadcasts() async {
    final idToken = await FirebaseAuth.instance.currentUser!.getIdToken();
    final response = await http.get(
      Uri.parse('$backendBaseUrl/tenants/${widget.tenantId}/broadcasts'),
      headers: {'Authorization': 'Bearer $idToken'},
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw Exception(data['error'] ?? 'Could not load broadcasts');
    }
    return ((data['broadcasts'] as List?) ?? []).cast<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<void> _send() async {
    final billing = await SubscriptionService().fetchBilling(widget.tenantId);
    if (!billing.writeAllowed) {
      setState(() => _error = SubscriptionService.readOnlyMessage);
      return;
    }
    if (_mode == 'template' && _selectedTemplate == null) {
      setState(() => _error = 'Pick a Meta template');
      return;
    }
    if (_mode == 'text' && _textController.text.trim().isEmpty) {
      setState(() => _error = 'Enter message text');
      return;
    }
    if (_audience == 'tag' && _tagController.text.trim().isEmpty) {
      setState(() => _error = 'Enter a contact tag');
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      final idToken = await FirebaseAuth.instance.currentUser!.getIdToken();
      final body = <String, dynamic>{
        'name': _nameController.text.trim(),
        'audience': _audience,
        if (_audience == 'tag') 'tag': _tagController.text.trim(),
        'mode': _mode,
        if (_mode == 'text') 'text': _textController.text.trim(),
        if (_mode == 'template') ...{
          'templateName': _selectedTemplate!.name,
          'languageCode': _selectedTemplate!.language,
        },
      };
      final response = await http.post(
        Uri.parse('$backendBaseUrl/tenants/${widget.tenantId}/broadcasts'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $idToken'},
        body: jsonEncode(body),
      );
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        throw Exception(data['error'] ?? 'Broadcast failed');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Queued for ${data['total']} contacts')),
      );
      await _bootstrap();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text('Broadcast', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        actions: [
          IconButton(onPressed: _loading ? null : _bootstrap, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'Outside the 24h window, use a Meta-approved template. Text works only when the chat window is open.',
                  style: TextStyle(color: AppColors.textSecondary, height: 1.35),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Campaign name (optional)'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _audience,
                  decoration: const InputDecoration(labelText: 'Audience'),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All contacts')),
                    DropdownMenuItem(value: 'tag', child: Text('By tag')),
                  ],
                  onChanged: (v) => setState(() => _audience = v ?? 'all'),
                ),
                if (_audience == 'tag') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _tagController,
                    decoration: const InputDecoration(labelText: 'Tag', hintText: 'e.g. vip'),
                  ),
                ],
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _mode,
                  decoration: const InputDecoration(labelText: 'Message type'),
                  items: const [
                    DropdownMenuItem(value: 'template', child: Text('Meta template')),
                    DropdownMenuItem(value: 'text', child: Text('Free text')),
                  ],
                  onChanged: (v) => setState(() => _mode = v ?? 'template'),
                ),
                const SizedBox(height: 12),
                if (_mode == 'template')
                  DropdownButtonFormField<WaTemplate>(
                    value: _selectedTemplate,
                    decoration: const InputDecoration(labelText: 'Template'),
                    items: [
                      for (final t in _templates)
                        DropdownMenuItem(value: t, child: Text(t.displayLabel, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => setState(() => _selectedTemplate = v),
                  )
                else
                  TextField(
                    controller: _textController,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: 'Message'),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: AppColors.error)),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _sending ? null : _send,
                  style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                  child: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Queue broadcast'),
                ),
                const SizedBox(height: 28),
                const Text('Recent', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 10),
                if (_history.isEmpty)
                  const Text('No broadcasts yet.', style: TextStyle(color: AppColors.textSecondary))
                else
                  for (final b in _history)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(b['name']?.toString() ?? 'Broadcast', style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        '${b['status']} · ${b['sent']}/${b['total']} sent'
                        '${(b['failed'] as num?) != null && (b['failed'] as num) > 0 ? ' · ${b['failed']} failed' : ''}',
                      ),
                    ),
              ],
            ),
    );
  }
}
