import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../services/chat_service.dart';
import '../../theme/app_theme.dart';

// Real WhatsApp colors, deliberately not the app's pink theme — this screen
// is meant to read as an authentic WhatsApp conversation.
class _WaColors {
  _WaColors._();
  static const chatBackground = Color(0xFFECE5DD);
  static const outboundBubble = Color(0xFFDCF8C6);
  static const inboundBubble = Color(0xFFFFFFFF);
  static const tickGrey = Color(0xFF8696A0);
  static const tickBlue = Color(0xFF53BDEB);
}

// A generic (not WhatsApp's actual copyrighted artwork) scattered doodle
// pattern, echoing the spirit of WhatsApp's chat wallpaper without copying
// it — faint outline icons tiled at a fixed, seeded layout so it doesn't
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
  bool _isSending = false;

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    _textController.clear();
    try {
      await _chatService.sendMessage(tenantId: widget.tenantId, to: widget.phone, text: text);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not send message. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final initial = widget.contactName.isNotEmpty ? widget.contactName[0].toUpperCase() : '?';

    // The rest of the app uses Inter (see AppTheme), but Inter renders
    // noticeably wider than WhatsApp's own system font at the same size —
    // that's what was making our bubbles look bigger than WhatsApp's for
    // identical text. Reset to the platform default just for this screen.
    return Theme(
      data: Theme.of(context).copyWith(
        textTheme: Theme.of(context).textTheme.apply(fontFamily: 'Roboto'),
      ),
      child: Scaffold(
      backgroundColor: _WaColors.chatBackground,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.surfaceSolid,
            border: Border(bottom: BorderSide(color: AppColors.surfaceBorder)),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Container(
                    width: 38,
                    height: 38,
                    decoration: const BoxDecoration(color: AppColors.primaryLight, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: Text(initial, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.contactName,
                      style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 15.5),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.perm_media_outlined, color: AppColors.textSecondary),
                    onPressed: () {},
                  ),
                  IconButton(
                    icon: const Icon(Icons.call_outlined, color: AppColors.textSecondary),
                    onPressed: () {},
                  ),
                  IconButton(
                    icon: const Icon(Icons.more_vert_rounded, color: AppColors.textSecondary),
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: CustomPaint(painter: _ChatWallpaperPainter())),
          Column(
            children: [
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _chatService.watchMessages(widget.tenantId, widget.phone),
              builder: (context, snapshot) {
                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Column(
                    children: [
                      _EncryptionNotice(),
                      Expanded(
                        child: Center(
                          child: Text('No messages yet', style: TextStyle(color: AppColors.textSecondary)),
                        ),
                      ),
                    ],
                  );
                }

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scrollController.hasClients) {
                    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
                  }
                });

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data();
                    final timestamp = (data['timestamp'] as Timestamp?)?.toDate();
                    final showDateSeparator = index == 0 ||
                        !_isSameDay(timestamp, (docs[index - 1].data()['timestamp'] as Timestamp?)?.toDate());
                    final isOutbound = data['direction'] == 'outbound';
                    // The little bubble tail only appears on the first message
                    // of a run from the same sender, exactly like WhatsApp —
                    // a new date section or a sender switch both start a run.
                    final isFirstInGroup = index == 0 ||
                        showDateSeparator ||
                        (docs[index - 1].data()['direction'] == 'outbound') != isOutbound;

                    return Column(
                      children: [
                        if (index == 0) const _EncryptionNotice(),
                        if (showDateSeparator && timestamp != null) _DateSeparator(date: timestamp),
                        _MessageBubble(
                          text: data['text'] as String? ?? '',
                          isOutbound: isOutbound,
                          status: data['status'] as String?,
                          timestamp: timestamp,
                          showTail: isFirstInGroup,
                        ),
                      ],
                    );
                  },
                );
                  },
                ),
              ),
              _MessageInputBar(controller: _textController, isSending: _isSending, onSend: _send),
            ],
          ),
        ],
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

class _EncryptionNotice extends StatelessWidget {
  const _EncryptionNotice();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: const Color(0xFFFFF3CC), borderRadius: BorderRadius.circular(8)),
        child: RichText(
          textAlign: TextAlign.center,
          text: const TextSpan(
            children: [
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Icon(Icons.lock_outline_rounded, size: 12, color: Color(0xFF7A6A3E)),
              ),
              TextSpan(text: '  '),
              TextSpan(
                text: 'Messages and calls are end-to-end encrypted. Only people in this chat can read, listen to, or share them. ',
                style: TextStyle(color: Color(0xFF7A6A3E), fontSize: 12.5, height: 1.35),
              ),
              TextSpan(
                text: 'Learn more',
                style: TextStyle(color: Color(0xFF7A6A3E), fontSize: 12.5, height: 1.35, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final String text;
  final bool isOutbound;
  final String? status;
  final DateTime? timestamp;
  final bool showTail;

  const _MessageBubble({
    required this.text,
    required this.isOutbound,
    this.status,
    this.timestamp,
    required this.showTail,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isOutbound ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.79),
        margin: const EdgeInsets.symmetric(vertical: 2),
        child: CustomPaint(
          painter: _TailedBubblePainter(
            color: isOutbound ? _WaColors.outboundBubble : _WaColors.inboundBubble,
            isOutbound: isOutbound,
            showTail: showTail,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
            // WhatsApp doesn't place time+ticks right after the last word —
            // it reserves invisible space for it at the end of the text (so
            // wrapping accounts for it) and then anchors the real widget to
            // the bubble's bottom-right corner, which is why there's often a
            // big gap between the last word and the timestamp.
            child: Stack(
              children: [
                Text.rich(
                  TextSpan(
                    style: const TextStyle(color: Color(0xFF111B21), fontSize: 14.5),
                    children: [
                      TextSpan(text: text),
                      WidgetSpan(
                        child: Opacity(
                          opacity: 0,
                          child: _TimeTicksRow(timestamp: timestamp, isOutbound: isOutbound, status: status),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: _TimeTicksRow(timestamp: timestamp, isOutbound: isOutbound, status: status),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TimeTicksRow extends StatelessWidget {
  final DateTime? timestamp;
  final bool isOutbound;
  final String? status;

  const _TimeTicksRow({this.timestamp, required this.isOutbound, this.status});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (timestamp != null)
            Text(
              DateFormat('h:mm a').format(timestamp!),
              style: const TextStyle(color: Color(0xFF667781), fontSize: 11),
            ),
          if (isOutbound) ...[const SizedBox(width: 4), _StatusTicks(status: status)],
        ],
      ),
    );
  }
}

// Draws a WhatsApp-style bubble: rounded rect where the corner nearest the
// screen edge is left sharp (no radius) on the first bubble of a run from
// the same sender — verified against a real WhatsApp chat pixel-by-pixel:
// it's a plain squared corner, not a protruding tail shape.
class _TailedBubblePainter extends CustomPainter {
  final Color color;
  final bool isOutbound;
  final bool showTail;

  const _TailedBubblePainter({required this.color, required this.isOutbound, required this.showTail});

  static const _radius = 7.5;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..isAntiAlias = true;

    final sharpCorner = showTail ? Radius.zero : const Radius.circular(_radius);
    final rrect = RRect.fromRectAndCorners(
      Offset.zero & size,
      topLeft: isOutbound ? const Radius.circular(_radius) : sharpCorner,
      topRight: isOutbound ? sharpCorner : const Radius.circular(_radius),
      bottomLeft: const Radius.circular(_radius),
      bottomRight: const Radius.circular(_radius),
    );
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(covariant _TailedBubblePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.isOutbound != isOutbound || oldDelegate.showTail != showTail;
}

class _StatusTicks extends StatelessWidget {
  final String? status;

  const _StatusTicks({this.status});

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case 'read':
        return const Icon(Icons.done_all_rounded, size: 19, color: _WaColors.tickBlue);
      case 'delivered':
        return const Icon(Icons.done_all_rounded, size: 19, color: _WaColors.tickGrey);
      case 'sent':
        return const Icon(Icons.done_rounded, size: 19, color: _WaColors.tickGrey);
      default:
        return const Icon(Icons.access_time_rounded, size: 15, color: _WaColors.tickGrey);
    }
  }
}

class _MessageInputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool isSending;
  final VoidCallback onSend;

  const _MessageInputBar({required this.controller, required this.isSending, required this.onSend});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 10, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Container(
                constraints: const BoxConstraints(minHeight: 46),
                decoration: BoxDecoration(
                  color: AppColors.surfaceSolid,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 3, offset: const Offset(0, 1))],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.emoji_emotions_outlined, color: AppColors.textSecondary, size: 22),
                      onPressed: () {},
                    ),
                    Expanded(
                      child: TextField(
                        controller: controller,
                        minLines: 1,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          hintText: 'Message',
                          hintStyle: TextStyle(color: AppColors.textSecondary),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          isCollapsed: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 12),
                        ),
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14.5),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.attach_file_rounded, color: AppColors.textSecondary, size: 21),
                      onPressed: () {},
                    ),
                    IconButton(
                      icon: const Icon(Icons.camera_alt_rounded, color: AppColors.textSecondary, size: 21),
                      onPressed: () {},
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                final hasText = value.text.trim().isNotEmpty;
                return GestureDetector(
                  onTap: isSending ? null : (hasText ? onSend : null),
                  child: Container(
                    width: 46,
                    height: 46,
                    decoration: const BoxDecoration(gradient: AppColors.primaryGradient, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: isSending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Icon(hasText ? Icons.send_rounded : Icons.mic_rounded, color: Colors.white, size: 20),
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
