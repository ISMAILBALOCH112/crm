import 'package:flutter/material.dart';

import '../services/chat_service.dart';
import '../theme/app_theme.dart';

/// Bottom sheet: pick a quick reply, or manage (add/edit/delete) the list.
Future<void> showQuickRepliesSheet({
  required BuildContext context,
  required String tenantId,
  required String contactName,
  required ValueChanged<String> onInsert,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => QuickRepliesSheet(
      tenantId: tenantId,
      contactName: contactName,
      onSelect: (reply) {
        final text = reply.text.replaceAll('{{name}}', contactName);
        Navigator.pop(ctx);
        onInsert(text);
      },
    ),
  );
}

class QuickRepliesSheet extends StatefulWidget {
  final String tenantId;
  final String contactName;
  final ValueChanged<QuickReply> onSelect;

  const QuickRepliesSheet({
    super.key,
    required this.tenantId,
    required this.contactName,
    required this.onSelect,
  });

  @override
  State<QuickRepliesSheet> createState() => _QuickRepliesSheetState();
}

class _QuickRepliesSheetState extends State<QuickRepliesSheet> {
  final _chatService = ChatService();
  bool _managing = false;

  Future<void> _save(List<QuickReply> items) async {
    try {
      await _chatService.saveQuickReplies(widget.tenantId, items);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _showEditDialog(List<QuickReply> current, {QuickReply? existing}) async {
    final shortcutCtrl = TextEditingController(text: existing?.shortcut ?? '');
    final textCtrl = TextEditingController(text: existing?.text ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'Add quick reply' : 'Edit quick reply'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: shortcutCtrl,
              decoration: const InputDecoration(
                labelText: 'Shortcut',
                hintText: 'e.g. /hello',
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: textCtrl,
              decoration: const InputDecoration(
                labelText: 'Message',
                hintText: 'Hi {{name}}!',
              ),
              minLines: 2,
              maxLines: 5,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: Text(existing == null ? 'Add' : 'Save'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final text = textCtrl.text.trim();
    if (text.isEmpty) return;
    final next = List<QuickReply>.from(current);
    if (existing == null) {
      next.add(QuickReply(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        shortcut: shortcutCtrl.text.trim(),
        text: text,
      ));
    } else {
      final i = next.indexWhere((e) => e.id == existing.id);
      if (i >= 0) {
        next[i] = QuickReply(
          id: existing.id,
          shortcut: shortcutCtrl.text.trim(),
          text: text,
        );
      }
    }
    await _save(next);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.52,
        minChildSize: 0.35,
        maxChildSize: 0.9,
        builder: (context, scrollController) {
          return StreamBuilder<List<QuickReply>>(
            stream: _chatService.watchQuickReplies(widget.tenantId),
            builder: (context, snap) {
              final items = snap.data ?? const <QuickReply>[];
              return Column(
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                    child: Row(
                      children: [
                        Text(
                          _managing ? 'Manage quick replies' : 'Quick replies',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF111B21),
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => setState(() => _managing = !_managing),
                          child: Text(_managing ? 'Done' : 'Manage'),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: items.isEmpty
                        ? ListView(
                            controller: scrollController,
                            children: [
                              const SizedBox(height: 36),
                              const Icon(Icons.bolt_outlined, size: 40, color: Color(0xFF8696A0)),
                              const SizedBox(height: 12),
                              const Text(
                                'No quick replies yet',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Color(0xFF667781), fontSize: 14),
                              ),
                              const SizedBox(height: 8),
                              Center(
                                child: TextButton.icon(
                                  onPressed: () => _showEditDialog(items),
                                  icon: const Icon(Icons.add),
                                  label: const Text('Add reply'),
                                ),
                              ),
                            ],
                          )
                        : ListView.separated(
                            controller: scrollController,
                            itemCount: items.length + (_managing ? 1 : 0),
                            separatorBuilder: (_, _) => const Divider(height: 1, indent: 16),
                            itemBuilder: (context, index) {
                              if (_managing && index == items.length) {
                                return ListTile(
                                  leading: const Icon(Icons.add_circle_outline, color: AppColors.primary),
                                  title: const Text('Add quick reply'),
                                  onTap: () => _showEditDialog(items),
                                );
                              }
                              final reply = items[index];
                              if (_managing) {
                                return ListTile(
                                  title: Text(
                                    reply.shortcut.isEmpty ? reply.text : reply.shortcut,
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  subtitle: reply.shortcut.isEmpty
                                      ? null
                                      : Text(reply.text, maxLines: 2, overflow: TextOverflow.ellipsis),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.edit_outlined, size: 20),
                                        onPressed: () => _showEditDialog(items, existing: reply),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, size: 20, color: AppColors.error),
                                        onPressed: () async {
                                          final next = items.where((e) => e.id != reply.id).toList();
                                          await _save(next);
                                        },
                                      ),
                                    ],
                                  ),
                                );
                              }
                              return ListTile(
                                leading: const Icon(Icons.bolt, color: Color(0xFF075E54)),
                                title: Text(
                                  reply.shortcut.isEmpty ? reply.text : reply.shortcut,
                                  style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF111B21)),
                                ),
                                subtitle: reply.shortcut.isEmpty
                                    ? null
                                    : Text(
                                        reply.text.replaceAll('{{name}}', widget.contactName),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(color: Color(0xFF667781), fontSize: 13),
                                      ),
                                onTap: () => widget.onSelect(reply),
                              );
                            },
                          ),
                  ),
                  SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
