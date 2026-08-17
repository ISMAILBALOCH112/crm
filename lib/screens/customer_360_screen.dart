import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/chat_service.dart';
import '../services/order_service.dart';
import '../theme/app_theme.dart';
import 'create_order_screen.dart';
import 'order_detail_screen.dart';

class Customer360Screen extends StatefulWidget {
  final String tenantId;
  final String phone;
  final String contactName;

  const Customer360Screen({
    super.key,
    required this.tenantId,
    required this.phone,
    required this.contactName,
  });

  @override
  State<Customer360Screen> createState() => _Customer360ScreenState();
}

class _Customer360ScreenState extends State<Customer360Screen> {
  final _chatService = ChatService();
  final _orderService = OrderService();
  final _cityController = TextEditingController();
  final _notesController = TextEditingController();
  final _customTagController = TextEditingController();
  StreamSubscription<List<String>>? _catalogSub;
  List<String> _catalogTags = [];
  bool _profileSeeded = false;

  static const _presetTags = ChatService.defaultInboxTags;

  String _digits(String value) => value.replaceAll(RegExp(r'\D'), '');

  bool _phoneMatch(String a, String b) {
    final da = _digits(a);
    final db = _digits(b);
    if (da.isEmpty || db.isEmpty) return false;
    if (da == db) return true;
    if (da.length >= 10 && db.length >= 10) {
      return da.substring(da.length - 10) == db.substring(db.length - 10);
    }
    return da.endsWith(db) || db.endsWith(da);
  }

  Future<void> _toggleTag(List<String> current, String tag) async {
    final next = List<String>.from(current);
    final exists = next.any((t) => t.trim().toLowerCase() == tag.toLowerCase());
    if (exists) {
      next.removeWhere((t) => t.trim().toLowerCase() == tag.toLowerCase());
    } else {
      next.add(tag);
    }
    await _chatService.updateContactProfile(
      tenantId: widget.tenantId,
      phone: widget.phone,
      tags: next,
    );
  }

  Future<void> _addCustomTag(List<String> current) async {
    final tag = _customTagController.text.trim();
    if (tag.isEmpty) return;
    if (!current.any((t) => t.trim().toLowerCase() == tag.toLowerCase())) {
      await _chatService.updateContactProfile(
        tenantId: widget.tenantId,
        phone: widget.phone,
        tags: [...current, tag],
      );
    } else {
      await _chatService.addChatTagToCatalog(widget.tenantId, tag);
    }
    _customTagController.clear();
  }

  Future<void> _saveCityNotes() async {
    await _chatService.updateContactProfile(
      tenantId: widget.tenantId,
      phone: widget.phone,
      city: _cityController.text,
      notes: _notesController.text,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved'), duration: Duration(seconds: 1)),
    );
  }

  Future<void> _call() async {
    final uri = Uri(scheme: 'tel', path: widget.phone);
    await launchUrl(uri);
  }

  @override
  void initState() {
    super.initState();
    _catalogSub = _chatService.watchChatTagCatalog(widget.tenantId).listen((tags) {
      if (mounted) setState(() => _catalogTags = tags);
    });
  }

  @override
  void dispose() {
    _catalogSub?.cancel();
    _cityController.dispose();
    _notesController.dispose();
    _customTagController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(symbol: 'Rs ', decimalDigits: 0);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF111B21)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Customer',
          style: TextStyle(color: Color(0xFF111B21), fontWeight: FontWeight.w600, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.call_outlined, color: Color(0xFF54656F)),
            onPressed: _call,
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _chatService.watchContact(widget.tenantId, widget.phone),
        builder: (context, contactSnap) {
          final data = contactSnap.data?.data() ?? {};
          final name = (data['name'] as String?)?.trim().isNotEmpty == true
              ? (data['name'] as String).trim()
              : widget.contactName;
          final tags = (data['tags'] as List<dynamic>? ?? []).map((e) => '$e').toList();
          final city = data['city'] as String? ?? '';
          final notes = data['notes'] as String? ?? '';

          if (!_profileSeeded && contactSnap.hasData) {
            _profileSeeded = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _cityController.text = city;
              _notesController.text = notes;
            });
          }

          final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
          final seenTags = <String>{};
          final allTags = <String>[];
          for (final raw in [..._presetTags, ..._catalogTags, ...tags]) {
            final tag = raw.trim();
            if (tag.isEmpty) continue;
            if (seenTags.add(tag.toLowerCase())) allTags.add(tag);
          }
          bool tagOn(String tag) => tags.any((t) => t.trim().toLowerCase() == tag.toLowerCase());

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: const Color(0xFFDFE5E7),
                    child: Text(
                      initial,
                      style: const TextStyle(
                        color: Color(0xFF54656F),
                        fontWeight: FontWeight.w700,
                        fontSize: 26,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF111B21),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.phone,
                          style: const TextStyle(fontSize: 14, color: Color(0xFF667781)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                'Tags',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF667781)),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tag in allTags)
                    FilterChip(
                      label: Text(tag),
                      selected: tagOn(tag),
                      onSelected: (_) => _toggleTag(tags, tag),
                      selectedColor: const Color(0xFFD9FDD3),
                      checkmarkColor: const Color(0xFF008069),
                      labelStyle: TextStyle(
                        color: tagOn(tag) ? const Color(0xFF008069) : const Color(0xFF54656F),
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                      side: BorderSide(
                        color: tagOn(tag) ? const Color(0xFF008069) : const Color(0xFFD1D7DB),
                      ),
                      backgroundColor: Colors.white,
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _customTagController,
                      decoration: const InputDecoration(
                        hintText: 'Custom tag',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _addCustomTag(tags),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => _addCustomTag(tags),
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF008069)),
                    child: const Text('Add'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _cityController,
                decoration: const InputDecoration(
                  labelText: 'City',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notesController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _saveCityNotes,
                  child: const Text('Save city & notes'),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Orders',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF111B21)),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      CreateOrderScreen.show(
                        context,
                        widget.tenantId,
                        initialPhone: widget.phone,
                        initialName: name,
                      );
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('New order'),
                  ),
                ],
              ),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _orderService.watchOrders(widget.tenantId),
                builder: (context, ordersSnap) {
                  final all = (ordersSnap.data?.docs ?? []).map(CrmOrder.fromDoc).toList();
                  final orders = all.where((o) => _phoneMatch(o.customerPhone, widget.phone)).toList();
                  final last = orders.isNotEmpty ? orders.first : null;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (last != null) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0F2F5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Last purchase',
                                style: TextStyle(fontSize: 12, color: Color(0xFF667781), fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${last.displayId} · ${money.format(last.totalAmount)}',
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF111B21)),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${last.itemsSummary} · ${last.status.label}',
                                style: const TextStyle(fontSize: 13, color: Color(0xFF54656F)),
                              ),
                              if (last.createdAt != null)
                                Text(
                                  DateFormat('dd MMM yyyy, hh:mm a').format(last.createdAt!),
                                  style: const TextStyle(fontSize: 12, color: Color(0xFF8696A0)),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (orders.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: Text('No orders yet', style: TextStyle(color: Color(0xFF667781))),
                          ),
                        )
                      else
                        ...orders.map((order) {
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              '${order.displayId} · ${money.format(order.totalAmount)}',
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                            subtitle: Text(
                              '${order.itemsSummary} · ${order.status.label}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            trailing: const Icon(Icons.chevron_right, color: Color(0xFF8696A0)),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => OrderDetailScreen(
                                    tenantId: widget.tenantId,
                                    orderId: order.id,
                                  ),
                                ),
                              );
                            },
                          );
                        }),
                    ],
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
