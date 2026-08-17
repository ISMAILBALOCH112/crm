import 'package:flutter/material.dart';

import '../services/chat_service.dart';
import '../theme/app_theme.dart';

Future<void> showWaTemplatePicker({
  required BuildContext context,
  required String tenantId,
  required String phone,
  required String contactName,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _WaTemplateSheet(
      tenantId: tenantId,
      phone: phone,
      contactName: contactName,
    ),
  );
}

class _WaTemplateSheet extends StatefulWidget {
  final String tenantId;
  final String phone;
  final String contactName;

  const _WaTemplateSheet({
    required this.tenantId,
    required this.phone,
    required this.contactName,
  });

  @override
  State<_WaTemplateSheet> createState() => _WaTemplateSheetState();
}

class _WaTemplateSheetState extends State<_WaTemplateSheet> {
  final _chat = ChatService();
  late Future<List<WaTemplate>> _future;
  WaTemplate? _selected;
  final _bodyControllers = <TextEditingController>[];
  final _headerControllers = <TextEditingController>[];
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _future = _chat.listWaTemplates(widget.tenantId);
  }

  @override
  void dispose() {
    for (final c in _bodyControllers) {
      c.dispose();
    }
    for (final c in _headerControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _select(WaTemplate template) {
    for (final c in _bodyControllers) {
      c.dispose();
    }
    for (final c in _headerControllers) {
      c.dispose();
    }
    _bodyControllers
      ..clear()
      ..addAll(List.generate(template.bodyVarCount, (_) => TextEditingController()));
    _headerControllers
      ..clear()
      ..addAll(List.generate(template.headerVarCount, (_) => TextEditingController()));
    // Prefill first body var with contact name when present.
    if (_bodyControllers.isNotEmpty && widget.contactName.trim().isNotEmpty) {
      _bodyControllers.first.text = widget.contactName.trim();
    }
    setState(() {
      _selected = template;
      _error = null;
    });
  }

  Future<void> _send() async {
    final template = _selected;
    if (template == null || _sending) return;

    for (final c in [..._headerControllers, ..._bodyControllers]) {
      if (c.text.trim().isEmpty) {
        setState(() => _error = 'Fill all template variables.');
        return;
      }
    }

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      final components = <Map<String, dynamic>>[];
      if (_headerControllers.isNotEmpty) {
        components.add({
          'type': 'header',
          'parameters': [
            for (final c in _headerControllers) {'type': 'text', 'text': c.text.trim()},
          ],
        });
      }
      if (_bodyControllers.isNotEmpty) {
        components.add({
          'type': 'body',
          'parameters': [
            for (final c in _bodyControllers) {'type': 'text', 'text': c.text.trim()},
          ],
        });
      }

      await _chat.sendTemplate(
        tenantId: widget.tenantId,
        to: widget.phone,
        name: template.name,
        languageCode: template.language,
        components: components.isEmpty ? null : components,
      );
      await _chat.rememberContactName(
        tenantId: widget.tenantId,
        phone: widget.phone,
        name: widget.contactName,
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Template sent: ${template.name}')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
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
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text(
                'Send template',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.textPrimary),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                '24h window closed — only Meta-approved templates can be sent.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ),
            Expanded(
              child: FutureBuilder<List<WaTemplate>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator(color: AppColors.primary));
                  }
                  if (snap.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        '${snap.error}'.replaceFirst('Exception: ', ''),
                        style: const TextStyle(color: AppColors.error),
                      ),
                    );
                  }
                  final templates = snap.data ?? [];
                  if (templates.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'No approved templates found. Create one in Meta Business Suite → WhatsApp → Message templates.',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    );
                  }

                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      for (final t in templates)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Material(
                            color: _selected?.name == t.name && _selected?.language == t.language
                                ? AppColors.primary.withValues(alpha: 0.08)
                                : AppColors.surfaceSolid,
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () => _select(t),
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: _selected?.name == t.name && _selected?.language == t.language
                                        ? AppColors.primary
                                        : AppColors.surfaceBorder,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      t.displayLabel,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      t.language,
                                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                    ),
                                    if (t.bodyText.isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      Text(
                                        t.bodyText,
                                        style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.35),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (_selected != null) ...[
                        const SizedBox(height: 8),
                        if (_headerControllers.isNotEmpty)
                          const Text('Header variables', style: TextStyle(fontWeight: FontWeight.w700)),
                        for (var i = 0; i < _headerControllers.length; i++) ...[
                          const SizedBox(height: 8),
                          TextField(
                            controller: _headerControllers[i],
                            decoration: InputDecoration(
                              labelText: 'Header {{${i + 1}}}',
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ],
                        if (_bodyControllers.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          const Text('Body variables', style: TextStyle(fontWeight: FontWeight.w700)),
                        ],
                        for (var i = 0; i < _bodyControllers.length; i++) ...[
                          const SizedBox(height: 8),
                          TextField(
                            controller: _bodyControllers[i],
                            decoration: InputDecoration(
                              labelText: 'Body {{${i + 1}}}',
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ],
                      ],
                    ],
                  );
                },
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SafeArea(
                top: false,
                child: FilledButton(
                  onPressed: _selected == null || _sending ? null : _send,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Send template', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
