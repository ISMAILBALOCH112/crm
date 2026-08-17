import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:record/record.dart';
import 'package:video_player/video_player.dart';

import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/cloudinary_config.dart';
import '../../data/chat_gif_sticker_data.dart';
import '../../services/chat_service.dart';
import '../../services/subscription_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/chat_ad_referral_card.dart';
import '../../widgets/chat_attach_sheet.dart';
import '../../widgets/chat_emoji_panel.dart';
import '../../widgets/chat_media_bubbles.dart';
import '../../widgets/chat_media_viewer.dart';
import '../../widgets/quick_replies_sheet.dart';
import '../../widgets/voice_record_panel.dart';
import '../../widgets/wa_template_sheet.dart';
import '../chat_camera_screen.dart';
import '../chat_media_preview_screen.dart';
import '../customer_360_screen.dart';
import '../create_order_screen.dart';
import '../catalog_screen.dart';
import '../parcel_payment_settings_screen.dart';

// WhatsApp Android â€” simple rounded rect + one sharp top corner (no SVG tail).
class _WaMetrics {
  _WaMetrics._();

  static const bubbleRadius = 7.5;
  static const tailCornerRadius = 2.0;
  static const bubblePaddingH = 7.0;
  static const bubblePaddingV = 6.0;
  static const edgeMargin = 8.0;
  static const oppositeMargin = 56.0;
  static const bubbleMaxWidthFactor = 0.85;

  static const groupGap = 2.0;
  static const senderGap = 10.0;

  static const messageFontSize = 14.2;
  static const messageLineHeight = 1.25;
  static const messageColor = Color(0xFF111B21);

  static const metaFontSize = 11.0;
  static const metaColor = Color(0xFF667781);
  static const metaHeight = 14.0;
  static const tickGap = 3.0;
}

// Real WhatsApp colors, deliberately not the app's pink theme â€” this screen
// is meant to read as an authentic WhatsApp conversation.
class _WaColors {
  _WaColors._();
  static const chatBackground = Color(0xFFECE5DD);
  static const outboundBubble = Color(0xFFD9FDD3);
  static const inboundBubble = Color(0xFFFFFFFF);
  static const tickGrey = Color(0xFF8696A0);
  static const tickBlue = Color(0xFF34B7F1);
  static const inputBarGreen = Color(0xFF075E54);
  static const inputIconGrey = Color(0xFF8696A0);
}

class _PendingOutbound {
  final String id;
  final String type;
  final String text;
  final DateTime at;
  final String? replyPreview;
  final String? localPath;
  Uint8List? bytes;
  String? remoteUrl;

  _PendingOutbound({
    required this.id,
    this.type = 'text',
    required this.text,
    required this.at,
    this.replyPreview,
    this.localPath,
    this.bytes,
  });
}

// A generic (not WhatsApp's actual copyrighted artwork) scattered doodle
// pattern, echoing the spirit of WhatsApp's chat wallpaper without copying
// it â€” faint outline icons tiled at a fixed, seeded layout so it doesn't
// reshuffle on every rebuild.
class _ChatWallpaperPainter extends CustomPainter {
  const _ChatWallpaperPainter();

  static const _icons = [
    Icons.star_border_rounded,
    Icons.favorite_border_rounded,
    Icons.local_florist_outlined,
    Icons.cake_outlined,
    Icons.camera_alt_outlined,
    Icons.music_note_outlined,
    Icons.card_giftcard_outlined,
    Icons.shopping_cart_outlined,
    Icons.local_cafe_outlined,
    Icons.headphones_outlined,
    Icons.lightbulb_outline,
    Icons.rocket_launch_outlined,
    Icons.emoji_emotions_outlined,
    Icons.pets_outlined,
    Icons.beach_access_outlined,
    Icons.wb_sunny_outlined,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    const spacing = 62.0;
    const iconSize = 20.0;
    final color = Colors.black.withValues(alpha: 0.04);
    final random = Random(7);

    final cols = (size.width / spacing).ceil() + 1;
    final rows = (size.height / spacing).ceil() + 2;

    for (var row = 0; row < rows; row++) {
      final rowOffsetX = row.isOdd ? spacing / 2 : 0.0;
      for (var col = 0; col < cols; col++) {
        final icon = _icons[random.nextInt(_icons.length)];
        final jitterX = random.nextDouble() * 10 - 5;
        final jitterY = random.nextDouble() * 10 - 5;
        final dx = col * spacing + rowOffsetX + jitterX;
        final dy = row * spacing + jitterY;

        final textPainter = TextPainter(
          text: TextSpan(
            text: String.fromCharCode(icon.codePoint),
            style: TextStyle(
              fontSize: iconSize,
              fontFamily: icon.fontFamily,
              package: icon.fontPackage,
              color: color,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();

        textPainter.paint(canvas, Offset(dx, dy));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ChatWallpaperPainter oldDelegate) => false;
}

class ChatConversationScreen extends StatefulWidget {
  final String tenantId;
  final String phone;
  final String contactName;

  const ChatConversationScreen({
    super.key,
    required this.tenantId,
    required this.phone,
    required this.contactName,
  });

  @override
  State<ChatConversationScreen> createState() => _ChatConversationScreenState();
}

class _ChatConversationScreenState extends State<ChatConversationScreen> {
  final _chatService = ChatService();
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  final _recorder = AudioRecorder();
  bool _isSending = false;
  bool _isRecording = false;
  bool _micHolding = false;
  bool _micLocked = false;
  bool _emojiOpen = false;
  String? _recordPath;
  DateTime? _recordStartedAt;
  double _holdDx = 0;
  double _holdDy = 0;
  Offset? _holdOrigin;
  Timer? _holdTicker;
  String? _selfPhotoUrl;
  String _selfLetter = 'Y';
  final Set<String> _selectedIds = {};
  bool _didInitialJump = false;
  Map<String, dynamic>? _replyTo;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _latestDocs = const [];
  final List<_PendingOutbound> _pending = [];
  DateTime? _lastCustomerMessageAt;
  String? _lastListDocId;
  bool _messagesSnapReady = false;

  final _searchController = TextEditingController();
  bool _searchOpen = false;
  String _searchQuery = '';

  int _initialUnreadCount = 0;
  String? _firstUnreadId;
  bool _unreadSeparatorReady = false;
  bool _unreadCaptured = false;

  String? _assigneeUid;
  String? _assigneeName;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _contactSub;

  bool get _selecting => _selectedIds.isNotEmpty;

  void _clearSelection() => setState(() => _selectedIds.clear());

  void _toggleMessageSelect(String id, {String? direction}) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _startMessageSelect(String id, {String? direction}) {
    setState(() {
      _selectedIds
        ..clear()
        ..add(id);
    });
  }

  Future<void> _deleteSelected() async {
    final ids = _selectedIds.toList();
    if (ids.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete for me?'),
        content: Text(
          ids.length == 1
              ? 'Removed from your inbox only â€” customer still sees it on WhatsApp.'
              : 'Remove ${ids.length} messages from your inbox only â€” customer still sees them on WhatsApp.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete for me'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _chatService.softDeleteMessages(
      tenantId: widget.tenantId,
      phone: widget.phone,
      messageIds: ids,
    );
    _clearSelection();
  }

  Future<void> _starSelected() async {
    if (_selectedIds.length != 1) return;
    final id = _selectedIds.first;
    bool currently = false;
    for (final d in _latestDocs) {
      if (d.id == id) {
        currently = d.data()['starred'] == true;
        break;
      }
    }
    await _chatService.setMessageStarred(
      tenantId: widget.tenantId,
      phone: widget.phone,
      messageId: id,
      starred: !currently,
    );
    if (!mounted) return;
    _clearSelection();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(currently ? 'Unstarred' : 'Starred')),
    );
  }

  Future<void> _sendLocation() async {
    final nameCtrl = TextEditingController();
    final addrCtrl = TextEditingController();
    final latCtrl = TextEditingController();
    final lngCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Share location'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name (optional)')),
              TextField(controller: addrCtrl, decoration: const InputDecoration(labelText: 'Address (optional)')),
              TextField(
                controller: latCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration: const InputDecoration(labelText: 'Latitude'),
              ),
              TextField(
                controller: lngCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration: const InputDecoration(labelText: 'Longitude'),
              ),
              const SizedBox(height: 8),
              Text(
                'Google Maps se pin ki lat/lng copy karein.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (_guardOutboundSend()) return;
    final lat = double.tryParse(latCtrl.text.trim());
    final lng = double.tryParse(lngCtrl.text.trim());
    if (lat == null || lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Valid latitude & longitude required')));
      return;
    }
    setState(() => _isSending = true);
    try {
      await _chatService.sendLocation(
        tenantId: widget.tenantId,
        to: widget.phone,
        latitude: lat,
        longitude: lng,
        name: nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim(),
        address: addrCtrl.text.trim().isEmpty ? null : addrCtrl.text.trim(),
      );
      await _onOutboundSent();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _sendContactCard() async {
    try {
      final status = await FlutterContacts.permissions.request(PermissionType.read);
      if (status != PermissionStatus.granted && status != PermissionStatus.limited) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Contacts permission needed')));
        }
        return;
      }
      final all = await FlutterContacts.getAll(
        properties: {ContactProperty.name, ContactProperty.phone},
      );
      final usable = all
          .where((c) => (c.displayName ?? '').trim().isNotEmpty && c.phones.isNotEmpty)
          .toList()
        ..sort((a, b) => (a.displayName ?? '').compareTo(b.displayName ?? ''));
      if (!mounted) return;
      if (usable.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No phone contacts found')));
        return;
      }
      final picked = await showModalBottomSheet<Contact>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(ctx).height * 0.65,
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Share contact', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: usable.length,
                    itemBuilder: (_, i) {
                      final c = usable[i];
                      final phone = c.phones.first.normalizedNumber?.trim().isNotEmpty == true
                          ? c.phones.first.normalizedNumber!.trim()
                          : c.phones.first.number.trim();
                      return ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.person)),
                        title: Text(c.displayName ?? 'Contact'),
                        subtitle: Text(phone),
                        onTap: () => Navigator.pop(ctx, c),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      if (picked == null || !mounted) return;
      final name = (picked.displayName ?? '').trim();
      final phone = picked.phones.first.normalizedNumber?.trim().isNotEmpty == true
          ? picked.phones.first.normalizedNumber!.trim()
          : picked.phones.first.number.replaceAll(RegExp(r'[^\d+]'), '');
      if (name.isEmpty || phone.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Contact needs a name and phone')));
        return;
      }
      if (_guardOutboundSend()) return;
      setState(() => _isSending = true);
      await _chatService.sendContactCard(
        tenantId: widget.tenantId,
        to: widget.phone,
        formattedName: name,
        phone: phone,
      );
      await _onOutboundSent();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _sharePaymentDetails() async {
    final cfg = await ParcelPaymentService().load(widget.tenantId);
    if (!mounted) return;
    if (!cfg.hasJazzcash && !cfg.hasEasypaisa) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pehle Settings â†’ Parcel payment mein number add karein')),
      );
      return;
    }

    final amountCtrl = TextEditingController();
    var includeJazz = cfg.hasJazzcash;
    var includeEasy = cfg.hasEasypaisa && !cfg.hasJazzcash;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Share payment'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
                  decoration: const InputDecoration(
                    labelText: 'Amount (PKR)',
                    hintText: 'e.g. 2500',
                    border: OutlineInputBorder(),
                    prefixText: 'Rs ',
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 12),
                const Text('Accounts', style: TextStyle(fontWeight: FontWeight.w700)),
                if (cfg.hasJazzcash)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: includeJazz,
                    onChanged: (v) => setLocal(() => includeJazz = v ?? false),
                    title: Text('JazzCash Â· ${cfg.jazzcashNumber}'),
                    subtitle: cfg.jazzcashAccountName.isEmpty ? null : Text(cfg.jazzcashAccountName),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                if (cfg.hasEasypaisa)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: includeEasy,
                    onChanged: (v) => setLocal(() => includeEasy = v ?? false),
                    title: Text('EasyPaisa Â· ${cfg.easypaisaNumber}'),
                    subtitle: cfg.easypaisaAccountName.isEmpty ? null : Text(cfg.easypaisaAccountName),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;

    final amountRaw = amountCtrl.text.trim();
    final amount = double.tryParse(amountRaw);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Valid amount enter karein')));
      return;
    }
    if (!includeJazz && !includeEasy) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kam az kam ek account select karein')));
      return;
    }

    final amountStr = amount == amount.roundToDouble()
        ? amount.toStringAsFixed(0)
        : amount.toStringAsFixed(2);
    final lines = <String>[
      'ðŸ’³ *Payment details*',
      'â”â”â”â”â”â”â”â”â”â”â”â”',
      'ðŸ’° Amount: *PKR $amountStr*',
    ];
    if (includeJazz && cfg.hasJazzcash) {
      lines.addAll([
        '',
        'ðŸ“± *JazzCash*',
        'Number: *${cfg.jazzcashNumber}*',
        if (cfg.jazzcashAccountName.isNotEmpty) 'Name: ${cfg.jazzcashAccountName}',
      ]);
    }
    if (includeEasy && cfg.hasEasypaisa) {
      lines.addAll([
        '',
        'ðŸ“± *EasyPaisa*',
        'Number: *${cfg.easypaisaNumber}*',
        if (cfg.easypaisaAccountName.isNotEmpty) 'Name: ${cfg.easypaisaAccountName}',
      ]);
    }
    if (cfg.note.isNotEmpty) {
      lines.addAll(['', cfg.note]);
    }
    final text = lines.join('\n');

    if (_guardOutboundSend()) return;
    setState(() => _isSending = true);
    try {
      await _chatService.sendMessage(
        tenantId: widget.tenantId,
        to: widget.phone,
        text: text,
      );
      await _onOutboundSent();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _replySelected(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    if (_selectedIds.length != 1) return;
    final id = _selectedIds.first;
    QueryDocumentSnapshot<Map<String, dynamic>>? doc;
    for (final d in docs) {
      if (d.id == id) {
        doc = d;
        break;
      }
    }
    if (doc == null) return;
    final data = doc.data();
    setState(() {
      _replyTo = {
        'id': id,
        'text': (data['text'] as String?)?.trim().isNotEmpty == true
            ? data['text']
            : (data['type'] == 'image'
                ? 'Photo'
                : data['type'] == 'audio'
                    ? 'Voice message'
                    : data['type'] ?? 'Message'),
        'waMessageId': data['waMessageId'],
        'direction': data['direction'],
      };
      _selectedIds.clear();
    });
    _focusNode.requestFocus();
  }

  Future<void> _shareSelected(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) async {
    final textParts = <String>[];
    final files = <XFile>[];
    for (final id in _selectedIds) {
      QueryDocumentSnapshot<Map<String, dynamic>>? doc;
      for (final d in docs) {
        if (d.id == id) {
          doc = d;
          break;
        }
      }
      if (doc == null) continue;
      final data = doc.data();
      final t = (data['text'] as String?)?.trim();
      if (t != null && t.isNotEmpty) textParts.add(t);
      final url = (data['imageUrl'] as String?)?.trim() ??
          (data['mediaUrl'] as String?)?.trim() ??
          (data['documentUrl'] as String?)?.trim();
      if (url != null && url.isNotEmpty && (url.startsWith('http://') || url.startsWith('https://'))) {
        try {
          final res = await http.get(Uri.parse(url));
          if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
            final dir = await getTemporaryDirectory();
            final name = (data['filename'] as String?)?.trim();
            final ext = name != null && name.contains('.')
                ? name.split('.').last
                : (data['type'] == 'image'
                    ? 'jpg'
                    : data['type'] == 'video' || data['type'] == 'gif'
                        ? 'mp4'
                        : data['type'] == 'audio'
                            ? 'ogg'
                            : 'bin');
            final path = '${dir.path}/share_${DateTime.now().millisecondsSinceEpoch}_$id.$ext';
            await File(path).writeAsBytes(res.bodyBytes);
            files.add(XFile(path, name: name ?? 'share.$ext'));
          } else if (t == null || t.isEmpty) {
            textParts.add(url);
          }
        } catch (_) {
          if (t == null || t.isEmpty) textParts.add(url);
        }
      }
    }
    if (textParts.isEmpty && files.isEmpty) return;
    await SharePlus.instance.share(
      ShareParams(
        text: textParts.isEmpty ? null : textParts.join('\n\n'),
        files: files.isEmpty ? null : files,
      ),
    );
    _clearSelection();
  }

  Future<void> _forwardSelected(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) async {
    final payloads = <Map<String, dynamic>>[];
    for (final id in _selectedIds) {
      for (final d in docs) {
        if (d.id == id) {
          payloads.add(d.data());
          break;
        }
      }
    }
    if (payloads.isEmpty) return;

    final target = await showModalBottomSheet<ChatContact>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _ForwardContactPicker(
        tenantId: widget.tenantId,
        excludePhone: widget.phone,
      ),
    );
    if (target == null || !mounted) return;

    try {
      for (final data in payloads) {
        await _chatService.forwardMessageData(
          tenantId: widget.tenantId,
          to: target.phone,
          data: data,
        );
      }
      if (!mounted) return;
      _clearSelection();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Forwarded to ${target.name}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  void _maybeSetUnreadSeparator(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    if (_unreadSeparatorReady || _initialUnreadCount <= 0 || docs.isEmpty) return;
    final inbound = <String>[];
    for (var i = 0; i < docs.length && inbound.length < _initialUnreadCount; i++) {
      if (docs[i].data()['direction'] == 'inbound') {
        inbound.add(docs[i].id);
      }
    }
    if (inbound.isEmpty) {
      _unreadSeparatorReady = true;
      return;
    }
    _firstUnreadId = inbound.last;
    _unreadSeparatorReady = true;
  }

  Map<String, dynamic> _retryPayloadFor(Map<String, dynamic> data) {
    final existing = data['retryPayload'];
    if (existing is Map) {
      return Map<String, dynamic>.from(existing);
    }
    final type = data['type'] as String? ?? 'text';
    final body = <String, dynamic>{'to': widget.phone};
    switch (type) {
      case 'image':
        final url = data['imageUrl'] as String?;
        if (url != null && url.isNotEmpty) {
          body['imageUrl'] = url;
          final caption = (data['text'] as String?)?.trim();
          if (caption != null && caption.isNotEmpty) body['caption'] = caption;
        } else {
          body['text'] = data['text'] ?? '';
        }
      case 'gif':
        body['gifUrl'] = data['mediaUrl'] ?? data['documentUrl'] ?? '';
      case 'sticker':
        body['stickerUrl'] = data['mediaUrl'] ?? data['documentUrl'] ?? '';
      case 'video':
        body['videoUrl'] = data['mediaUrl'] ?? data['documentUrl'] ?? '';
        final caption = (data['text'] as String?)?.trim();
        if (caption != null && caption.isNotEmpty) body['caption'] = caption;
      case 'audio':
        body['audioUrl'] = data['mediaUrl'] ?? data['documentUrl'] ?? '';
        body['voice'] = true;
      case 'document':
        body['documentUrl'] = data['documentUrl'] ?? data['mediaUrl'] ?? '';
        if (data['filename'] != null) body['filename'] = data['filename'];
      default:
        body['text'] = data['text'] ?? '';
    }
    return body;
  }

  Future<void> _retryFailed(Map<String, dynamic> data) async {
    try {
      await _chatService.retryFailedMessage(
        tenantId: widget.tenantId,
        retryPayload: _retryPayloadFor(data),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  void _openSearch() {
    setState(() {
      _searchOpen = true;
      _searchQuery = _searchController.text.trim();
    });
  }

  void _closeSearch() {
    _searchController.clear();
    setState(() {
      _searchOpen = false;
      _searchQuery = '';
    });
  }

  bool _messageMatchesSearch(Map<String, dynamic> data, String q) {
    if (q.isEmpty) return true;
    final text = (data['text'] as String?)?.toLowerCase() ?? '';
    final preview = (data['replyPreview'] as String?)?.toLowerCase() ?? '';
    final filename = (data['filename'] as String?)?.toLowerCase() ?? '';
    return text.contains(q) || preview.contains(q) || filename.contains(q);
  }

  Future<void> _openQuickReplies() async {
    await showQuickRepliesSheet(
      context: context,
      tenantId: widget.tenantId,
      contactName: widget.contactName,
      onInsert: (text) {
        final cur = _textController.text;
        final sel = _textController.selection;
        if (sel.isValid && sel.start >= 0) {
          final start = sel.start;
          final end = sel.end >= start ? sel.end : start;
          _textController.value = TextEditingValue(
            text: cur.replaceRange(start, end, text),
            selection: TextSelection.collapsed(offset: start + text.length),
          );
        } else {
          _textController.text = text;
          _textController.selection = TextSelection.collapsed(offset: text.length);
        }
        setState(() {});
        _focusNode.requestFocus();
      },
    );
  }

  Future<void> _toggleAssignToMe() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final mine = _assigneeUid == user.uid;
    try {
      if (mine) {
        await _chatService.setAssignee(
          tenantId: widget.tenantId,
          phone: widget.phone,
          assigneeUid: null,
          assigneeName: null,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unassigned')));
        }
      } else {
        final name = (user.displayName?.trim().isNotEmpty == true)
            ? user.displayName!.trim()
            : (user.email ?? 'Me');
        await _chatService.setAssignee(
          tenantId: widget.tenantId,
          phone: widget.phone,
          assigneeUid: user.uid,
          assigneeName: name,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Assigned to $name')));
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (_focusNode.hasFocus && _emojiOpen) {
        setState(() => _emojiOpen = false);
      }
    });
    _contactSub = _chatService.watchContact(widget.tenantId, widget.phone).listen((snap) {
      if (!mounted) return;
      final data = snap.data();
      final unread = (data?['unreadCount'] as num?)?.toInt() ?? 0;
      setState(() {
        _assigneeUid = data?['assigneeUid'] as String?;
        _assigneeName = data?['assigneeName'] as String?;
        _lastCustomerMessageAt = (data?['lastCustomerMessageAt'] as Timestamp?)?.toDate();
        if (!_unreadCaptured) {
          _initialUnreadCount = unread;
          _unreadCaptured = true;
          _chatService.markRead(tenantId: widget.tenantId, phone: widget.phone);
        }
      });
    });
    // Fallback if contact watch is slow/empty.
    Future<void>.delayed(const Duration(milliseconds: 800), () {
      if (!mounted || _unreadCaptured) return;
      _unreadCaptured = true;
      _chatService.markRead(tenantId: widget.tenantId, phone: widget.phone);
    });
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      FirebaseFirestore.instance.collection('users').doc(uid).get().then((snap) {
        if (!mounted) return;
        final data = snap.data();
        final name = (data?['name'] as String?)?.trim();
        setState(() {
          _selfPhotoUrl = data?['photoUrl'] as String?;
          _selfLetter = (name != null && name.isNotEmpty) ? name[0].toUpperCase() : 'Y';
        });
      });
    }
  }

  @override
  void dispose() {
    _contactSub?.cancel();
    _holdTicker?.cancel();
    _searchController.dispose();
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _recorder.dispose();
    super.dispose();
  }

  void _toggleEmojiPanel() {
    if (_isSending || _isRecording) return;
    final open = !_emojiOpen;
    setState(() => _emojiOpen = open);
    if (open) {
      _focusNode.unfocus();
    } else {
      _focusNode.requestFocus();
    }
  }

  Future<void> _onOutboundSent() async {
    unawaited(_chatService.rememberContactName(
      tenantId: widget.tenantId,
      phone: widget.phone,
      name: widget.contactName,
    ));
  }

  bool _isOutside24hWindow() {
    DateTime? last = _lastCustomerMessageAt;
    if (last == null) {
      for (final doc in _latestDocs) {
        final data = doc.data();
        if (data['direction'] != 'inbound') continue;
        final ts = (data['timestamp'] as Timestamp?)?.toDate();
        if (ts == null) continue;
        if (last == null || ts.isAfter(last)) last = ts;
      }
    }
    if (last == null) {
      // Still loading — do not block. Empty history after snapshot = no customer
      // message yet, so the 24h session is closed (template only).
      if (!_messagesSnapReady) return false;
      return true;
    }
    return DateTime.now().difference(last) > const Duration(hours: 24);
  }

  bool _guardOutboundSend({bool checkInFlight = true}) {
    if (checkInFlight && _isSending) return true;
    if (_sendBlockedByBilling()) return true;
    if (_sendBlockedBy24hWindow()) return true;
    return false;
  }

  Widget _windowBanner() {
    if (!_isOutside24hWindow()) return const SizedBox.shrink();
    return Material(
      color: const Color(0xFFFFF4CE),
      child: InkWell(
        onTap: _openTemplates,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.lock_clock, size: 18, color: Color(0xFF8A6D1D)),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  '24h window closed. Tap to send a Meta template.',
                  style: TextStyle(color: Color(0xFF5C4B12), fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              TextButton(
                onPressed: _openTemplates,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF075E54),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Templates', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _sendRemoteMedia(
    String url, {
    required String ext,
    required Future<void> Function(XFile file) send,
  }) async {
    if (_guardOutboundSend()) return;
    setState(() {
      _isSending = true;
      _emojiOpen = false;
    });
    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('Could not download media');
      }
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/wa_media_${DateTime.now().millisecondsSinceEpoch}.$ext';
      await File(path).writeAsBytes(res.bodyBytes, flush: true);
      await send(XFile(path));
      await _onOutboundSent();
    } catch (e) {
      if (mounted) {
        final message = e.toString().replaceFirst('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _onGifSelected(GifItem gif) => _sendRemoteMedia(
        gif.mediaUrl,
        ext: 'mp4',
        send: (file) => _chatService.sendGif(tenantId: widget.tenantId, to: widget.phone, file: file),
      );

  Future<void> _onStickerSelected(StickerItem sticker) => _sendRemoteMedia(
        sticker.imageUrl,
        ext: 'png',
        send: (file) => _chatService.sendSticker(tenantId: widget.tenantId, to: widget.phone, file: file),
      );

  Future<void> _openTemplates() {
    return showWaTemplatePicker(
      context: context,
      tenantId: widget.tenantId,
      phone: widget.phone,
      contactName: widget.contactName,
    );
  }

  Future<void> _send() async {
    if (_isSending) return;
    if (_sendBlockedByBilling()) return;
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    if (_sendBlockedBy24hWindow()) return;

    _textController.clear();
    final replyWaId = (_replyTo?['waMessageId'] as String?)?.trim();
    final pending = _PendingOutbound(
      id: 'p${DateTime.now().microsecondsSinceEpoch}',
      type: 'text',
      text: text,
      at: DateTime.now(),
      replyPreview: (_replyTo?['text'] as String?)?.trim(),
    );
    setState(() {
      _pending.add(pending);
      _replyTo = null;
      _isSending = true;
    });
    WidgetsBinding.instance.addPostFrameCallback(_scrollToEnd);

    try {
      await _chatService.sendMessage(
        tenantId: widget.tenantId,
        to: widget.phone,
        text: text,
        replyToMessageId: (replyWaId != null && replyWaId.isNotEmpty) ? replyWaId : null,
      );
      unawaited(_onOutboundSent());
    } catch (e) {
      if (mounted) {
        setState(() => _pending.removeWhere((p) => p.id == pending.id));
        final message = e.toString().replaceFirst('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _scrollToEnd([_]) {
    if (!_scrollController.hasClients) return;
    _scrollController.jumpTo(0);
  }

  bool _isPinnedToLatest() {
    if (!_scrollController.hasClients) return true;
    return _scrollController.offset < 72;
  }

  void _prunePending(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    if (_pending.isEmpty) return;
    final matchedDocIds = <String>{};
    _pending.removeWhere((p) {
      for (final d in docs) {
        if (matchedDocIds.contains(d.id)) continue;
        final data = d.data();
        if (data['direction'] != 'outbound') continue;
        final ts = (data['timestamp'] as Timestamp?)?.toDate();
        if (ts == null) continue;
        if (ts.isBefore(p.at.subtract(const Duration(seconds: 5)))) continue;
        if (ts.difference(p.at).abs() > const Duration(minutes: 3)) continue;

        final msgType = data['type'] as String? ?? 'text';
        final msgText = (data['text'] as String? ?? '').trim();
        final pendingText = p.text.trim();
        final msgImage = (data['imageUrl'] as String?)?.trim();
        final msgMedia = (data['mediaUrl'] as String?)?.trim();

        final matches = switch (p.type) {
          'text' => msgType == 'text' && msgText == pendingText,
          'image' => () {
              if (msgType != 'image') return false;
              final url = (msgImage != null && msgImage.isNotEmpty) ? msgImage : msgMedia;
              if (url == null || url.isEmpty) return false;
              if (p.remoteUrl != null && p.remoteUrl!.isNotEmpty) {
                return url == p.remoteUrl;
              }
              return msgText == pendingText &&
                  ts.difference(p.at).abs() < const Duration(seconds: 20);
            }(),
          'video' => msgType == 'video' && msgText == pendingText,
          _ => false,
        };
        if (!matches) continue;
        matchedDocIds.add(d.id);
        return true;
      }
      return false;
    });
  }

  bool _isVideoFile(XFile file) {
    final p = file.path.toLowerCase();
    return p.endsWith('.mp4') ||
        p.endsWith('.mov') ||
        p.endsWith('.mkv') ||
        p.endsWith('.webm') ||
        p.endsWith('.3gp') ||
        p.endsWith('.avi');
  }

  bool _sendBlockedByBilling() {
    final billing = SubscriptionService.cachedBilling(widget.tenantId);
    if (billing != null && !billing.writeAllowed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(SubscriptionService.readOnlyMessage)),
      );
      return true;
    }
    return false;
  }

  bool _sendBlockedBy24hWindow() {
    if (!_isOutside24hWindow()) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('24h window closed — send a Meta template first.'),
        action: SnackBarAction(label: 'Templates', onPressed: _openTemplates),
      ),
    );
    return true;
  }

  _PendingOutbound _newPending({
    required String type,
    required String text,
    String? localPath,
    Uint8List? bytes,
  }) {
    return _PendingOutbound(
      id: 'p${DateTime.now().microsecondsSinceEpoch}',
      type: type,
      text: text,
      at: DateTime.now(),
      localPath: localPath,
      bytes: bytes,
    );
  }

  void _showPendingBubble(_PendingOutbound pending) {
    setState(() => _pending.add(pending));
    WidgetsBinding.instance.addPostFrameCallback(_scrollToEnd);
  }

  Widget _pendingBubble(_PendingOutbound p) {
    return _MessageBubble(
      key: ValueKey(p.id),
      text: p.text,
      type: p.type,
      localMediaPath: p.localPath,
      localMediaBytes: p.bytes,
      imageUrl: p.remoteUrl,
      isOutbound: true,
      timestamp: p.at,
      showTail: true,
      marginTop: _WaMetrics.senderGap,
      marginBottom: _WaMetrics.groupGap,
      photoUrl: _selfPhotoUrl,
      letter: _selfLetter,
      contactName: widget.contactName,
      tenantId: widget.tenantId,
      phone: widget.phone,
      replyPreview: p.replyPreview,
    );
  }

  Future<void> _sendVideoFile(XFile file, {String? caption}) async {
    if (_guardOutboundSend()) return;

    final cap = caption?.trim() ?? '';
    final pending = _newPending(type: 'video', text: cap, localPath: file.path);
    _showPendingBubble(pending);

    try {
      await _chatService.sendVideo(
        tenantId: widget.tenantId,
        to: widget.phone,
        file: file,
        caption: cap.isEmpty ? null : cap,
      );
      unawaited(_onOutboundSent());
    } catch (e) {
      if (mounted) {
        setState(() => _pending.removeWhere((x) => x.id == pending.id));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  Future<void> _previewAndSendVideo(XFile file) async {
    if (!mounted) return;
    final result = await openChatVideoPreview(context, file: file);
    if (result == null || result.files.isEmpty || !mounted) return;
    await _sendVideoFile(result.files.first, caption: result.caption);
  }

  Future<void> _openCamera() async {
    if (_isSending) return;
    final file = await Navigator.of(context).push<XFile?>(
      MaterialPageRoute(builder: (_) => const ChatCameraScreen()),
    );
    if (file == null || !mounted) return;
    if (_isVideoFile(file)) {
      await _previewAndSendVideo(file);
    } else {
      await _previewAndSendImages([file]);
    }
  }

  Future<void> _pickFromGallery() async {
    if (_isSending) return;
    try {
      final files = await ImagePicker().pickMultiImage(imageQuality: 85, limit: 30);
      if (files.isEmpty || !mounted) return;
      await _previewAndSendImages(files);
    } catch (e) {
      if (mounted) {
        final message = e.toString().replaceFirst('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  Future<void> _previewAndSendImages(List<XFile> files) async {
    if (files.isEmpty || !mounted) return;
    final result = await openChatMediaPreview(context, files: files);
    if (result == null || result.files.isEmpty || !mounted) return;
    if (_guardOutboundSend()) return;

    final caption = result.caption?.trim() ?? '';
    final pendings = <_PendingOutbound>[];
    for (var i = 0; i < result.files.length; i++) {
      pendings.add(_newPending(
        type: 'image',
        text: i == 0 ? caption : '',
        localPath: result.files[i].path,
      ));
    }
    setState(() => _pending.addAll(pendings));
    WidgetsBinding.instance.addPostFrameCallback(_scrollToEnd);

    Future<void> sendOne(int i) async {
      final pending = pendings[i];
      final file = result.files[i];
      final data = await file.readAsBytes();
      if (data.isEmpty) throw Exception('Could not read photo.');
      pending.bytes = data;
      if (mounted) setState(() {});
      final name = file.name.trim().isEmpty ? 'image.jpg' : file.name;
      final url = await _chatService.uploadImageBytes(data, filename: name);
      pending.remoteUrl = url;
      if (mounted) setState(() {});
      await _chatService.sendImageUrl(
        tenantId: widget.tenantId,
        to: widget.phone,
        imageUrl: url,
        caption: i == 0 && caption.isNotEmpty ? caption : null,
        bytes: data,
      );
    }

    try {
      for (var i = 0; i < result.files.length; i++) {
        await sendOne(i);
      }
      unawaited(_onOutboundSent());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  Future<void> _showAttachSheet() async {
    if (_isSending) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => const ChatAttachSheet(),
    );
    if (!mounted || choice == null) return;
    if (choice == 'gallery') {
      await _pickFromGallery();
    } else if (choice == 'camera') {
      await _openCamera();
    } else if (choice == 'document') {
      await _pickDocument();
    } else if (choice == 'audio') {
      await _pickAudioFile();
    } else if (choice == 'product') {
      await _shareProductFromCatalog();
    } else if (choice == 'location') {
      await _sendLocation();
    } else if (choice == 'contact') {
      await _sendContactCard();
    } else if (choice == 'payment') {
      await _sharePaymentDetails();
    } else if (choice.startsWith('recent:')) {
      final id = choice.substring('recent:'.length);
      await _pickRecentAsset(id);
    }
  }

  Future<void> _shareProductFromCatalog() async {
    final product = await CatalogScreen.pick(context, widget.tenantId);
    if (product == null || !mounted) return;
    if (_guardOutboundSend()) return;
    setState(() => _isSending = true);
    try {
      await _chatService.shareProduct(
        tenantId: widget.tenantId,
        to: widget.phone,
        name: product.name,
        price: product.price,
        description: product.description,
        sku: product.sku,
        imageUrl: product.imageUrl,
      );
      await _onOutboundSent();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _pickRecentAsset(String id) async {
    try {
      final asset = await AssetEntity.fromId(id);
      if (asset == null) return;
      final file = await asset.file;
      if (file == null || !mounted) return;
      final x = XFile(file.path);
      if (asset.type == AssetType.video) {
        await _previewAndSendVideo(x);
      } else {
        await _previewAndSendImages([x]);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  Future<void> _pickAudioFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'm4a', 'aac', 'ogg', 'wav', 'opus'],
      );
      final path = result?.files.single.path;
      if (path == null) return;
      if (_guardOutboundSend()) return;
      setState(() => _isSending = true);
      await _chatService.sendAudio(
        tenantId: widget.tenantId,
        to: widget.phone,
        path: path,
        voice: false,
      );
      await _onOutboundSent();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _pickDocument() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'pdf',
          'doc',
          'docx',
          'xls',
          'xlsx',
          'ppt',
          'pptx',
          'txt',
          'csv',
          'zip',
          'rar',
        ],
        withData: false,
      );
      final path = result?.files.single.path;
      final name = result?.files.single.name;
      if (path == null || name == null) return;
      if (_guardOutboundSend()) return;
      setState(() => _isSending = true);
      await _chatService.sendDocumentFile(
        tenantId: widget.tenantId,
        to: widget.phone,
        path: path,
        filename: name,
      );
      await _onOutboundSent();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _startRecording({required bool locked}) async {
    if (_isSending || _isRecording) return;
    final allowed = await _recorder.hasPermission();
    if (!allowed) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission is required for voice notes.')),
        );
      }
      return;
    }
    final dir = await getTemporaryDirectory();
    final useOpus = await _recorder.isEncoderSupported(AudioEncoder.opus);
    final ext = useOpus ? 'ogg' : 'm4a';
    final path = '${dir.path}/voice-${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _recorder.start(
      RecordConfig(
        encoder: useOpus ? AudioEncoder.opus : AudioEncoder.aacLc,
        numChannels: 1,
        bitRate: 24000,
        sampleRate: 16000,
      ),
      path: path,
    );
    _recordStartedAt = DateTime.now();
    if (!mounted) return;
    setState(() {
      _isRecording = true;
      _recordPath = path;
      _micLocked = locked;
      _micHolding = !locked;
      _holdDx = 0;
      _holdDy = 0;
    });
    if (!locked) {
      _holdTicker?.cancel();
      _holdTicker = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (_micHolding && mounted) setState(() {});
      });
    }
  }

  Future<void> _onMicTap() => _startRecording(locked: true);

  Future<void> _onHoldStart() => _startRecording(locked: false);

  void _onHoldUpdate(Offset fromOrigin) {
    if (!_micHolding) return;
    setState(() {
      _holdDx = fromOrigin.dx.clamp(-160.0, 20.0);
      _holdDy = fromOrigin.dy.clamp(-120.0, 20.0);
    });
    if (_holdDy < -55) {
      _holdTicker?.cancel();
      _holdOrigin = null;
      setState(() {
        _micHolding = false;
        _micLocked = true;
        _holdDx = 0;
        _holdDy = 0;
      });
    }
  }

  Future<void> _onHoldEnd() async {
    if (!_micHolding) return;
    final cancel = _holdDx < -70;
    _holdTicker?.cancel();
    _holdOrigin = null;
    if (cancel) {
      await _cancelRecording();
      return;
    }
    final started = _recordStartedAt;
    final path = _recordPath;
    _recordStartedAt = null;
    _recordPath = null;
    setState(() {
      _micHolding = false;
      _micLocked = false;
      _isRecording = false;
      _holdDx = 0;
      _holdDy = 0;
    });
    String? stopped;
    try {
      stopped = await _recorder.stop();
    } catch (_) {}
    final file = stopped ?? path;
    if (file == null || !File(file).existsSync()) return;
    final durationMs = started == null ? 0 : DateTime.now().difference(started).inMilliseconds;
    await _uploadAndSendVoice(file, durationMs);
  }

  Future<void> _cancelRecording() async {
    _holdTicker?.cancel();
    _recordStartedAt = null;
    _recordPath = null;
    try {
      await _recorder.cancel();
    } catch (_) {
      try {
        await _recorder.stop();
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _isRecording = false;
        _micHolding = false;
        _micLocked = false;
        _holdDx = 0;
        _holdDy = 0;
      });
    }
  }

  Future<void> _cancelVoicePanel() async {
    await _cancelRecording();
  }

  Future<void> _sendVoiceFromPanel(int durationMs) async {
    final path = _recordPath;
    _recordStartedAt = null;
    _recordPath = null;
    _holdTicker?.cancel();
    if (mounted) {
      setState(() {
        _isRecording = false;
        _micHolding = false;
        _micLocked = false;
      });
    }
    if (path == null || !File(path).existsSync()) return;
    await _uploadAndSendVoice(path, durationMs);
  }

  Future<void> _uploadAndSendVoice(String path, int durationMs) async {
    if (_guardOutboundSend()) return;
    setState(() => _isSending = true);
    try {
      final isVoice = path.toLowerCase().endsWith('.ogg') || path.toLowerCase().endsWith('.opus');
      await _chatService.sendAudio(
        tenantId: widget.tenantId,
        to: widget.phone,
        path: path,
        voice: isVoice,
        durationMs: durationMs <= 0 ? 500 : durationMs,
      );
      await _onOutboundSent();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _openCustomer360() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Customer360Screen(
          tenantId: widget.tenantId,
          phone: widget.phone,
          contactName: widget.contactName,
        ),
      ),
    );
  }

  Future<void> _callContact() async {
    final uri = Uri(scheme: 'tel', path: widget.phone);
    await launchUrl(uri);
  }

  Future<void> _onHeaderMenu(String value) async {
    switch (value) {
      case 'template':
        await _openTemplates();
        break;
      case 'customer':
        _openCustomer360();
        break;
      case 'order':
        final billing = await SubscriptionService().fetchBilling(widget.tenantId);
        if (!billing.writeAllowed) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(SubscriptionService.readOnlyMessage)),
            );
          }
          break;
        }
        await CreateOrderScreen.show(
          context,
          widget.tenantId,
          initialPhone: widget.phone,
          initialName: widget.contactName,
        );
        break;
      case 'favorite':
        final snap = await FirebaseFirestore.instance
            .collection('tenants')
            .doc(widget.tenantId)
            .collection('contacts')
            .doc(widget.phone)
            .get();
        final isFavorite = snap.data()?['isFavorite'] as bool? ?? false;
        await _chatService.setFavorite(
          tenantId: widget.tenantId,
          phone: widget.phone,
          isFavorite: !isFavorite,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(isFavorite ? 'Removed from favorites' : 'Added to favorites')),
          );
        }
        break;
      case 'archive':
        await _chatService.setArchived(
          tenantId: widget.tenantId,
          phone: widget.phone,
          isArchived: true,
        );
        if (mounted) Navigator.of(context).pop();
        break;
      case 'mute':
        final snap = await FirebaseFirestore.instance
            .collection('tenants')
            .doc(widget.tenantId)
            .collection('contacts')
            .doc(widget.phone)
            .get();
        final muted = snap.data()?['isMuted'] == true;
        await _chatService.setMuted(tenantId: widget.tenantId, phone: widget.phone, isMuted: !muted);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(muted ? 'Unmuted' : 'Muted â€” push notifications off')),
          );
        }
        break;
      case 'starred':
        final starred = _latestDocs.where((d) => d.data()['starred'] == true).toList();
        if (!mounted) return;
        await showModalBottomSheet<void>(
          context: context,
          builder: (ctx) => SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(ctx).height * 0.5,
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Starred messages', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  ),
                  Expanded(
                    child: starred.isEmpty
                        ? const Center(child: Text('No starred messages'))
                        : ListView.builder(
                            itemCount: starred.length,
                            itemBuilder: (_, i) {
                              final d = starred[i].data();
                              final t = (d['text'] as String?)?.trim().isNotEmpty == true
                                  ? d['text']
                                  : (d['type'] ?? 'Message');
                              return ListTile(
                                leading: const Icon(Icons.star_rounded, color: Color(0xFFF59E0B)),
                                title: Text('$t', maxLines: 2, overflow: TextOverflow.ellipsis),
                                trailing: IconButton(
                                  icon: const Icon(Icons.star_border),
                                  onPressed: () async {
                                    await _chatService.setMessageStarred(
                                      tenantId: widget.tenantId,
                                      phone: widget.phone,
                                      messageId: starred[i].id,
                                      starred: false,
                                    );
                                    if (ctx.mounted) Navigator.pop(ctx);
                                  },
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
        break;
      case 'assign':
        await _toggleAssignToMe();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final initial = widget.contactName.isNotEmpty ? widget.contactName[0].toUpperCase() : '?';

    return Theme(
      data: Theme.of(context).copyWith(
        textTheme: Theme.of(context).textTheme.apply(fontFamily: 'Roboto'),
      ),
      child: PopScope(
        canPop: !_selecting && !_searchOpen,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          if (_selecting) {
            _clearSelection();
          } else if (_searchOpen) {
            _closeSearch();
          }
        },
        child: Scaffold(
      backgroundColor: _WaColors.chatBackground,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: Container(
          color: _selecting ? const Color(0xFFD9FDD3) : Colors.white,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.only(left: 2, right: 0),
              child: _selecting
                  ? Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back, color: Color(0xFF111B21)),
                          onPressed: _clearSelection,
                        ),
                        Text(
                          '${_selectedIds.length}',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF111B21)),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Reply',
                          icon: const Icon(Icons.reply_rounded, color: Color(0xFF111B21)),
                          onPressed: _selectedIds.length == 1 ? () => _replySelected(_latestDocs) : null,
                        ),
                        IconButton(
                          tooltip: 'Delete',
                          icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFF111B21)),
                          onPressed: _deleteSelected,
                        ),
                        IconButton(
                          tooltip: 'Star',
                          icon: const Icon(Icons.star_border_rounded, color: Color(0xFF111B21)),
                          onPressed: _selectedIds.length == 1 ? _starSelected : null,
                        ),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert, color: Color(0xFF111B21)),
                          onSelected: (v) async {
                            if (v == 'forward') {
                              await _forwardSelected(_latestDocs);
                            } else if (v == 'share') {
                              await _shareSelected(_latestDocs);
                            } else if (v == 'copy') {
                              final id = _selectedIds.length == 1 ? _selectedIds.first : null;
                              if (id == null) return;
                              for (final d in _latestDocs) {
                                if (d.id == id) {
                                  final t = (d.data()['text'] as String?)?.trim() ?? '';
                                  if (t.isNotEmpty) {
                                    Clipboard.setData(ClipboardData(text: t));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Copied'), duration: Duration(seconds: 1)),
                                    );
                                  }
                                  break;
                                }
                              }
                              _clearSelection();
                            }
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(value: 'forward', child: Text('Forward')),
                            const PopupMenuItem(value: 'share', child: Text('Share')),
                            if (_selectedIds.length == 1)
                              const PopupMenuItem(value: 'copy', child: Text('Copy')),
                          ],
                        ),
                      ],
                    )
                  : _searchOpen
                      ? Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_back, color: Color(0xFF111B21)),
                              onPressed: _closeSearch,
                            ),
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                autofocus: true,
                                textInputAction: TextInputAction.search,
                                onChanged: (v) => setState(() => _searchQuery = v.trim()),
                                decoration: const InputDecoration(
                                  hintText: 'Search messages',
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  filled: false,
                                  isCollapsed: true,
                                ),
                                style: const TextStyle(color: Color(0xFF111B21), fontSize: 16),
                              ),
                            ),
                            if (_searchQuery.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.close, color: Color(0xFF54656F)),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              ),
                          ],
                        )
                      : Row(
                      children: [
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                          icon: const Icon(Icons.arrow_back, color: Color(0xFF111B21), size: 24),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        Expanded(
                          child: InkWell(
                            onTap: _openCustomer360,
                            borderRadius: BorderRadius.circular(24),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 18,
                                  backgroundColor: const Color(0xFFDFE5E7),
                                  child: Text(
                                    initial,
                                    style: const TextStyle(color: Color(0xFF54656F), fontWeight: FontWeight.w600, fontSize: 15),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        widget.contactName,
                                        style: const TextStyle(color: Color(0xFF111B21), fontWeight: FontWeight.w500, fontSize: 16),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                      if (_assigneeName != null && _assigneeName!.trim().isNotEmpty)
                                        Text(
                                          'Assigned: ${_assigneeName!}',
                                          style: const TextStyle(color: Color(0xFF667781), fontSize: 11),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                          tooltip: 'Search',
                          icon: const Icon(Icons.search_rounded, color: Color(0xFF54656F), size: 22),
                          onPressed: _openSearch,
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                          tooltip: 'Customer profile',
                          icon: const Icon(Icons.contact_page_outlined, color: Color(0xFF54656F), size: 22),
                          onPressed: _openCustomer360,
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                          tooltip: 'Call',
                          icon: const Icon(Icons.call_outlined, color: Color(0xFF54656F), size: 22),
                          onPressed: _callContact,
                        ),
                        PopupMenuButton<String>(
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.more_vert, color: Color(0xFF54656F), size: 22),
                          onSelected: _onHeaderMenu,
                          itemBuilder: (context) {
                            final uid = FirebaseAuth.instance.currentUser?.uid;
                            final assignedToMe = uid != null && _assigneeUid == uid;
                            return [
                              const PopupMenuItem(value: 'template', child: Text('Send template')),
                              const PopupMenuItem(value: 'customer', child: Text('View customer')),
                              const PopupMenuItem(value: 'order', child: Text('Create order')),
                              const PopupMenuItem(value: 'favorite', child: Text('Toggle favorite')),
                              const PopupMenuItem(value: 'mute', child: Text('Mute / unmute')),
                              const PopupMenuItem(value: 'starred', child: Text('Starred messages')),
                              const PopupMenuItem(value: 'archive', child: Text('Archive chat')),
                              PopupMenuItem(
                                value: 'assign',
                                child: Text(assignedToMe ? 'Unassign' : 'Assign to me'),
                              ),
                            ];
                          },
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerMove: _micHolding && _holdOrigin != null
            ? (e) => _onHoldUpdate(e.position - _holdOrigin!)
            : null,
        onPointerUp: _micHolding ? (_) => _onHoldEnd() : null,
        onPointerCancel: _micHolding ? (_) => _onHoldEnd() : null,
        child: Stack(
        children: [
          const Positioned.fill(child: CustomPaint(painter: _ChatWallpaperPainter())),
          Column(
            children: [
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _chatService.watchMessages(widget.tenantId, widget.phone),
              builder: (context, snapshot) {
                final raw = snapshot.data?.docs ?? const [];
                final docs = raw.where((d) => d.data()['deleted'] != true).toList();
                _latestDocs = docs;
                _messagesSnapReady = true;
                _prunePending(docs);
                _maybeSetUnreadSeparator(docs);
                final pending = List<_PendingOutbound>.from(_pending);
                if (docs.isEmpty && pending.isEmpty) {
                  return const Center(
                    child: Text('No messages yet', style: TextStyle(color: Color(0xFF667781))),
                  );
                }

                final q = _searchQuery.toLowerCase();
                final searching = _searchOpen && q.isNotEmpty;
                final newestId = pending.isNotEmpty
                    ? pending.last.id
                    : (docs.isNotEmpty ? docs.first.id : null);
                final isNew = newestId != _lastListDocId;
                _lastListDocId = newestId;

                if (!_didInitialJump && (docs.isNotEmpty || pending.isNotEmpty)) {
                  _didInitialJump = true;
                  WidgetsBinding.instance.addPostFrameCallback(_scrollToEnd);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    Future<void>.delayed(const Duration(milliseconds: 80), () {
                      if (mounted) _scrollToEnd();
                    });
                  });
                } else if (isNew && !searching && !_searchOpen && !_selecting && _isPinnedToLatest()) {
                  WidgetsBinding.instance.addPostFrameCallback(_scrollToEnd);
                }

                final total = docs.length + pending.length;

                return Column(
                  children: [
                    _windowBanner(),
                    Expanded(
                      child: ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  cacheExtent: 4000,
                  addAutomaticKeepAlives: true,
                  itemCount: total,
                  itemBuilder: (context, index) {
                    if (index < pending.length) {
                      return _pendingBubble(pending[pending.length - 1 - index]);
                    }
                    final docIndex = index - pending.length;
                    final data = docs[docIndex].data();
                    final msgId = docs[docIndex].id;
                    final selected = _selectedIds.contains(msgId);
                    final timestamp = (data['timestamp'] as Timestamp?)?.toDate();
                    final older = docIndex + 1 < docs.length ? docs[docIndex + 1].data() : null;
                    final newer = docIndex > 0 ? docs[docIndex - 1].data() : null;
                    final showDateSeparator = older == null ||
                        !_isSameDay(timestamp, (older['timestamp'] as Timestamp?)?.toDate());
                    final isOutbound = data['direction'] == 'outbound';
                    final isFirstInGroup = older == null ||
                        showDateSeparator ||
                        (older['direction'] == 'outbound') != isOutbound;
                    final isLastInGroup = newer == null ||
                        (newer['direction'] == 'outbound') != isOutbound;
                    final reaction = (data['reaction'] ?? data['localReaction'] ?? data['customerReaction']) as String?;
                    final matches = !searching || _messageMatchesSearch(data, q);
                    final replyPreview = (data['replyPreview'] as String?)?.trim();
                    final status = data['status'] as String?;
                    final retryPayload = data['retryPayload'] is Map
                        ? Map<String, dynamic>.from(data['retryPayload'] as Map)
                        : null;

                    return Opacity(
                      opacity: searching && !matches ? 0.28 : 1,
                      child: Column(
                      children: [
                        if (showDateSeparator && timestamp != null) _DateSeparator(date: timestamp),
                        if (_firstUnreadId == msgId && _initialUnreadCount > 0)
                          _UnreadMessagesChip(count: _initialUnreadCount),
                        GestureDetector(
                          onLongPress: () => _startMessageSelect(
                            msgId,
                            direction: data['direction'] as String?,
                          ),
                          onTap: _selecting
                              ? () => _toggleMessageSelect(
                                    msgId,
                                    direction: data['direction'] as String?,
                                  )
                              : null,
                          child: ColoredBox(
                            color: selected
                                ? const Color(0xFFD9FDD3).withValues(alpha: 0.55)
                                : (searching && matches
                                    ? const Color(0xFFFFF59D).withValues(alpha: 0.35)
                                    : Colors.transparent),
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Padding(
                                  padding: EdgeInsets.only(
                                    bottom: (reaction != null && reaction.isNotEmpty) ? 12 : 0,
                                  ),
                                  child: _MessageBubble(
                                  key: ValueKey(msgId),
                                  text: data['text'] as String? ?? '',
                                  imageUrl: data['imageUrl'] is String
                                      ? data['imageUrl'] as String
                                      : data['image_url'] as String?,
                                  mediaUrl: data['mediaUrl'] as String?,
                                  documentUrl: data['documentUrl'] as String?,
                                  filename: data['filename'] as String?,
                                  type: data['type'] as String? ?? 'text',
                                  isOutbound: isOutbound,
                                  status: status,
                                  timestamp: timestamp,
                                  durationMs: (data['durationMs'] as num?)?.toInt(),
                                  showTail: isFirstInGroup,
                                  marginTop: isFirstInGroup ? _WaMetrics.senderGap : _WaMetrics.groupGap,
                                  marginBottom: isLastInGroup ? _WaMetrics.groupGap : _WaMetrics.groupGap,
                                  photoUrl: isOutbound ? _selfPhotoUrl : null,
                                  letter: isOutbound
                                      ? _selfLetter
                                      : (widget.contactName.trim().isNotEmpty
                                          ? widget.contactName.trim()[0].toUpperCase()
                                          : '?'),
                                  contactName: widget.contactName,
                                  tenantId: widget.tenantId,
                                  phone: widget.phone,
                                  waMessageId: data['waMessageId'] as String?,
                                  reaction: reaction,
                                  starred: data['starred'] == true,
                                  replyPreview: replyPreview,
                                  messageDocId: msgId,
                                  retryPayload: retryPayload,
                                  onRetry: isOutbound && status == 'failed'
                                      ? () => _retryFailed(data)
                                      : null,
                                  location: data['location'] is Map
                                      ? Map<String, dynamic>.from(data['location'] as Map)
                                      : null,
                                  contacts: data['contacts'] as List<dynamic>?,
                                  referral: data['referral'] is Map
                                      ? Map<String, dynamic>.from(data['referral'] as Map)
                                      : null,
                                ),
                                ),
                                if (reaction != null && reaction.isNotEmpty)
                                  Positioned(
                                    bottom: 0,
                                    left: isOutbound ? null : 18,
                                    right: isOutbound ? 18 : null,
                                    child: Material(
                                      elevation: 1.5,
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(10),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: const Color(0xFFE9EDEF)),
                                        ),
                                        child: Text(reaction, style: const TextStyle(fontSize: 13, height: 1.15)),
                                      ),
                                    ),
                                  ),
                                if (data['starred'] == true)
                                  Positioned(
                                    top: 8,
                                    left: isOutbound ? null : 12,
                                    right: isOutbound ? 12 : null,
                                    child: const Icon(Icons.star_rounded, size: 14, color: Color(0xFFF59E0B)),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    );
                  },
                ),
                    ),
                  ],
                );
                  },
                ),
              ),
              _isRecording && _micLocked && _recordPath != null
                  ? VoiceRecordPanel(
                      recorder: _recorder,
                      filePath: _recordPath!,
                      onDelete: _cancelVoicePanel,
                      onSend: _sendVoiceFromPanel,
                    )
                  : _micHolding
                      ? VoiceHoldBar(
                          elapsed: _recordStartedAt == null
                              ? Duration.zero
                              : DateTime.now().difference(_recordStartedAt!),
                          dragDx: _holdDx,
                          dragDy: _holdDy,
                          willCancel: _holdDx < -70,
                          willLock: _holdDy < -55,
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_replyTo != null)
                              Container(
                                width: double.infinity,
                                color: Colors.white,
                                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                                child: Row(
                                  children: [
                                    Container(width: 3, height: 36, color: const Color(0xFF25D366)),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _replyTo!['direction'] == 'outbound' ? 'You' : widget.contactName,
                                            style: const TextStyle(
                                              color: Color(0xFF25D366),
                                              fontWeight: FontWeight.w700,
                                              fontSize: 12,
                                            ),
                                          ),
                                          Text(
                                            '${_replyTo!['text']}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(color: Color(0xFF667781), fontSize: 13),
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.close, size: 18, color: Color(0xFF667781)),
                                      onPressed: () => setState(() => _replyTo = null),
                                    ),
                                  ],
                                ),
                              ),
                            _MessageInputBar(
                              controller: _textController,
                              focusNode: _focusNode,
                              isSending: _isSending,
                              emojiOpen: _emojiOpen,
                              onToggleEmoji: _toggleEmojiPanel,
                              onSend: _send,
                              onCamera: _openCamera,
                              onAttach: _showAttachSheet,
                              onQuickReplies: _openQuickReplies,
                              onMicTap: _onMicTap,
                              onHoldStart: (origin) {
                                _holdOrigin = origin;
                                _onHoldStart();
                              },
                            ),
                            if (_emojiOpen)
                              SafeArea(
                                top: false,
                                child: ChatEmojiPanel(
                                  textController: _textController,
                                  height: MediaQuery.of(context).size.height * 0.38,
                                  onGifSelected: _onGifSelected,
                                  onStickerSelected: _onStickerSelected,
                                ),
                              ),
                          ],
                        ),
            ],
          ),
        ],
      ),
      ),
      ),
      ),
    );
  }
}

bool _isSameDay(DateTime? a, DateTime? b) {
  if (a == null || b == null) return false;
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

class _DateSeparator extends StatelessWidget {
  final DateTime date;

  const _DateSeparator({required this.date});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final day = DateTime(date.year, date.month, date.day);

    final String label;
    if (day == today) {
      label = 'Today';
    } else if (day == yesterday) {
      label = 'Yesterday';
    } else {
      label = DateFormat('MMMM d, yyyy').format(date);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(8)),
          child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

class _UnreadMessagesChip extends StatelessWidget {
  final int count;

  const _UnreadMessagesChip({required this.count});

  @override
  Widget build(BuildContext context) {
    final label = count == 1 ? '1 unread message' : '$count unread messages';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFE7FCE3),
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [
              BoxShadow(color: Color(0x14000000), blurRadius: 2, offset: Offset(0, 1)),
            ],
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF1FA855),
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final String text;
  final String? imageUrl;
  final String? mediaUrl;
  final String? documentUrl;
  final String? filename;
  final String type;
  final bool isOutbound;
  final String? status;
  final DateTime? timestamp;
  final bool showTail;
  final double marginTop;
  final double marginBottom;
  final String? photoUrl;
  final String letter;
  final int? durationMs;
  final String contactName;
  final String? tenantId;
  final String? phone;
  final String? waMessageId;
  final String? reaction;
  final bool starred;
  final String? replyPreview;
  final String? messageDocId;
  final Map<String, dynamic>? retryPayload;
  final VoidCallback? onRetry;
  final Map<String, dynamic>? location;
  final List<dynamic>? contacts;
  final String? localMediaPath;
  final Uint8List? localMediaBytes;
  final Map<String, dynamic>? referral;

  const _MessageBubble({
    super.key,
    required this.text,
    this.imageUrl,
    this.mediaUrl,
    this.documentUrl,
    this.filename,
    this.type = 'text',
    required this.isOutbound,
    this.status,
    this.timestamp,
    required this.showTail,
    this.marginTop = 2,
    this.marginBottom = 2,
    this.photoUrl,
    this.letter = '?',
    this.durationMs,
    this.contactName = '',
    this.tenantId,
    this.phone,
    this.waMessageId,
    this.reaction,
    this.starred = false,
    this.replyPreview,
    this.messageDocId,
    this.retryPayload,
    this.onRetry,
    this.location,
    this.contacts,
    this.localMediaPath,
    this.localMediaBytes,
    this.referral,
  });

  bool get _isImage {
    if (localMediaBytes != null && localMediaBytes!.isNotEmpty) return true;
    if (type == 'image') return true;
    final url = imageUrl?.trim();
    if (url != null && url.isNotEmpty && type != 'interactive' && type != 'template') {
      return true;
    }
    return false;
  }

  String? get _resolvedImageUrl {
    final a = imageUrl?.trim();
    if (a != null && a.isNotEmpty) return a;
    if (type != 'image') return null;
    final b = mediaUrl?.trim();
    if (b != null && b.isNotEmpty) return b;
    final c = documentUrl?.trim();
    if (c != null && c.isNotEmpty) return c;
    return null;
  }

  String? get _media => (mediaUrl != null && mediaUrl!.isNotEmpty) ? mediaUrl : documentUrl;

  static const _messageStyle = TextStyle(
    color: _WaMetrics.messageColor,
    fontSize: _WaMetrics.messageFontSize,
    height: _WaMetrics.messageLineHeight,
    fontWeight: FontWeight.w400,
  );

  static const _metaStyle = TextStyle(
    color: _WaMetrics.metaColor,
    fontSize: _WaMetrics.metaFontSize,
    height: 1.0,
    fontWeight: FontWeight.w400,
  );

  BorderRadius _borderRadius() {
    const r = _WaMetrics.bubbleRadius;
    const t = _WaMetrics.tailCornerRadius;
    return BorderRadius.only(
      topLeft: Radius.circular(!isOutbound && showTail ? t : r),
      topRight: Radius.circular(isOutbound && showTail ? t : r),
      bottomLeft: const Radius.circular(r),
      bottomRight: const Radius.circular(r),
    );
  }

  double _metaReserveWidth(String timeLabel) {
    final tp = TextPainter(text: TextSpan(text: timeLabel, style: _metaStyle), textDirection: TextDirection.ltr)
      ..layout();
    final tickW = isOutbound ? 16.0 : 0.0;
    return tp.width + tickW + (isOutbound ? _WaMetrics.tickGap : 0) + 4;
  }

  Widget? _replyQuote() {
    final preview = replyPreview?.trim();
    if (preview == null || preview.isEmpty) return null;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(6),
        border: Border(
          left: BorderSide(
            color: isOutbound ? const Color(0xFF25D366) : const Color(0xFF53BDEB),
            width: 3.5,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Reply',
            style: TextStyle(
              color: isOutbound ? const Color(0xFF25D366) : const Color(0xFF53BDEB),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          Text(
            preview,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF667781), fontSize: 12.5, height: 1.2),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (type == 'location' && location != null) {
      final name = (location!['name'] as String?)?.trim();
      final address = (location!['address'] as String?)?.trim();
      final lat = location!['latitude'];
      final lng = location!['longitude'];
      final label = (name != null && name.isNotEmpty)
          ? name
          : (address != null && address.isNotEmpty)
              ? address
              : 'Location';
      return _buildMediaShell(
        context,
        InkWell(
          onTap: lat != null && lng != null
              ? () => launchUrl(
                    Uri.parse('https://maps.google.com/?q=$lat,$lng'),
                    mode: LaunchMode.externalApplication,
                  )
              : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_replyQuote() != null) _replyQuote()!,
                const Row(
                  children: [
                    Icon(Icons.location_on, color: Color(0xFF1E8E3E), size: 22),
                    SizedBox(width: 6),
                    Text('Location', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(label, style: _messageStyle),
                const SizedBox(height: 4),
                Align(alignment: Alignment.bottomRight, child: _metaRow()),
              ],
            ),
          ),
        ),
      );
    }
    if (type == 'contacts') {
      final first = (contacts != null && contacts!.isNotEmpty && contacts!.first is Map)
          ? Map<String, dynamic>.from(contacts!.first as Map)
          : null;
      final nameMap = first?['name'] is Map ? Map<String, dynamic>.from(first!['name'] as Map) : null;
      final n = (nameMap?['formatted_name'] ?? nameMap?['first_name'] ?? text).toString();
      final phones = first?['phones'];
      final phone = (phones is List && phones.isNotEmpty && phones.first is Map)
          ? (phones.first as Map)['phone']?.toString()
          : null;
      return _buildMediaShell(
        context,
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_replyQuote() != null) _replyQuote()!,
              const Row(
                children: [
                  Icon(Icons.person, color: Color(0xFF1A73E8), size: 22),
                  SizedBox(width: 6),
                  Text('Contact', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                ],
              ),
              const SizedBox(height: 4),
              Text(n, style: _messageStyle),
              if (phone != null && phone.isNotEmpty)
                Text(phone, style: const TextStyle(color: Color(0xFF667781), fontSize: 12.5)),
              const SizedBox(height: 4),
              Align(alignment: Alignment.bottomRight, child: _metaRow()),
            ],
          ),
        ),
      );
    }
    if (_isImage) return _buildImageBubble(context);
    if (type == 'video' && localMediaPath != null && localMediaPath!.isNotEmpty) {
      return _buildLocalVideoBubble(context);
    }
    if (type == 'gif' && _media != null) {
      return _buildMediaShell(
        context,
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_replyQuote() != null) Padding(padding: const EdgeInsets.fromLTRB(4, 4, 4, 0), child: _replyQuote()),
            GestureDetector(
              onTap: () => openChatMediaViewer(
                context,
                kind: ChatMediaKind.video,
                url: _media!,
                caption: 'GIF',
                timestamp: timestamp,
                isOutbound: isOutbound,
                title: contactName,
                tenantId: tenantId,
                phone: phone,
                waMessageId: waMessageId,
              ),
              child: ChatGifBubble(url: _media!, meta: _metaRow(light: true)),
            ),
          ],
        ),
      );
    }
    if (type == 'sticker' && _media != null) return _buildStickerBubble();
    if (type == 'video' && _media != null) {
      final caption = text.trim();
      return _buildMediaShell(
        context,
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_replyQuote() != null) Padding(padding: const EdgeInsets.fromLTRB(4, 4, 4, 0), child: _replyQuote()),
            ChatVideoBubble(
              url: _media!,
              caption: caption,
              meta: _metaRow(light: caption.isEmpty),
              timestamp: timestamp,
              isOutbound: isOutbound,
              title: contactName,
              tenantId: tenantId,
              phone: phone,
              waMessageId: waMessageId,
            ),
          ],
        ),
      );
    }
    if (type == 'audio' && _media != null) {
      return _buildMediaShell(
        context,
        ChatAudioBubble(
          url: _media!,
          isOutbound: isOutbound,
          photoUrl: photoUrl,
          letter: letter,
          durationMs: durationMs,
          meta: _metaRow(),
        ),
        expand: true,
      );
    }
    if (type == 'document' && _media != null) {
      return _buildMediaShell(
        context,
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_replyQuote() != null) Padding(padding: const EdgeInsets.fromLTRB(6, 6, 6, 0), child: _replyQuote()),
            ChatDocumentBubble(url: _media!, filename: filename ?? 'Document', caption: text.trim(), meta: _metaRow()),
          ],
        ),
      );
    }
    return _buildTextBubble(context);
  }

  Widget _metaRow({bool light = false}) {
    return _TimeTicksRow(
      timestamp: timestamp,
      isOutbound: isOutbound,
      status: status,
      light: light,
      onRetry: onRetry,
    );
  }

  Widget _buildMediaShell(BuildContext context, Widget child, {bool expand = false}) {
    final maxW = MediaQuery.of(context).size.width * _WaMetrics.bubbleMaxWidthFactor;
    final radius = _borderRadius();
    return Padding(
      padding: EdgeInsets.only(
        left: isOutbound ? _WaMetrics.oppositeMargin : _WaMetrics.edgeMargin,
        right: isOutbound ? _WaMetrics.edgeMargin : _WaMetrics.oppositeMargin,
        top: marginTop,
        bottom: marginBottom,
      ),
      child: Align(
        alignment: isOutbound ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: expand ? maxW : 0, maxWidth: maxW),
          child: Container(
            decoration: BoxDecoration(
              color: isOutbound ? _WaColors.outboundBubble : _WaColors.inboundBubble,
              borderRadius: radius,
              boxShadow: const [
                BoxShadow(color: Color(0x22000000), blurRadius: 1.2, offset: Offset(0, 1)),
              ],
            ),
            child: ClipRRect(borderRadius: radius, child: child),
          ),
        ),
      ),
    );
  }

  Widget _chatPhotoWidget({
    required double width,
    required double height,
    Uint8List? bytes,
    String? localPath,
    String? remoteUrl,
  }) {
    if (bytes != null && bytes.isNotEmpty) {
      return Image.memory(
        bytes,
        width: width,
        height: height,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _chatPhotoWidget(
          width: width,
          height: height,
          remoteUrl: remoteUrl,
        ),
      );
    }
    if (localPath != null && localPath.isNotEmpty) {
      return Image.file(
        File(localPath),
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _chatPhotoWidget(
          width: width,
          height: height,
          remoteUrl: remoteUrl,
        ),
      );
    }
    if (remoteUrl != null && remoteUrl.isNotEmpty) {
      final displayUrl = cloudinaryDisplayImageUrl(remoteUrl);
      return Image.network(
        displayUrl,
        width: width,
        height: height,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => SizedBox(
          width: width,
          height: height,
          child: const ColoredBox(
            color: Color(0xFFECEFF1),
            child: Center(
              child: Icon(Icons.broken_image_outlined, color: Color(0xFF8696A0), size: 36),
            ),
          ),
        ),
        loadingBuilder: (_, child, progress) {
          if (progress == null) return child;
          return SizedBox(
            width: width,
            height: height,
            child: const ColoredBox(
              color: Color(0xFF2A3942),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                ),
              ),
            ),
          );
        },
      );
    }
    return SizedBox(
      width: width,
      height: height,
      child: const ColoredBox(
        color: Color(0xFF2A3942),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.photo_outlined, color: Colors.white70, size: 40),
              SizedBox(height: 6),
              Text('Photo', style: TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageBubble(BuildContext context) {
    final maxW = MediaQuery.of(context).size.width * _WaMetrics.bubbleMaxWidthFactor;
    final caption = text.trim();
    final quote = _replyQuote();
    final remote = _resolvedImageUrl;
    final imgW = maxW - 6;
    final imgH = MediaQuery.of(context).size.height * 0.32;

    return Padding(
      padding: EdgeInsets.only(
        left: isOutbound ? _WaMetrics.oppositeMargin : _WaMetrics.edgeMargin,
        right: isOutbound ? _WaMetrics.edgeMargin : _WaMetrics.oppositeMargin,
        top: marginTop,
        bottom: marginBottom,
      ),
      child: Align(
        alignment: isOutbound ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW),
          child: ClipRRect(
            borderRadius: _borderRadius(),
            child: Container(
              color: isOutbound ? _WaColors.outboundBubble : _WaColors.inboundBubble,
              padding: const EdgeInsets.all(3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (quote != null) Padding(padding: const EdgeInsets.fromLTRB(3, 3, 3, 2), child: quote),
                  GestureDetector(
                    onTap: remote != null && remote.isNotEmpty
                        ? () => openChatMediaViewer(
                              context,
                              kind: ChatMediaKind.image,
                              url: remote,
                              caption: caption,
                              timestamp: timestamp,
                              isOutbound: isOutbound,
                              title: contactName,
                              tenantId: tenantId,
                              phone: phone,
                              waMessageId: waMessageId,
                            )
                        : null,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        width: imgW,
                        height: imgH,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _chatPhotoWidget(
                              width: imgW,
                              height: imgH,
                              bytes: localMediaBytes,
                              localPath: localMediaPath?.trim(),
                              remoteUrl: remote,
                            ),
                            Positioned(
                              right: 6,
                              bottom: 6,
                              child: _TimeTicksRow(
                                timestamp: timestamp,
                                isOutbound: isOutbound,
                                status: status,
                                light: caption.isEmpty,
                                onRetry: onRetry,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (caption.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(6, 4, 6, 2),
                      child: Text(caption, style: _messageStyle),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLocalVideoBubble(BuildContext context) {
    final caption = text.trim();
    final quote = _replyQuote();
    final path = localMediaPath ?? '';

    return _buildMediaShell(
      context,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (quote != null) Padding(padding: const EdgeInsets.fromLTRB(4, 4, 4, 0), child: quote),
          _LocalVideoFrame(
            path: path,
            meta: _metaRow(light: caption.isEmpty),
          ),
          if (caption.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
              child: Text(caption, style: _messageStyle),
            ),
        ],
      ),
    );
  }

  Widget _buildStickerBubble() {
    return Padding(
      padding: EdgeInsets.only(
        left: isOutbound ? _WaMetrics.oppositeMargin : _WaMetrics.edgeMargin,
        right: isOutbound ? _WaMetrics.edgeMargin : _WaMetrics.oppositeMargin,
        top: marginTop,
        bottom: marginBottom,
      ),
      child: Align(
        alignment: isOutbound ? Alignment.centerRight : Alignment.centerLeft,
        child: ChatStickerBubble(
          url: _media!,
          isOutbound: isOutbound,
          meta: _TimeTicksRow(timestamp: timestamp, isOutbound: isOutbound, status: status, light: true, onRetry: onRetry),
        ),
      ),
    );
  }

  Widget _buildTextBubble(BuildContext context) {
    final timeLabel = timestamp != null ? DateFormat('h:mm a').format(timestamp!) : '12:59 PM';
    final metaW = _metaReserveWidth(timeLabel);
    final maxW = MediaQuery.of(context).size.width * _WaMetrics.bubbleMaxWidthFactor;
    final emojiOnly = _isEmojiOnlyMessage(text) && (replyPreview == null || replyPreview!.trim().isEmpty);
    final messageStyle = emojiOnly
        ? _messageStyle.copyWith(fontSize: text.characters.length <= 2 ? 42 : 34, height: 1.15)
        : _messageStyle;
    final quote = _replyQuote();
    final adReferral = referral;

    return Padding(
      padding: EdgeInsets.only(
        left: isOutbound ? _WaMetrics.oppositeMargin : _WaMetrics.edgeMargin,
        right: isOutbound ? _WaMetrics.edgeMargin : _WaMetrics.oppositeMargin,
        top: marginTop,
        bottom: marginBottom,
      ),
      child: Align(
        alignment: isOutbound ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: emojiOnly
                  ? Colors.transparent
                  : (isOutbound ? _WaColors.outboundBubble : _WaColors.inboundBubble),
              borderRadius: _borderRadius(),
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                emojiOnly ? 4 : _WaMetrics.bubblePaddingH,
                emojiOnly ? 2 : _WaMetrics.bubblePaddingV,
                emojiOnly ? 4 : _WaMetrics.bubblePaddingH,
                emojiOnly ? 2 : _WaMetrics.bubblePaddingV,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (quote != null) quote,
                  if (adReferral != null && adReferral.isNotEmpty)
                    ChatAdReferralCard(referral: adReferral),
                  Stack(
                    children: [
                      Text.rich(
                        TextSpan(
                          style: messageStyle,
                          children: [
                            TextSpan(text: text),
                            WidgetSpan(
                              alignment: PlaceholderAlignment.bottom,
                              child: SizedBox(width: metaW, height: _WaMetrics.metaHeight),
                            ),
                          ],
                        ),
                        textHeightBehavior: const TextHeightBehavior(
                          applyHeightToFirstAscent: false,
                          applyHeightToLastDescent: false,
                        ),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: emojiOnly
                            ? DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.22),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  child: _TimeTicksRow(
                                    timestamp: timestamp,
                                    isOutbound: isOutbound,
                                    status: status,
                                    light: true,
                                    onRetry: onRetry,
                                  ),
                                ),
                              )
                            : _TimeTicksRow(
                                timestamp: timestamp,
                                isOutbound: isOutbound,
                                status: status,
                                onRetry: onRetry,
                              ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

bool _isEmojiOnlyMessage(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return false;
  final chars = text.characters;
  if (chars.length > 6) return false;
  // Reject if any character looks like normal letters/digits/punctuation-heavy text.
  final stripped = text.replaceAll(RegExp(r'\s'), '');
  if (RegExp(r'[A-Za-z0-9]').hasMatch(stripped)) return false;
  // Must contain at least one non-ASCII / emoji-ish code unit.
  return stripped.runes.any((r) => r > 0x2040);
}

class _TimeTicksRow extends StatelessWidget {
  final DateTime? timestamp;
  final bool isOutbound;
  final String? status;
  final bool light;
  final VoidCallback? onRetry;

  const _TimeTicksRow({
    this.timestamp,
    required this.isOutbound,
    this.status,
    this.light = false,
    this.onRetry,
  });

  static const _metaStyle = TextStyle(
    color: _WaMetrics.metaColor,
    fontSize: _WaMetrics.metaFontSize,
    height: 1.0,
    fontWeight: FontWeight.w400,
  );

  static const _metaStyleLight = TextStyle(
    color: Colors.white,
    fontSize: _WaMetrics.metaFontSize,
    height: 1.0,
    fontWeight: FontWeight.w400,
  );

  @override
  Widget build(BuildContext context) {
    final style = light ? _metaStyleLight : _metaStyle;
    final ticks = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (timestamp != null)
          Text(
            DateFormat('h:mm a').format(timestamp!),
            style: style,
          ),
        if (isOutbound) ...[
          const SizedBox(width: _WaMetrics.tickGap),
          _StatusTicks(status: status, light: light),
        ],
      ],
    );
    if (isOutbound && status == 'failed' && onRetry != null) {
      return GestureDetector(
        onTap: onRetry,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(height: _WaMetrics.metaHeight, child: ticks),
      );
    }
    return SizedBox(height: _WaMetrics.metaHeight, child: ticks);
  }
}

class _StatusTicks extends StatelessWidget {
  final String? status;
  final bool light;

  const _StatusTicks({this.status, this.light = false});

  Color get _grey => light ? Colors.white70 : _WaColors.tickGrey;
  Color get _blue => light ? const Color(0xFF93EAFF) : _WaColors.tickBlue;

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case 'read':
        return _WaTickIcon(doubleTick: true, color: _blue);
      case 'delivered':
        return _WaTickIcon(doubleTick: true, color: _grey);
      case 'sent':
        return _WaTickIcon(doubleTick: false, color: _grey);
      case 'failed':
        return Icon(Icons.error_outline_rounded, size: 13, color: light ? Colors.white70 : const Color(0xFFE53935));
      default:
        return Icon(Icons.access_time_rounded, size: 11, color: _grey);
    }
  }
}

/// WhatsApp overlapping check marks â€” double 18Ã—12, single 13Ã—12.
class _WaTickIcon extends StatelessWidget {
  final bool doubleTick;
  final Color color;

  const _WaTickIcon({required this.doubleTick, required this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(doubleTick ? 16 : 12, 10),
      painter: _WaTickPainter(doubleTick: doubleTick, color: color),
    );
  }
}

class _WaTickPainter extends CustomPainter {
  final bool doubleTick;
  final Color color;

  _WaTickPainter({required this.doubleTick, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (doubleTick) {
      final back = Path()
        ..moveTo(0, 6.5)
        ..lineTo(3.5, 10)
        ..lineTo(10, 2);
      final front = Path()
        ..moveTo(5.5, 6.5)
        ..lineTo(9, 10)
        ..lineTo(16.5, 2);
      canvas.drawPath(back, paint);
      canvas.drawPath(front, paint);
    } else {
      final tick = Path()
        ..moveTo(1, 6.5)
        ..lineTo(4.5, 10)
        ..lineTo(12, 2);
      canvas.drawPath(tick, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaTickPainter oldDelegate) =>
      oldDelegate.doubleTick != doubleTick || oldDelegate.color != color;
}

class _MessageInputBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isSending;
  final bool emojiOpen;
  final VoidCallback onToggleEmoji;
  final VoidCallback onSend;
  final VoidCallback onCamera;
  final VoidCallback onAttach;
  final VoidCallback onQuickReplies;
  final VoidCallback onMicTap;
  final void Function(Offset globalOrigin) onHoldStart;

  const _MessageInputBar({
    required this.controller,
    required this.focusNode,
    required this.isSending,
    required this.emojiOpen,
    required this.onToggleEmoji,
    required this.onSend,
    required this.onCamera,
    required this.onAttach,
    required this.onQuickReplies,
    required this.onMicTap,
    required this.onHoldStart,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      bottom: !emojiOpen,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: Icon(
                        emojiOpen ? Icons.keyboard_alt_outlined : Icons.emoji_emotions_outlined,
                        color: _WaColors.inputIconGrey,
                        size: 24,
                      ),
                      padding: const EdgeInsets.only(left: 4, bottom: 4),
                      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                      onPressed: isSending ? null : onToggleEmoji,
                    ),
                    Expanded(
                      child: TextField(
                        controller: controller,
                        focusNode: focusNode,
                        minLines: 1,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        onTap: () {
                          if (emojiOpen) onToggleEmoji();
                        },
                        decoration: const InputDecoration(
                          hintText: 'Message',
                          hintStyle: TextStyle(color: _WaColors.inputIconGrey, fontSize: 16),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          isCollapsed: true,
                          contentPadding: EdgeInsets.fromLTRB(0, 12, 0, 12),
                        ),
                        style: const TextStyle(color: _WaMetrics.messageColor, fontSize: 16, height: 1.25),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Quick replies',
                      icon: const Icon(Icons.bolt_outlined, color: _WaColors.inputIconGrey, size: 22),
                      padding: const EdgeInsets.only(bottom: 4),
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 44),
                      onPressed: isSending ? null : onQuickReplies,
                    ),
                    IconButton(
                      icon: Transform.rotate(
                        angle: 0.8,
                        child: const Icon(Icons.attach_file_rounded, color: _WaColors.inputIconGrey, size: 22),
                      ),
                      padding: const EdgeInsets.only(bottom: 4),
                      constraints: const BoxConstraints(minWidth: 40, minHeight: 44),
                      onPressed: isSending ? null : onAttach,
                    ),
                    IconButton(
                      icon: const Icon(Icons.camera_alt_rounded, color: _WaColors.inputIconGrey, size: 22),
                      padding: const EdgeInsets.only(right: 2, bottom: 4),
                      constraints: const BoxConstraints(minWidth: 40, minHeight: 44),
                      onPressed: isSending ? null : onCamera,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                final hasText = value.text.trim().isNotEmpty;
                return GestureDetector(
                  onTap: isSending ? null : (hasText ? onSend : onMicTap),
                  onLongPressStart: !hasText && !isSending
                      ? (d) => onHoldStart(d.globalPosition)
                      : null,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                      color: _WaColors.inputBarGreen,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: isSending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Icon(
                            hasText ? Icons.send_rounded : Icons.mic_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ForwardContactPicker extends StatefulWidget {
  const _ForwardContactPicker({
    required this.tenantId,
    required this.excludePhone,
  });

  final String tenantId;
  final String excludePhone;

  @override
  State<_ForwardContactPicker> createState() => _ForwardContactPickerState();
}

class _ForwardContactPickerState extends State<_ForwardContactPicker> {
  final _chatService = ChatService();
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.72;
    return SizedBox(
      height: height,
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFD1D7DB),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Forward to',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFF111B21)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _search,
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Search name or number',
                prefixIcon: const Icon(Icons.search, color: Color(0xFF667781)),
                filled: true,
                fillColor: const Color(0xFFF0F2F5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _chatService.watchContacts(widget.tenantId),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final contacts = snap.data!.docs
                    .map(ChatContact.fromDoc)
                    .where((c) => c.phone != widget.excludePhone && !c.isArchived)
                    .where((c) {
                      if (_query.isEmpty) return true;
                      return c.name.toLowerCase().contains(_query) ||
                          c.phone.toLowerCase().contains(_query);
                    })
                    .toList();
                if (contacts.isEmpty) {
                  return const Center(
                    child: Text('No chats found', style: TextStyle(color: Color(0xFF667781))),
                  );
                }
                return ListView.builder(
                  itemCount: contacts.length,
                  itemBuilder: (context, i) {
                    final c = contacts[i];
                    final letter = c.name.trim().isNotEmpty ? c.name.trim()[0].toUpperCase() : '?';
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFFDFE5E7),
                        child: Text(letter, style: const TextStyle(color: Color(0xFF54656F))),
                      ),
                      title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(c.phone, style: const TextStyle(color: Color(0xFF667781), fontSize: 13)),
                      onTap: () => Navigator.pop(context, c),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LocalVideoFrame extends StatefulWidget {
  final String path;
  final Widget meta;

  const _LocalVideoFrame({required this.path, required this.meta});

  @override
  State<_LocalVideoFrame> createState() => _LocalVideoFrameState();
}

class _LocalVideoFrameState extends State<_LocalVideoFrame> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    if (widget.path.isEmpty) return;
    final c = VideoPlayerController.file(File(widget.path));
    try {
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _controller = c);
    } catch (_) {
      await c.dispose();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final ratio = (c != null && c.value.isInitialized) ? c.value.aspectRatio.clamp(0.75, 1.55) : 4 / 3;

    return AspectRatio(
      aspectRatio: ratio,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (c != null && c.value.isInitialized)
              FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: c.value.size.width,
                  height: c.value.size.height,
                  child: VideoPlayer(c),
                ),
              )
            else
              const ColoredBox(color: Color(0xFF2A3942)),
            Center(
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0x66000000),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.95), width: 1.6),
                ),
                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 38),
              ),
            ),
            Positioned(right: 6, bottom: 6, child: widget.meta),
          ],
        ),
      ),
    );
  }
}
