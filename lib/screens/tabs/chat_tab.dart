import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/chat_service.dart';
import '../../services/order_service.dart';
import '../../services/tenant_service.dart';
import '../../theme/app_theme.dart';
import '../broadcast_screen.dart';
import '../order_stats_screen.dart';
import '../phone_contacts_screen.dart';
import 'chat_conversation_screen.dart';

enum _ChatFilter { all, unread, favorites, muted }

class ChatTab extends StatefulWidget {
  const ChatTab({super.key});

  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> {
  final _searchController = TextEditingController();
  final _chatService = ChatService();

  _ChatFilter _selectedFilter = _ChatFilter.all;
  bool _showingArchived = false;
  final Set<String> _selectedPhones = {};
  String? _tagFilter;

  static const _selectGreen = Color(0xFFD9FDD3);
  static const _waGreen = Color(0xFF25D366);

  bool get _selecting => _selectedPhones.isNotEmpty;

  void _clearSelection() => setState(() => _selectedPhones.clear());

  void _toggleSelect(ChatContact contact) {
    setState(() {
      if (_selectedPhones.contains(contact.phone)) {
        _selectedPhones.remove(contact.phone);
      } else {
        _selectedPhones.add(contact.phone);
      }
    });
  }

  void _startSelect(ChatContact contact) {
    setState(() {
      _selectedPhones
        ..clear()
        ..add(contact.phone);
    });
  }

  Future<void> _bulkFavorite(String tenantId) async {
    final phones = _selectedPhones.toList();
    for (final phone in phones) {
      await _chatService.setFavorite(tenantId: tenantId, phone: phone, isFavorite: true);
    }
    if (!mounted) return;
    _clearSelection();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${phones.length} chat(s) pinned')),
    );
  }

  Future<void> _bulkArchive(String tenantId, {required bool archived}) async {
    final phones = _selectedPhones.toList();
    for (final phone in phones) {
      await _chatService.setArchived(tenantId: tenantId, phone: phone, isArchived: archived);
    }
    if (!mounted) return;
    _clearSelection();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(archived ? '${phones.length} archived' : '${phones.length} unarchived')),
    );
  }

  Future<void> _bulkMute(String tenantId) async {
    final phones = _selectedPhones.toList();
    for (final phone in phones) {
      await _chatService.setMuted(tenantId: tenantId, phone: phone, isMuted: true);
    }
    if (!mounted) return;
    _clearSelection();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${phones.length} muted')),
    );
  }

  Future<void> _promptAddTag(String tenantId) async {
    final tag = await showDialog<String>(
      context: context,
      builder: (ctx) => _AddTagDialog(
        applyToSelected: _selecting,
        selectedCount: _selectedPhones.length,
      ),
    );
    if (tag == null || tag.isEmpty || !mounted) return;

    if (_selecting) {
      await _chatService.addTagToContacts(
        tenantId: tenantId,
        phones: _selectedPhones.toList(),
        tag: tag,
      );
      _clearSelection();
    } else {
      await _chatService.addChatTagToCatalog(tenantId, tag);
    }
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _tagFilter = tag);
    });
  }

  Future<void> _applyTagToSelected(String tenantId, String tag) async {
    final phones = _selectedPhones.toList();
    await _chatService.addTagToContacts(tenantId: tenantId, phones: phones, tag: tag);
    if (!mounted) return;
    _clearSelection();
    setState(() => _tagFilter = tag);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('"$tag" added to ${phones.length} chat(s)')),
    );
  }

  Future<void> _confirmArchive(String tenantId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete chats?'),
        content: Text(
          '${_selectedPhones.length} chat(s) archive ho jayengi — list se hatengi, baad me Archived se wapas la sakte ho.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _bulkArchive(tenantId, archived: true);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openConversation(String tenantId, ChatContact contact) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ChatConversationScreen(
          tenantId: tenantId,
          phone: contact.phone,
          contactName: contact.name,
        ),
      ),
    );
  }

  Future<void> _openStats() async {
    await OrderStatsScreen.open(context);
  }

  Future<void> _openNewChat(String tenantId) async {
    final result = await _showNewChatSheet(context);
    if (result == null || !mounted) return;

    // Don't save to chats until a message is sent — open conversation only.
    await _openConversation(
      tenantId,
      ChatContact(phone: result.phone, name: result.name ?? result.phone),
    );
  }

  Future<void> _openFromPhoneContacts(String tenantId) async {
    await openPhoneContactsPicker(context, tenantId: tenantId);
  }

  Future<void> _markAllRead(String tenantId) async {
    await _chatService.markAllRead(tenantId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('All chats marked as read'), duration: Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: TenantService().watchUserProfile(),
      builder: (context, userSnapshot) {
        final tenantId = userSnapshot.data?.data()?['tenantId'] as String?;
        if (tenantId == null) return const SizedBox.shrink();

        return Stack(
          children: [
            Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                decoration: BoxDecoration(
                  color: _selecting ? _selectGreen : Colors.transparent,
                  borderRadius: BorderRadius.circular(_selecting ? 12 : 0),
                ),
                child: Row(
                  children: [
                    if (_selecting)
                      IconButton(
                        icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
                        onPressed: _clearSelection,
                      )
                    else if (_showingArchived)
                      IconButton(
                        icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
                        onPressed: () => setState(() => _showingArchived = false),
                      )
                    else
                      const SizedBox(width: 8),
                    Expanded(
                      child: _selecting
                          ? Text(
                              '${_selectedPhones.length}',
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                              ),
                            )
                          : _showingArchived
                              ? const Text(
                                  'Archived',
                                  style: TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 26,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.3,
                                  ),
                                )
                              : ShaderMask(
                                  shaderCallback: (bounds) => AppColors.primaryGradient.createShader(bounds),
                                  child: const Text(
                                    'WaTech',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 26,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                ),
                    ),
                    if (_selecting) ...[
                      IconButton(
                        tooltip: 'Mute',
                        icon: const Icon(Icons.notifications_off_outlined, color: AppColors.textPrimary),
                        onPressed: () => _bulkMute(tenantId),
                      ),
                      IconButton(
                        tooltip: 'Pin',
                        icon: const Icon(Icons.push_pin_outlined, color: AppColors.textPrimary),
                        onPressed: () => _bulkFavorite(tenantId),
                      ),
                      IconButton(
                        tooltip: 'Delete',
                        icon: const Icon(Icons.delete_outline_rounded, color: AppColors.textPrimary),
                        onPressed: () => _confirmArchive(tenantId),
                      ),
                      IconButton(
                        tooltip: _showingArchived ? 'Unarchive' : 'Archive',
                        icon: Icon(
                          _showingArchived ? Icons.unarchive_outlined : Icons.archive_outlined,
                          color: AppColors.textPrimary,
                        ),
                        onPressed: () {
                          if (_showingArchived) {
                            _bulkArchive(tenantId, archived: false);
                          } else {
                            _confirmArchive(tenantId);
                          }
                        },
                      ),
                    ] else ...[
                      IconButton(
                        tooltip: 'Order stats',
                        icon: ShaderMask(
                          shaderCallback: (bounds) => const LinearGradient(
                            colors: [Color(0xFFFFD700), Color(0xFFFF7FA6), Color(0xFF8B5CF6)],
                          ).createShader(bounds),
                          child: const Icon(Icons.insights_rounded, color: Colors.white, size: 26),
                        ),
                        onPressed: _openStats,
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert_rounded, color: AppColors.textSecondary),
                        color: AppColors.surfaceSolid,
                        onSelected: (value) {
                          switch (value) {
                            case 'contacts':
                              _openFromPhoneContacts(tenantId);
                            case 'new':
                              _openNewChat(tenantId);
                            case 'archived':
                              setState(() => _showingArchived = true);
                            case 'read':
                              _markAllRead(tenantId);
                            case 'broadcast':
                              openBroadcastScreen(context, tenantId);
                            case 'templates':
                              openBroadcastScreen(context, tenantId);
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(value: 'contacts', child: Text('Phone contacts')),
                          const PopupMenuItem(value: 'new', child: Text('New chat (manual)')),
                          const PopupMenuItem(value: 'broadcast', child: Text('Broadcast')),
                          const PopupMenuItem(value: 'templates', child: Text('Templates')),
                          const PopupMenuItem(value: 'archived', child: Text('Archived chats')),
                          const PopupMenuItem(value: 'read', child: Text('Mark all as read')),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceSolid,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.surfaceBorder),
                  boxShadow: AppColors.cardShadow(AppColors.accent),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    const Icon(Icons.search_rounded, color: AppColors.textSecondary, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        textInputAction: TextInputAction.search,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: 'Search name or number',
                          hintStyle: TextStyle(
                            color: AppColors.textSecondary.withValues(alpha: 0.9),
                            fontSize: 14.5,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          isCollapsed: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14.5),
                      ),
                    ),
                    if (_searchController.text.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          _searchController.clear();
                          setState(() {});
                        },
                        child: const Icon(Icons.close_rounded, color: AppColors.textSecondary, size: 18),
                      ),
                  ],
                ),
              ),
            ),
            if (!_showingArchived) ...[
              _InboxFilterBar(
                tenantId: tenantId,
                selectedFilter: _selectedFilter,
                tagFilter: _tagFilter,
                selecting: _selecting,
                onSelectFilter: (filter) => setState(() {
                  _selectedFilter = filter;
                  _tagFilter = null;
                }),
                onSelectTag: (tag) => setState(() {
                  _tagFilter = tag;
                  _selectedFilter = _ChatFilter.all;
                }),
                onAddTag: () => _promptAddTag(tenantId),
                onApplyTag: (tag) => _applyTagToSelected(tenantId, tag),
              ),
              const SizedBox(height: 4),
              Material(
                color: Colors.transparent,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.archive_outlined, color: AppColors.primary, size: 20),
                  ),
                  title: const Text(
                    'Archived',
                    style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w500, fontSize: 15),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary, size: 20),
                  onTap: () => setState(() => _showingArchived = true),
                ),
              ),
              const Divider(height: 1, color: AppColors.surfaceBorder, indent: 16, endIndent: 16),
            ],
            Expanded(
              child: _ContactList(
                tenantId: tenantId,
                query: _searchController.text.trim(),
                filter: _selectedFilter,
                tagFilter: _tagFilter,
                showingArchived: _showingArchived,
                selectedPhones: _selectedPhones,
                selecting: _selecting,
                selectionColor: _selectGreen,
                checkColor: _waGreen,
                onOpen: (contact) {
                  if (_selecting) {
                    _toggleSelect(contact);
                  } else {
                    _openConversation(tenantId, contact);
                  }
                },
                onLongPress: (contact) {
                  if (_selecting) {
                    _toggleSelect(contact);
                  } else {
                    _startSelect(contact);
                  }
                },
              ),
            ),
          ],
            ),
            if (!_showingArchived && !_selecting)
              Positioned(
                right: 18,
                bottom: 18,
                child: Material(
                  color: const Color(0xFF25D366),
                  borderRadius: BorderRadius.circular(16),
                  elevation: 4,
                  shadowColor: Colors.black26,
                  child: InkWell(
                    onTap: () => _openFromPhoneContacts(tenantId),
                    borderRadius: BorderRadius.circular(16),
                      child: const SizedBox(
                      width: 58,
                      height: 58,
                      child: Icon(Icons.add_comment_rounded, color: Colors.white, size: 28),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ContactList extends StatefulWidget {
  final String tenantId;
  final String query;
  final _ChatFilter filter;
  final String? tagFilter;
  final bool showingArchived;
  final Set<String> selectedPhones;
  final bool selecting;
  final Color selectionColor;
  final Color checkColor;
  final ValueChanged<ChatContact> onOpen;
  final ValueChanged<ChatContact> onLongPress;

  const _ContactList({
    required this.tenantId,
    required this.query,
    required this.filter,
    this.tagFilter,
    required this.showingArchived,
    required this.selectedPhones,
    required this.selecting,
    required this.selectionColor,
    required this.checkColor,
    required this.onOpen,
    required this.onLongPress,
  });

  @override
  State<_ContactList> createState() => _ContactListState();
}

class _ContactListState extends State<_ContactList> {
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _contactsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _ordersSub;
  List<ChatContact> _contacts = const [];
  QuerySnapshot<Map<String, dynamic>>? _ordersSnap;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _bind();
    });
  }

  @override
  void didUpdateWidget(_ContactList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tenantId != widget.tenantId) _bind();
  }

  void _bind() {
    _contactsSub?.cancel();
    _ordersSub?.cancel();
    _contactsSub = ChatService().watchContacts(widget.tenantId).listen((snap) {
      if (!mounted) return;
      final next = snap.docs.map(ChatContact.fromDoc).toList();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _contacts = next);
      });
    });
    _ordersSub = OrderService().watchRecentOrders(widget.tenantId).listen((snap) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _ordersSnap = snap);
      });
    });
  }

  @override
  void dispose() {
    _contactsSub?.cancel();
    _ordersSub?.cancel();
    super.dispose();
  }

  List<ChatContact> _applyFilters(List<ChatContact> contacts) {
    var result = widget.showingArchived
        ? contacts.where((c) => c.isArchived)
        : contacts.where((c) => !c.isArchived);

    if (!widget.showingArchived) {
      result = switch (widget.filter) {
        _ChatFilter.all => result,
        _ChatFilter.unread => result.where((c) => c.isUnread),
        _ChatFilter.favorites => result.where((c) => c.isFavorite || c.isPinned),
        _ChatFilter.muted => result.where((c) => c.isMuted),
      };
    }

    if (widget.tagFilter != null && widget.tagFilter!.isNotEmpty) {
      final tag = widget.tagFilter!.toLowerCase();
      result = result.where((c) => c.tags.any((t) => t.trim().toLowerCase() == tag));
    }

    if (widget.query.isNotEmpty) {
      final q = widget.query.toLowerCase();
      result = result.where((c) => c.name.toLowerCase().contains(q) || c.phone.contains(q));
    }

    final list = result.toList();
    list.sort((a, b) {
      final pinCmp = (b.isPinned ? 1 : 0).compareTo(a.isPinned ? 1 : 0);
      if (pinCmp != 0) return pinCmp;
      final at = a.lastMessageAt;
      final bt = b.lastMessageAt;
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });
    return list;
  }

  String _emptyMessage({required bool noChatsAtAll}) {
    if (widget.query.isNotEmpty) return 'No chats found';
    if (widget.showingArchived) return 'No archived chats';
    if (noChatsAtAll) return 'No chats yet';
    if (widget.tagFilter != null && widget.tagFilter!.isNotEmpty) return 'No chats with this tag';
    return switch (widget.filter) {
      _ChatFilter.all => 'No chats yet',
      _ChatFilter.unread => 'No unread chats',
      _ChatFilter.favorites => 'Long-press a chat to add it to favorites',
      _ChatFilter.muted => 'No muted chats',
    };
  }

  String _digits(String phone) => phone.replaceAll(RegExp(r'\D'), '');

  Map<String, PaymentStatus> _paymentByPhone() {
    final snap = _ordersSnap;
    final map = <String, PaymentStatus>{};
    if (snap == null) return map;
    for (final doc in snap.docs) {
      final order = CrmOrder.fromDoc(doc);
      if (order.status == OrderStatus.cancelled || order.status == OrderStatus.returned) {
        continue;
      }
      final key = _digits(order.customerPhone);
      if (key.isEmpty) continue;
      map.putIfAbsent(key, () => order.paymentStatus);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final all = _contacts;
    final docs = _applyFilters(all);

    if (docs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            _emptyMessage(noChatsAtAll: all.where((c) => !c.isArchived).isEmpty),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ),
        ),
      );
    }

    final payments = _paymentByPhone();
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: docs.length,
      separatorBuilder: (_, _) => const Divider(height: 1, color: AppColors.surfaceBorder, indent: 72),
      itemBuilder: (context, index) {
        final contact = docs[index];
        return _ContactRow(
          contact: contact,
          paymentStatus: payments[_digits(contact.phone)],
          selected: widget.selectedPhones.contains(contact.phone),
          selectionColor: widget.selectionColor,
          checkColor: widget.checkColor,
          onTap: () => widget.onOpen(contact),
          onLongPress: () => widget.onLongPress(contact),
        );
      },
    );
  }
}

class _ContactRow extends StatelessWidget {
  final ChatContact contact;
  final PaymentStatus? paymentStatus;
  final bool selected;
  final Color selectionColor;
  final Color checkColor;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _ContactRow({
    required this.contact,
    required this.paymentStatus,
    required this.selected,
    required this.selectionColor,
    required this.checkColor,
    required this.onTap,
    required this.onLongPress,
  });

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final day = DateTime(dt.year, dt.month, dt.day);

    if (day == today) return DateFormat('h:mm a').format(dt);
    if (day == yesterday) return 'Yesterday';
    return DateFormat('d/M/yy').format(dt);
  }

  List<_ChatTag> _tags() {
    const paymentLabels = {'unpaid', 'paid', 'partial', 'cod pending'};
    final chips = <_ChatTag>[];

    if (paymentStatus != null) {
      chips.add(_ChatTag.payment(paymentStatus!));
    }

    for (final raw in contact.tags) {
      final tag = raw.trim();
      if (tag.isEmpty) continue;
      if (paymentStatus != null && paymentLabels.contains(tag.toLowerCase())) continue;
      chips.add(_ChatTag.custom(tag));
    }
    return chips.take(4).toList();
  }

  /// Name if real; otherwise phone — never both.
  String _displayTitle(ChatContact contact) {
    final name = contact.name.trim();
    final phone = contact.phone.trim();
    if (name.isEmpty) return phone;
    final nameDigits = name.replaceAll(RegExp(r'\D'), '');
    final phoneDigits = phone.replaceAll(RegExp(r'\D'), '');
    if (name == phone || (nameDigits.isNotEmpty && nameDigits == phoneDigits)) {
      return phone;
    }
    return name;
  }

  @override
  Widget build(BuildContext context) {
    final title = _displayTitle(contact);
    final initial = title.isNotEmpty ? title[0].toUpperCase() : '?';
    final unread = contact.isUnread;
    final timeColor = unread ? AppColors.primary : AppColors.textSecondary.withValues(alpha: 0.8);
    final tags = _tags();
    final preview = contact.lastMessageText?.trim();
    final hasPreview = preview != null && preview.isNotEmpty;

    return Material(
      color: selected ? selectionColor : Colors.transparent,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        onTap: onTap,
        onLongPress: onLongPress,
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: AppColors.primary.withValues(alpha: 0.12),
              child: Text(
                initial,
                style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 17),
              ),
            ),
            if (selected)
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: checkColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(Icons.check, color: Colors.white, size: 12),
                ),
              ),
          ],
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                title,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: unread ? FontWeight.w600 : FontWeight.w500,
                  fontSize: 15,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (tags.isNotEmpty) ...[
              const SizedBox(width: 6),
              Flexible(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: [
                      for (var i = 0; i < tags.length; i++) ...[
                        if (i > 0) const SizedBox(width: 4),
                        _TagChip(tag: tags[i]),
                      ],
                    ],
                  ),
                ),
              ),
            ],
            if (contact.isMuted)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(Icons.notifications_off_rounded, color: AppColors.textSecondary, size: 14),
              ),
            if (contact.isPinned)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(Icons.push_pin_rounded, color: AppColors.textSecondary, size: 14),
              )
            else if (contact.isFavorite)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(Icons.star_rounded, color: AppColors.accentWarm, size: 15),
              ),
          ],
        ),
        subtitle: !hasPreview &&
                (contact.assigneeName == null || contact.assigneeName!.trim().isEmpty)
            ? null
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hasPreview)
                    Text(
                      contact.listPreview,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        fontWeight: unread ? FontWeight.w500 : FontWeight.w400,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (contact.assigneeName != null && contact.assigneeName!.trim().isNotEmpty)
                    Padding(
                      padding: EdgeInsets.only(top: hasPreview ? 2 : 0),
                      child: Text(
                        contact.assigneeName!,
                        style: TextStyle(
                          color: AppColors.textSecondary.withValues(alpha: 0.85),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
        trailing: contact.lastMessageAt == null && !unread
            ? null
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (contact.lastMessageAt != null)
                    Text(_formatTime(contact.lastMessageAt!), style: TextStyle(color: timeColor, fontSize: 12)),
                  if (unread) ...[
                    const SizedBox(height: 4),
                    if (contact.unreadCount > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          contact.unreadCount > 99 ? '99+' : '${contact.unreadCount}',
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      )
                    else
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                      ),
                  ],
                ],
              ),
      ),
    );
  }
}

class _ChatTag {
  final String label;
  final Color color;
  final Color background;

  const _ChatTag({required this.label, required this.color, required this.background});

  factory _ChatTag.payment(PaymentStatus status) {
    return switch (status) {
      PaymentStatus.paid => const _ChatTag(
          label: 'Paid',
          color: Color(0xFF047857),
          background: Color(0xFFD1FAE5),
        ),
      PaymentStatus.partial => const _ChatTag(
          label: 'Partial',
          color: Color(0xFFB45309),
          background: Color(0xFFFEF3C7),
        ),
      PaymentStatus.unpaid => const _ChatTag(
          label: 'Unpaid',
          color: Color(0xFFBE123C),
          background: Color(0xFFFFE4E6),
        ),
    };
  }

  factory _ChatTag.custom(String raw) {
    final key = raw.trim().toLowerCase();
    final (Color color, Color bg) = switch (key) {
      'vip' => (const Color(0xFF6D28D9), const Color(0xFFEDE9FE)),
      'returning' => (const Color(0xFF0369A1), const Color(0xFFE0F2FE)),
      'hot lead' || 'hot' => (const Color(0xFFC2410C), const Color(0xFFFFEDD5)),
      'new' => (const Color(0xFF1D4ED8), const Color(0xFFDBEAFE)),
      'cod pending' => (const Color(0xFFB45309), const Color(0xFFFEF3C7)),
      'unpaid' => (const Color(0xFFBE123C), const Color(0xFFFFE4E6)),
      'paid' => (const Color(0xFF047857), const Color(0xFFD1FAE5)),
      'partial' => (const Color(0xFFB45309), const Color(0xFFFEF3C7)),
      _ => (AppColors.primary, AppColors.primary.withValues(alpha: 0.12)),
    };
    return _ChatTag(label: raw.trim(), color: color, background: bg);
  }
}

class _TagChip extends StatelessWidget {
  final _ChatTag tag;

  const _TagChip({required this.tag});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: tag.background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tag.color.withValues(alpha: 0.18)),
      ),
      child: Text(
        tag.label,
        style: TextStyle(
          color: tag.color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          height: 1.1,
          letterSpacing: 0.15,
        ),
      ),
    );
  }
}

class _NewChatResult {
  final String phone;
  final String? name;

  const _NewChatResult({required this.phone, this.name});
}

Future<_NewChatResult?> _showNewChatSheet(BuildContext context) {
  return showModalBottomSheet<_NewChatResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const _NewChatSheet(),
  );
}

class _NewChatSheet extends StatefulWidget {
  const _NewChatSheet();

  @override
  State<_NewChatSheet> createState() => _NewChatSheetState();
}

class _NewChatSheetState extends State<_NewChatSheet> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _phoneController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final phone = _phoneController.text.replaceAll(RegExp(r'\D'), '');
    final name = _nameController.text.trim();
    Navigator.of(context).pop(_NewChatResult(phone: phone, name: name.isEmpty ? null : name));
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
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'New chat',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                'Enter the WhatsApp number with country code',
                style: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.95), fontSize: 13),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Phone number',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
                validator: (value) {
                  final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
                  if (digits.length < 7) return 'Enter a valid number with country code';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Name (optional)',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('Open chat', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InboxFilterBar extends StatefulWidget {
  const _InboxFilterBar({
    required this.tenantId,
    required this.selectedFilter,
    required this.tagFilter,
    required this.selecting,
    required this.onSelectFilter,
    required this.onSelectTag,
    required this.onAddTag,
    required this.onApplyTag,
  });

  final String tenantId;
  final _ChatFilter selectedFilter;
  final String? tagFilter;
  final bool selecting;
  final ValueChanged<_ChatFilter> onSelectFilter;
  final ValueChanged<String?> onSelectTag;
  final VoidCallback onAddTag;
  final ValueChanged<String> onApplyTag;

  @override
  State<_InboxFilterBar> createState() => _InboxFilterBarState();
}

class _InboxFilterBarState extends State<_InboxFilterBar> {
  final _chatService = ChatService();
  StreamSubscription<List<String>>? _catalogSub;
  List<String> _tags = [];

  static const _statusChips = <(_ChatFilter, String)>[
    (_ChatFilter.all, 'All'),
    (_ChatFilter.unread, 'Unread'),
    (_ChatFilter.favorites, 'Favorites'),
    (_ChatFilter.muted, 'Muted'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _bind(widget.tenantId);
    });
  }

  @override
  void didUpdateWidget(_InboxFilterBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tenantId != widget.tenantId) {
      _bind(widget.tenantId);
    }
  }

  void _bind(String tenantId) {
    _catalogSub?.cancel();
    _catalogSub = _chatService.watchChatTagCatalog(tenantId).listen((catalog) {
      _applyTags(catalog);
    });
  }

  void _applyTags(List<String> catalog) {
    if (!mounted) return;
    final merged = _mergeTags([...ChatService.defaultInboxTags, ...catalog]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_sameTagLists(_tags, merged)) return;
      setState(() => _tags = merged);
    });
  }

  bool _sameTagLists(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].toLowerCase() != b[i].toLowerCase()) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _catalogSub?.cancel();
    super.dispose();
  }

  List<String> _mergeTags(Iterable<String> sources) {
    final seen = <String>{};
    final out = <String>[];
    for (final raw in sources) {
      final tag = raw.trim();
      if (tag.isEmpty) continue;
      if (seen.add(tag.toLowerCase())) out.add(tag);
    }
    out.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return out;
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
  }) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          gradient: selected ? AppColors.primaryGradient : null,
          color: selected ? null : AppColors.surfaceSolid,
          borderRadius: BorderRadius.circular(20),
          border: selected ? null : Border.all(color: AppColors.surfaceBorder),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.textSecondary,
            fontSize: 13.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedKey = widget.tagFilter?.toLowerCase();
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final (filter, label) in _statusChips) ...[
            _chip(
              label: label,
              selected: widget.tagFilter == null && filter == widget.selectedFilter,
              onTap: () => widget.onSelectFilter(filter),
            ),
            const SizedBox(width: 8),
          ],
          for (final tag in _tags) ...[
            _chip(
              label: tag,
              selected: selectedKey == tag.toLowerCase(),
              onTap: () => widget.onSelectTag(selectedKey == tag.toLowerCase() ? null : tag),
              onLongPress: widget.selecting ? () => widget.onApplyTag(tag) : null,
            ),
            const SizedBox(width: 8),
          ],
          _chip(
            label: '+',
            selected: false,
            onTap: widget.onAddTag,
          ),
        ],
      ),
    );
  }
}

class _AddTagDialog extends StatefulWidget {
  final bool applyToSelected;
  final int selectedCount;

  const _AddTagDialog({required this.applyToSelected, required this.selectedCount});

  @override
  State<_AddTagDialog> createState() => _AddTagDialogState();
}

class _AddTagDialogState extends State<_AddTagDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final tag = _controller.text.trim();
    if (tag.isEmpty) return;
    Navigator.pop(context, tag);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add tag'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              hintText: 'e.g. VIP, Follow-up',
              labelText: 'Tag name',
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (widget.applyToSelected) ...[
            const SizedBox(height: 12),
            Text(
              'Ye tag ${widget.selectedCount} selected chat(s) pe lag jayega.',
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Add')),
      ],
    );
  }
}
