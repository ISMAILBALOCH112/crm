import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/chat_service.dart';
import '../../services/tenant_service.dart';
import '../../theme/app_theme.dart';
import 'chat_conversation_screen.dart';

class ChatTab extends StatefulWidget {
  const ChatTab({super.key});

  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> {
  static const _filters = ['All', 'Unread', 'Favorites', 'Groups'];
  int _selectedFilter = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'CRM',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.photo_camera_outlined, color: AppColors.textSecondary),
                onPressed: () {},
              ),
              IconButton(
                icon: const Icon(Icons.more_vert_rounded, color: AppColors.textSecondary),
                onPressed: () {},
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceSolid,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.surfaceBorder),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.search_rounded, color: AppColors.textSecondary, size: 20),
                const SizedBox(width: 10),
                Text(
                  'Ask Meta AI or Search',
                  style: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.9), fontSize: 14.5),
                ),
              ],
            ),
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _filters.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final isSelected = index == _selectedFilter;
              return GestureDetector(
                onTap: () => setState(() => _selectedFilter = index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    gradient: isSelected ? AppColors.primaryGradient : null,
                    color: isSelected ? null : AppColors.surfaceSolid,
                    borderRadius: BorderRadius.circular(20),
                    border: isSelected ? null : Border.all(color: AppColors.surfaceBorder),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _filters[index],
                    style: TextStyle(
                      color: isSelected ? Colors.white : AppColors.textSecondary,
                      fontSize: 13.5,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Material(
          color: Colors.transparent,
          child: ListTile(
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.archive_outlined, color: AppColors.primary, size: 20),
            ),
            title: const Text(
              'Archived',
              style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 15),
            ),
            onTap: () {},
          ),
        ),
        const Divider(height: 1, color: AppColors.surfaceBorder),
        Expanded(
          child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: TenantService().watchUserProfile(),
            builder: (context, userSnapshot) {
              final tenantId = userSnapshot.data?.data()?['tenantId'] as String?;
              if (tenantId == null) return const SizedBox.shrink();
              return _ContactList(tenantId: tenantId);
            },
          ),
        ),
      ],
    );
  }
}

class _ContactList extends StatelessWidget {
  final String tenantId;

  const _ContactList({required this.tenantId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: ChatService().watchContacts(tenantId),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Center(
            child: Text('No chats yet', style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
          );
        }

        return ListView.separated(
          itemCount: docs.length,
          separatorBuilder: (_, _) => const Divider(height: 1, color: AppColors.surfaceBorder, indent: 78),
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data();
            return _ContactRow(
              tenantId: tenantId,
              phone: doc.id,
              name: data['name'] as String? ?? doc.id,
              lastMessageAt: (data['lastMessageAt'] as Timestamp?)?.toDate(),
            );
          },
        );
      },
    );
  }
}

class _ContactRow extends StatelessWidget {
  final String tenantId;
  final String phone;
  final String name;
  final DateTime? lastMessageAt;

  const _ContactRow({required this.tenantId, required this.phone, required this.name, this.lastMessageAt});

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final day = DateTime(dt.year, dt.month, dt.day);

    if (day == today) return DateFormat('h:mm a').format(dt);
    if (day == yesterday) return 'Yesterday';
    return DateFormat('d/M/yy').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Material(
      color: Colors.transparent,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 48,
          height: 48,
          decoration: const BoxDecoration(gradient: AppColors.primaryGradient, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Text(initial, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
        ),
        title: Text(
          name,
          style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 15.5),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          phone,
          style: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.9), fontSize: 13),
          overflow: TextOverflow.ellipsis,
        ),
        trailing: lastMessageAt != null
            ? Text(
                _formatTime(lastMessageAt!),
                style: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.8), fontSize: 12),
              )
            : null,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => ChatConversationScreen(tenantId: tenantId, phone: phone, contactName: name),
            ),
          );
        },
      ),
    );
  }
}
