import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/bot_service.dart';
import '../../services/media_upload_service.dart';
import '../../services/tenant_service.dart';
import '../../theme/app_theme.dart';

class BotTab extends StatelessWidget {
  const BotTab({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: TenantService().watchUserProfile(),
      builder: (context, userSnap) {
        final tenantId = userSnap.data?.data()?['tenantId'] as String?;
        if (tenantId == null) {
          return const Center(child: Text('Join a business to configure the bot.'));
        }

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: TenantService().watchMembership(tenantId),
          builder: (context, memberSnap) {
            final isAdmin = memberSnap.data?.data()?['role'] == 'admin';
            return _BotEditor(tenantId: tenantId, isAdmin: isAdmin);
          },
        );
      },
    );
  }
}

class _BotEditor extends StatefulWidget {
  final String tenantId;
  final bool isAdmin;

  const _BotEditor({required this.tenantId, required this.isAdmin});

  @override
  State<_BotEditor> createState() => _BotEditorState();
}

class _BotEditorState extends State<_BotEditor> with AutomaticKeepAliveClientMixin {
  final _botService = BotService();
  final _mediaUpload = MediaUploadService();
  final _apiKeyController = TextEditingController();
  final _promptController = TextEditingController();
  final _handoffController = TextEditingController();
  final _awayController = TextEditingController();

  BotConfig? _config;
  bool _apiConfigured = false;
  bool _loading = true;
  bool _saving = false;
  bool _testingAi = false;
  bool _uploading = false;
  bool _controllersSeeded = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _promptController.dispose();
    _handoffController.dispose();
    _awayController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final configured = widget.isAdmin ? await _botService.fetchApiKeyConfigured(widget.tenantId) : false;
      if (mounted) setState(() => _apiConfigured = configured);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  void _seedControllers(BotConfig config) {
    if (_controllersSeeded) return;
    _controllersSeeded = true;
    _promptController.text = config.aiAgent.systemPrompt;
    _handoffController.text = config.aiAgent.handoffKeywords.join(', ');
    _awayController.text = config.away.message;
  }

  Future<void> _persist(BotConfig next, {String? successMessage}) async {
    if (!widget.isAdmin) return;
    setState(() {
      _config = next;
      _saving = true;
    });
    try {
      final keywords = _handoffController.text
          .split(',')
          .map((k) => k.trim())
          .where((k) => k.isNotEmpty)
          .toList();
      final toSave = next.copyWith(
        away: next.away.copyWith(message: _awayController.text.trim().isEmpty ? next.away.message : _awayController.text.trim()),
        aiAgent: BotAiAgentConfig(
          enabled: next.aiAgent.enabled,
          provider: next.aiAgent.provider,
          model: next.aiAgent.model,
          systemPrompt: _promptController.text.trim().isEmpty
              ? next.aiAgent.systemPrompt
              : _promptController.text.trim(),
          temperature: next.aiAgent.temperature,
          maxTokens: next.aiAgent.maxTokens,
          handoffKeywords: keywords.isEmpty ? next.aiAgent.handoffKeywords : keywords,
        ),
      );
      await _botService.saveConfig(widget.tenantId, toSave);
      if (!mounted) return;
      setState(() => _config = toSave);
      if (successMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(successMessage), duration: const Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e'), backgroundColor: AppColors.error),
      );
      // Reload remote so UI matches Firestore after failed write.
      try {
        final snap = await _botService.watchConfig(widget.tenantId).first;
        if (mounted) setState(() => _config = snap);
      } catch (_) {}
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleBotEnabled(bool enabled) async {
    if (_config == null) return;
    await _persist(
      _config!.copyWith(enabled: enabled),
      successMessage: enabled ? 'Bot ON' : 'Bot OFF',
    );
  }

  Future<void> _save() async {
    if (_config == null || !widget.isAdmin) return;
    await _persist(_config!, successMessage: 'Bot settings saved.');
  }

  TimeOfDay _parseTod(String hm) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(hm.trim());
    if (m == null) return const TimeOfDay(hour: 9, minute: 0);
    return TimeOfDay(hour: int.parse(m.group(1)!), minute: int.parse(m.group(2)!));
  }

  String _fmtTod(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _saveApiKey() async {
    final key = _apiKeyController.text.trim();
    if (key.isEmpty) return;
    setState(() => _saving = true);
    try {
      await _botService.saveApiKey(widget.tenantId, key);
      _apiKeyController.clear();
      setState(() => _apiConfigured = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('OpenAI API key saved securely.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _testAi() async {
    setState(() => _testingAi = true);
    try {
      final reply = await _botService.testAi(widget.tenantId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('AI connected: $reply')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _testingAi = false);
    }
  }

  Future<void> _addGreetingItem(BotResponseType type) async {
    if (_config == null) return;
    try {
      if (type == BotResponseType.text) {
        _updateGreetingResponses([
          ..._config!.greeting.responses,
          const BotResponseItem(type: BotResponseType.text, text: ''),
        ]);
        return;
      }

      setState(() => _uploading = true);

      if (type == BotResponseType.image) {
        final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
        if (picked == null) return;
        final url = await _mediaUpload.uploadImage(picked);
        _updateGreetingResponses([
          ..._config!.greeting.responses,
          BotResponseItem(type: BotResponseType.image, mediaUrl: url),
        ]);
      } else if (type == BotResponseType.video) {
        final picked = await ImagePicker().pickVideo(source: ImageSource.gallery);
        if (picked == null) return;
        final url = await _mediaUpload.uploadVideo(picked);
        _updateGreetingResponses([
          ..._config!.greeting.responses,
          BotResponseItem(type: BotResponseType.video, mediaUrl: url),
        ]);
      } else if (type == BotResponseType.audio) {
        final picked = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: const ['mp3', 'm4a', 'aac', 'ogg', 'opus', 'amr', 'wav'],
        );
        final file = picked?.files.isNotEmpty == true ? picked!.files.first : null;
        if (file == null || file.path == null) return;
        final url = await _mediaUpload.uploadAudio(file.path!);
        _updateGreetingResponses([
          ..._config!.greeting.responses,
          BotResponseItem(type: BotResponseType.audio, mediaUrl: url, voice: true, caption: file.name),
        ]);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _updateGreetingResponses(List<BotResponseItem> responses) {
    setState(() {
      _config = _config!.copyWith(
        greeting: BotGreetingConfig(enabled: _config!.greeting.enabled, responses: responses),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }

    return StreamBuilder<BotConfig>(
      stream: _botService.watchConfig(widget.tenantId),
      builder: (context, snap) {
        final remote = snap.data ?? BotConfig.defaults();
        if (_config == null) {
          _config = remote;
          _seedControllers(remote);
        } else if (snap.hasData && !_saving) {
          // Keep local edits; only adopt remote when we have no pending local state conflict.
          // Master switch is persisted immediately, so remote sync is fine after save settles.
        }

        final config = _config!;
        if (!_controllersSeeded) _seedControllers(config);

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: AppColors.cardShadow(),
                  ),
                  child: const Icon(Icons.smart_toy_rounded, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('WhatsApp Bot', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                      SizedBox(height: 2),
                      Text('Auto greeting, media replies & AI agent', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
            if (!widget.isAdmin)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Only admin can turn the bot on/off.',
                  style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w600),
                ),
              ),
            const SizedBox(height: 20),
            _SectionCard(
              title: 'Bot master switch',
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Enable bot', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  _saving
                      ? 'Saving…'
                      : (config.enabled
                          ? 'ON — replies to WhatsApp messages'
                          : 'OFF — tap to turn on (saves automatically)'),
                ),
                value: config.enabled,
                activeThumbColor: AppColors.primary,
                onChanged: widget.isAdmin && !_saving ? _toggleBotEnabled : null,
              ),
            ),
            const SizedBox(height: 14),
            _SectionCard(
              title: 'First message greeting',
              subtitle: 'Optional welcome sent once when a customer messages first time',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Send greeting', style: TextStyle(fontWeight: FontWeight.w600)),
                    value: config.greeting.enabled,
                    activeThumbColor: AppColors.primary,
                    onChanged: widget.isAdmin
                        ? (v) => setState(() {
                              _config = config.copyWith(
                                greeting: BotGreetingConfig(enabled: v, responses: config.greeting.responses),
                              );
                            })
                        : null,
                  ),
                  if (config.greeting.enabled) ...[
                    const SizedBox(height: 8),
                    ...config.greeting.responses.asMap().entries.map((entry) {
                      final i = entry.key;
                      final item = entry.value;
                      return _GreetingItemEditor(
                        item: item,
                        isAdmin: widget.isAdmin,
                        onChanged: (updated) {
                          final list = [...config.greeting.responses];
                          list[i] = updated;
                          _updateGreetingResponses(list);
                        },
                        onDelete: () {
                          final list = [...config.greeting.responses]..removeAt(i);
                          _updateGreetingResponses(list);
                        },
                      );
                    }),
                    if (widget.isAdmin) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _AddChip(label: 'Text', icon: Icons.text_fields_rounded, onTap: () => _addGreetingItem(BotResponseType.text)),
                          _AddChip(label: 'Photo', icon: Icons.image_outlined, onTap: () => _addGreetingItem(BotResponseType.image)),
                          _AddChip(label: 'Audio', icon: Icons.audio_file_rounded, onTap: () => _addGreetingItem(BotResponseType.audio)),
                          _AddChip(label: 'Video', icon: Icons.videocam_outlined, onTap: () => _addGreetingItem(BotResponseType.video)),
                        ],
                      ),
                      if (_uploading) ...[
                        const SizedBox(height: 10),
                        const Row(
                          children: [
                            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                            SizedBox(width: 8),
                            Text('Uploading file…', style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
                          ],
                        ),
                      ],
                    ],
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            _SectionCard(
              title: 'Away message + hours',
              subtitle: 'Like WhatsApp Business — auto-reply when closed or always-on away',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Send away message', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text('Works even if master bot switch is off'),
                    value: config.away.enabled,
                    activeThumbColor: AppColors.primary,
                    onChanged: widget.isAdmin
                        ? (v) => setState(() {
                              _config = config.copyWith(away: config.away.copyWith(enabled: v));
                            })
                        : null,
                  ),
                  if (config.away.enabled) ...[
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Always on (ignore hours)', style: TextStyle(fontWeight: FontWeight.w600)),
                      value: config.away.alwaysOn,
                      activeThumbColor: AppColors.primary,
                      onChanged: widget.isAdmin
                          ? (v) => setState(() {
                                _config = config.copyWith(away: config.away.copyWith(alwaysOn: v));
                              })
                          : null,
                    ),
                    TextField(
                      controller: _awayController,
                      maxLines: 3,
                      enabled: widget.isAdmin,
                      decoration: InputDecoration(
                        labelText: 'Away text',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onChanged: (v) => setState(() {
                        _config = config.copyWith(away: config.away.copyWith(message: v));
                      }),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Use business hours', style: TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('Timezone: ${config.businessHours.timezone}'),
                      value: config.businessHours.enabled,
                      activeThumbColor: AppColors.primary,
                      onChanged: widget.isAdmin
                          ? (v) => setState(() {
                                _config = config.copyWith(
                                  businessHours: config.businessHours.copyWith(enabled: v),
                                );
                              })
                          : null,
                    ),
                    if (config.businessHours.enabled)
                      ...BusinessHoursConfig.dayOrder.map((key) {
                        final day = config.businessHours.days[key] ?? const BusinessDayHours();
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 36,
                                child: Text(
                                  BusinessHoursConfig.dayLabels[key] ?? key,
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                ),
                              ),
                              Checkbox(
                                value: !day.closed,
                                onChanged: widget.isAdmin
                                    ? (v) {
                                        final next = Map<String, BusinessDayHours>.from(config.businessHours.days);
                                        next[key] = day.copyWith(closed: v != true);
                                        setState(() {
                                          _config = config.copyWith(
                                            businessHours: config.businessHours.copyWith(days: next),
                                          );
                                        });
                                      }
                                    : null,
                              ),
                              TextButton(
                                onPressed: !widget.isAdmin || day.closed
                                    ? null
                                    : () async {
                                        final t = await showTimePicker(
                                          context: context,
                                          initialTime: _parseTod(day.open),
                                        );
                                        if (t == null || !mounted) return;
                                        final next = Map<String, BusinessDayHours>.from(config.businessHours.days);
                                        next[key] = day.copyWith(open: _fmtTod(t));
                                        setState(() {
                                          _config = config.copyWith(
                                            businessHours: config.businessHours.copyWith(days: next),
                                          );
                                        });
                                      },
                                child: Text(day.closed ? '—' : day.open),
                              ),
                              const Text('–'),
                              TextButton(
                                onPressed: !widget.isAdmin || day.closed
                                    ? null
                                    : () async {
                                        final t = await showTimePicker(
                                          context: context,
                                          initialTime: _parseTod(day.close),
                                        );
                                        if (t == null || !mounted) return;
                                        final next = Map<String, BusinessDayHours>.from(config.businessHours.days);
                                        next[key] = day.copyWith(close: _fmtTod(t));
                                        setState(() {
                                          _config = config.copyWith(
                                            businessHours: config.businessHours.copyWith(days: next),
                                          );
                                        });
                                      },
                                child: Text(day.closed ? '—' : day.close),
                              ),
                            ],
                          ),
                        );
                      }),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            _SectionCard(
              title: 'AI Agent',
              subtitle: 'OpenAI reads text, voice (transcribed) & photos to reply smartly',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Enable AI replies', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(_apiConfigured ? 'API key configured' : 'Add OpenAI API key below'),
                    value: config.aiAgent.enabled,
                    activeThumbColor: AppColors.primary,
                    onChanged: widget.isAdmin && _apiConfigured
                        ? (v) => setState(() {
                              _config = config.copyWith(
                                aiAgent: BotAiAgentConfig(
                                  enabled: v,
                                  provider: config.aiAgent.provider,
                                  model: config.aiAgent.model,
                                  systemPrompt: config.aiAgent.systemPrompt,
                                  temperature: config.aiAgent.temperature,
                                  maxTokens: config.aiAgent.maxTokens,
                                  handoffKeywords: config.aiAgent.handoffKeywords,
                                ),
                              );
                            })
                        : null,
                  ),
                  if (widget.isAdmin) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: _apiKeyController,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'OpenAI API key',
                        hintText: _apiConfigured ? 'Saved — paste new key to replace' : 'sk-...',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        suffixIcon: IconButton(
                          onPressed: _saving ? null : _saveApiKey,
                          icon: const Icon(Icons.key_rounded),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: _testingAi || !_apiConfigured ? null : _testAi,
                          icon: _testingAi
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.science_outlined, size: 18),
                          label: const Text('Test AI'),
                        ),
                        const SizedBox(width: 8),
                        DropdownButton<String>(
                          value: config.aiAgent.model,
                          items: const [
                            DropdownMenuItem(value: 'gpt-4o-mini', child: Text('gpt-4o-mini')),
                            DropdownMenuItem(value: 'gpt-4o', child: Text('gpt-4o')),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() {
                              _config = config.copyWith(
                                aiAgent: BotAiAgentConfig(
                                  enabled: config.aiAgent.enabled,
                                  provider: config.aiAgent.provider,
                                  model: v,
                                  systemPrompt: config.aiAgent.systemPrompt,
                                  temperature: config.aiAgent.temperature,
                                  maxTokens: config.aiAgent.maxTokens,
                                  handoffKeywords: config.aiAgent.handoffKeywords,
                                ),
                              );
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _promptController,
                      maxLines: 5,
                      decoration: InputDecoration(
                        labelText: 'AI training prompt',
                        hintText: 'Use {businessName} in your instructions...',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _handoffController,
                      decoration: InputDecoration(
                        labelText: 'Handoff keywords (comma separated)',
                        hintText: 'human, agent, person',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (widget.isAdmin) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _saving
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Save bot settings', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                ),
              ),
            ] else
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Text('Only admins can edit bot settings.', style: TextStyle(color: AppColors.textSecondary)),
              ),
          ],
        );
      },
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;

  const _SectionCard({required this.title, this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppDecorations.card(radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.textPrimary)),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _AddChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _AddChip({required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 16, color: AppColors.primary),
      label: Text(label),
      onPressed: onTap,
    );
  }
}

class _GreetingItemEditor extends StatefulWidget {
  final BotResponseItem item;
  final bool isAdmin;
  final ValueChanged<BotResponseItem> onChanged;
  final VoidCallback onDelete;

  const _GreetingItemEditor({
    required this.item,
    required this.isAdmin,
    required this.onChanged,
    required this.onDelete,
  });

  @override
  State<_GreetingItemEditor> createState() => _GreetingItemEditorState();
}

class _GreetingItemEditorState extends State<_GreetingItemEditor> {
  late TextEditingController _textController;
  late TextEditingController _captionController;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.item.text ?? '');
    _captionController = TextEditingController(text: widget.item.caption ?? '');
  }

  @override
  void didUpdateWidget(covariant _GreetingItemEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.text != widget.item.text) {
      _textController.text = widget.item.text ?? '';
    }
    if (oldWidget.item.caption != widget.item.caption) {
      _captionController.text = widget.item.caption ?? '';
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _captionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final typeLabel = switch (item.type) {
      BotResponseType.text => 'Text',
      BotResponseType.image => 'Photo',
      BotResponseType.audio => 'Audio',
      BotResponseType.video => 'Video',
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_iconForType(item.type), size: 18, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(typeLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              if (widget.isAdmin)
                IconButton(onPressed: widget.onDelete, icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 20)),
            ],
          ),
          if (item.type == BotResponseType.text)
            TextField(
              enabled: widget.isAdmin,
              controller: _textController,
              onChanged: (v) => widget.onChanged(item.copyWith(text: v)),
              decoration: InputDecoration(
                hintText: 'Greeting message text',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                isDense: true,
              ),
            )
          else ...[
            if (item.type == BotResponseType.audio)
              Row(
                children: [
                  const Icon(Icons.audiotrack_rounded, size: 16, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      item.caption?.trim().isNotEmpty == true ? item.caption! : 'Audio file attached',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                    ),
                  ),
                ],
              )
            else if (item.mediaUrl != null)
              Text(
                item.mediaUrl!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            if (item.type == BotResponseType.image || item.type == BotResponseType.video)
              TextField(
                enabled: widget.isAdmin,
                controller: _captionController,
                onChanged: (v) => widget.onChanged(item.copyWith(caption: v)),
                decoration: InputDecoration(
                  hintText: 'Caption (optional)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  isDense: true,
                ),
              ),
          ],
        ],
      ),
    );
  }

  IconData _iconForType(BotResponseType type) => switch (type) {
        BotResponseType.text => Icons.text_fields_rounded,
        BotResponseType.image => Icons.image_outlined,
        BotResponseType.audio => Icons.mic_rounded,
        BotResponseType.video => Icons.videocam_outlined,
      };
}
