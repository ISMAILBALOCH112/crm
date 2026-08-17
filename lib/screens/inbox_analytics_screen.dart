import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/chat_service.dart';
import '../theme/app_theme.dart';

Future<void> openInboxAnalytics(BuildContext context, String tenantId) {
  return Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => InboxAnalyticsScreen(tenantId: tenantId)),
  );
}

class InboxAnalyticsScreen extends StatelessWidget {
  final String tenantId;

  const InboxAnalyticsScreen({super.key, required this.tenantId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Inbox analytics')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: ChatService().watchContacts(tenantId),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final contacts = snap.data!.docs.map(ChatContact.fromDoc).where((c) => !c.isArchived).toList();
          final unread = contacts.where((c) => c.isUnread).toList();
          final muted = contacts.where((c) => c.isMuted).length;
          final unassigned = contacts.where((c) => (c.assigneeUid == null || c.assigneeUid!.isEmpty)).length;
          final assigned = contacts.length - unassigned;

          Duration? oldestUnreadAge;
          for (final c in unread) {
            final at = c.lastMessageAt;
            if (at == null) continue;
            final age = DateTime.now().difference(at);
            if (oldestUnreadAge == null || age > oldestUnreadAge) oldestUnreadAge = age;
          }

          String ageLabel(Duration? d) {
            if (d == null) return '—';
            if (d.inDays >= 1) return '${d.inDays}d';
            if (d.inHours >= 1) return '${d.inHours}h';
            return '${d.inMinutes}m';
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Live from your CRM inbox (not Meta Business stats).',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
              const SizedBox(height: 16),
              _StatGrid(
                items: [
                  _Stat('Open chats', '${contacts.length}'),
                  _Stat('Unread', '${unread.length}'),
                  _Stat('Muted', '$muted'),
                  _Stat('Assigned', '$assigned'),
                  _Stat('Unassigned', '$unassigned'),
                  _Stat('Oldest unread', ageLabel(oldestUnreadAge)),
                ],
              ),
              const SizedBox(height: 20),
              const Text('Oldest unread chats', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 8),
              ...() {
                final sorted = [...unread]
                  ..sort((a, b) {
                    final aa = a.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
                    final bb = b.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
                    return aa.compareTo(bb);
                  });
                final top = sorted.take(8).toList();
                if (top.isEmpty) {
                  return [
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: Text('No unread chats')),
                    ),
                  ];
                }
                return top
                    .map(
                      (c) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(c.listPreview, maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: Text(
                          ageLabel(c.lastMessageAt == null ? null : DateTime.now().difference(c.lastMessageAt!)),
                          style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.primary),
                        ),
                      ),
                    )
                    .toList();
              }(),
            ],
          );
        },
      ),
    );
  }
}

class _Stat {
  final String label;
  final String value;
  const _Stat(this.label, this.value);
}

class _StatGrid extends StatelessWidget {
  final List<_Stat> items;
  const _StatGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final s in items)
          Container(
            width: (MediaQuery.sizeOf(context).width - 42) / 2,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surfaceSolid,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.surfaceBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(s.label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
              ],
            ),
          ),
      ],
    );
  }
}
