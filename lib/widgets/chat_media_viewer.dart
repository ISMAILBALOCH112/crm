import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../config/cloudinary_config.dart';
import '../services/chat_media_cache.dart';
import '../services/chat_service.dart';

enum ChatMediaKind { image, video }

Future<void> openChatMediaViewer(
  BuildContext context, {
  required ChatMediaKind kind,
  required String url,
  String? localPath,
  String? caption,
  DateTime? timestamp,
  bool isOutbound = false,
  String? title,
  String? tenantId,
  String? phone,
  String? waMessageId,
}) {
  return Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 180),
      reverseTransitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (_, _, _) => ChatMediaViewerPage(
        kind: kind,
        url: url,
        localPath: localPath,
        caption: caption,
        timestamp: timestamp,
        isOutbound: isOutbound,
        title: title,
        tenantId: tenantId,
        phone: phone,
        waMessageId: waMessageId,
      ),
      transitionsBuilder: (_, anim, _, child) {
        return FadeTransition(opacity: anim, child: child);
      },
    ),
  );
}

class ChatMediaViewerPage extends StatefulWidget {
  final ChatMediaKind kind;
  final String url;
  final String? localPath;
  final String? caption;
  final DateTime? timestamp;
  final bool isOutbound;
  final String? title;
  final String? tenantId;
  final String? phone;
  final String? waMessageId;

  const ChatMediaViewerPage({
    super.key,
    required this.kind,
    required this.url,
    this.localPath,
    this.caption,
    this.timestamp,
    this.isOutbound = false,
    this.title,
    this.tenantId,
    this.phone,
    this.waMessageId,
  });

  @override
  State<ChatMediaViewerPage> createState() => _ChatMediaViewerPageState();
}

class _ChatMediaViewerPageState extends State<ChatMediaViewerPage> {
  bool _chromeVisible = true;
  double _dragOffset = 0;
  VideoPlayerController? _video;
  bool _videoReady = false;
  bool _videoFailed = false;
  Timer? _hideTimer;
  bool _saving = false;
  bool _sendingReply = false;
  String? _resolvedLocalPath;
  final _replyCtrl = TextEditingController();
  final _replyFocus = FocusNode();
  final _chat = ChatService();

  @override
  void initState() {
    super.initState();
    _resolvedLocalPath = widget.localPath;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (widget.kind == ChatMediaKind.video) _initVideo();
    _scheduleHide();
  }

  Future<void> _initVideo() async {
    try {
      final local = _resolvedLocalPath;
      final c = (local != null && local.isNotEmpty && File(local).existsSync())
          ? VideoPlayerController.file(File(local))
          : VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await c.initialize();
      c.addListener(() {
        if (mounted) setState(() {});
      });
      await c.play();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() {
        _video = c;
        _videoReady = true;
      });
      _scheduleHide();
    } catch (_) {
      if (mounted) setState(() => _videoFailed = true);
    }
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    // WhatsApp: chrome stays on images; only auto-hides while video is playing.
    if (widget.kind != ChatMediaKind.video) return;
    if (!_chromeVisible || _replyFocus.hasFocus) return;
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted || _replyFocus.hasFocus) return;
      if (_video?.value.isPlaying != true) return;
      setState(() => _chromeVisible = false);
    });
  }

  void _toggleChrome() {
    if (_replyFocus.hasFocus) {
      _replyFocus.unfocus();
      return;
    }
    setState(() => _chromeVisible = !_chromeVisible);
    if (_chromeVisible) _scheduleHide();
  }

  void _togglePlay() {
    final c = _video;
    if (c == null || !c.value.isInitialized) return;
    if (c.value.isPlaying) {
      c.pause();
      setState(() => _chromeVisible = true);
      _hideTimer?.cancel();
    } else {
      c.play();
      _scheduleHide();
    }
    setState(() {});
  }

  Future<File?> _ensureLocalFile() async {
    final existing = _resolvedLocalPath;
    if (existing != null && existing.isNotEmpty && File(existing).existsSync()) {
      return File(existing);
    }
    final cached = await ChatMediaCache.getIfCached(widget.url);
    if (cached != null) {
      _resolvedLocalPath = cached.path;
      return cached;
    }
    final downloaded = await ChatMediaCache.download(widget.url);
    _resolvedLocalPath = downloaded.path;
    return downloaded;
  }

  Future<void> _saveToGallery() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _chromeVisible = true;
    });
    try {
      final perm = await PhotoManager.requestPermissionExtend();
      if (!perm.hasAccess) {
        _toast('Gallery permission needed');
        return;
      }
      final file = await _ensureLocalFile();
      if (file == null || !await file.exists()) {
        _toast('Download failed');
        return;
      }
      final name = file.uri.pathSegments.isNotEmpty
          ? file.uri.pathSegments.last
          : (widget.kind == ChatMediaKind.video ? 'video.mp4' : 'photo.jpg');
      if (widget.kind == ChatMediaKind.video) {
        await PhotoManager.editor.saveVideo(file, title: name);
      } else {
        await PhotoManager.editor.saveImageWithPath(file.path, title: name);
      }
      if (!mounted) return;
      _toast('Saved to gallery');
    } catch (_) {
      if (mounted) _toast('Could not save');
    } finally {
      if (mounted) setState(() => _saving = false);
      _scheduleHide();
    }
  }

  Future<void> _forward() async {
    try {
      final file = await _ensureLocalFile();
      if (file == null || !await file.exists()) {
        _toast('Download failed');
        return;
      }
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
    } catch (_) {
      _toast('Could not share');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        backgroundColor: const Color(0xFF1F2C34),
      ),
    );
  }

  Future<void> _sendReply([String? raw]) async {
    final text = (raw ?? _replyCtrl.text).trim();
    if (text.isEmpty || _sendingReply) return;
    final tenantId = widget.tenantId;
    final phone = widget.phone;
    if (tenantId == null || tenantId.isEmpty || phone == null || phone.isEmpty) {
      _toast('Reply unavailable');
      return;
    }
    setState(() => _sendingReply = true);
    try {
      await _chat.sendMessage(
        tenantId: tenantId,
        to: phone,
        text: text,
        replyToMessageId: widget.waMessageId,
      );
      if (!mounted) return;
      _replyCtrl.clear();
      _replyFocus.unfocus();
      _toast('Sent');
      Navigator.of(context).maybePop();
    } catch (_) {
      if (mounted) _toast('Could not send reply');
    } finally {
      if (mounted) setState(() => _sendingReply = false);
    }
  }

  void _onQuickReact(String emoji) {
    _sendReply(emoji);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _video?.dispose();
    _replyCtrl.dispose();
    _replyFocus.dispose();
    super.dispose();
  }

  String get _headerTitle {
    if (widget.isOutbound) return 'You';
    final t = (widget.title ?? '').trim();
    return t.isNotEmpty ? t : 'Chat';
  }

  String get _relativeTime {
    final t = widget.timestamp;
    if (t == null) return '';
    final diff = DateTime.now().difference(t);
    if (diff.inSeconds < 45) return 'Just now';
    if (diff.inMinutes < 60) {
      final m = diff.inMinutes.clamp(1, 59);
      return m == 1 ? '1 minute ago' : '$m minutes ago';
    }
    if (diff.inHours < 24) {
      final h = diff.inHours;
      return h == 1 ? '1 hour ago' : '$h hours ago';
    }
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return DateFormat('MMM d, yyyy').format(t);
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    final opacity = (1.0 - (_dragOffset.abs() / 280)).clamp(0.35, 1.0);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black.withValues(alpha: opacity),
        resizeToAvoidBottomInset: true,
        body: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              onTap: _toggleChrome,
              onVerticalDragUpdate: (d) {
                if (_replyFocus.hasFocus) return;
                setState(() => _dragOffset += d.delta.dy);
              },
              onVerticalDragEnd: (d) {
                if (_replyFocus.hasFocus) return;
                if (_dragOffset.abs() > 120 || (d.primaryVelocity?.abs() ?? 0) > 700) {
                  Navigator.of(context).maybePop();
                } else {
                  setState(() => _dragOffset = 0);
                }
              },
              child: Transform.translate(
                offset: Offset(0, _dragOffset),
                child: Transform.scale(
                  scale: (1.0 - _dragOffset.abs() / 1200).clamp(0.88, 1.0),
                  child: Center(child: _buildMedia()),
                ),
              ),
            ),
            IgnorePointer(
              ignoring: !_chromeVisible,
              child: AnimatedOpacity(
                opacity: _chromeVisible ? 1 : 0,
                duration: const Duration(milliseconds: 160),
                child: _buildTopChrome(topPad),
              ),
            ),
            IgnorePointer(
              ignoring: !_chromeVisible,
              child: AnimatedOpacity(
                opacity: _chromeVisible ? 1 : 0,
                duration: const Duration(milliseconds: 160),
                child: _buildBottomChrome(bottomPad),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMedia() {
    if (widget.kind == ChatMediaKind.image) {
      final local = _resolvedLocalPath;
      final image = (local != null && local.isNotEmpty && File(local).existsSync())
          ? Image.file(
              File(local),
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) =>
                  const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 64),
            )
          : Image.network(
              cloudinaryDisplayImageUrl(widget.url),
              fit: BoxFit.contain,
              loadingBuilder: (_, child, progress) {
                if (progress == null) return child;
                return const SizedBox(
                  width: 72,
                  height: 72,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                );
              },
              errorBuilder: (_, _, _) =>
                  const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 64),
            );
      return InteractiveViewer(
        minScale: 1,
        maxScale: 4,
        child: image,
      );
    }

    if (_videoFailed) {
      return const Icon(Icons.videocam_off_outlined, color: Colors.white54, size: 64);
    }
    final c = _video;
    if (!_videoReady || c == null || !c.value.isInitialized) {
      return const CircularProgressIndicator(color: Colors.white, strokeWidth: 2);
    }

    return AspectRatio(
      aspectRatio: c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio,
      child: Stack(
        alignment: Alignment.center,
        children: [
          VideoPlayer(c),
          if (_chromeVisible)
            Material(
              color: Colors.black45,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _togglePlay,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Icon(
                    c.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 42,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTopChrome(double topPad) {
    return Align(
      alignment: Alignment.topCenter,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(2, topPad + 2, 4, 18),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xCC000000), Color(0x00000000)],
            ),
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _headerTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        height: 1.15,
                      ),
                    ),
                    if (_relativeTime.isNotEmpty)
                      Text(
                        _relativeTime,
                        style: const TextStyle(color: Color(0xFFCACACA), fontSize: 13, height: 1.2),
                      ),
                  ],
                ),
              ),
              _topIcon(
                onPressed: _saving ? null : _saveToGallery,
                icon: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.download, color: Colors.white, size: 24),
              ),
              _topIcon(
                onPressed: _forward,
                icon: const Icon(Icons.shortcut, color: Colors.white, size: 26),
              ),
              _topIcon(
                onPressed: () => _toast('Status'),
                icon: const Icon(Icons.add_circle_outline, color: Colors.white, size: 23),
              ),
              PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.more_vert, color: Colors.white, size: 24),
                color: const Color(0xFF233138),
                onSelected: (v) {
                  if (v == 'save') _saveToGallery();
                  if (v == 'share') _forward();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'save', child: Text('Save', style: TextStyle(color: Colors.white))),
                  PopupMenuItem(value: 'share', child: Text('Share', style: TextStyle(color: Colors.white))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topIcon({required VoidCallback? onPressed, required Widget icon}) {
    return IconButton(
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(6),
      constraints: const BoxConstraints(minWidth: 38, minHeight: 40),
      icon: icon,
    );
  }

  Widget _buildBottomChrome(double bottomPad) {
    final caption = (widget.caption ?? '').trim();
    final c = _video;
    final showScrubber = widget.kind == ChatMediaKind.video && c != null && c.value.isInitialized;
    final pos = c?.value.position ?? Duration.zero;
    final dur = c?.value.duration ?? Duration.zero;
    final maxMs = dur.inMilliseconds <= 0 ? 1.0 : dur.inMilliseconds.toDouble();
    final value = pos.inMilliseconds.clamp(0, maxMs.toInt()).toDouble();
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: EdgeInsets.fromLTRB(12, 12, 12, keyboard > 0 ? 8 : bottomPad + 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (caption.isNotEmpty) ...[
                Text(caption, style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.3)),
                const SizedBox(height: 10),
              ],
              if (showScrubber) ...[
                Row(
                  children: [
                    Text(_fmt(pos), style: const TextStyle(color: Colors.white70, fontSize: 11)),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 2.2,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                          activeTrackColor: const Color(0xFF25D366),
                          inactiveTrackColor: const Color(0x55FFFFFF),
                          thumbColor: Colors.white,
                        ),
                        child: Slider(
                          min: 0,
                          max: maxMs,
                          value: value,
                          onChanged: (v) {
                            c.seekTo(Duration(milliseconds: v.round()));
                            setState(() => _chromeVisible = true);
                            _scheduleHide();
                          },
                        ),
                      ),
                    ),
                    Text(_fmt(dur), style: const TextStyle(color: Colors.white70, fontSize: 11)),
                  ],
                ),
                const SizedBox(height: 6),
              ],
              // WhatsApp media viewer: single dark reply bar (TextField must not paint white)
              Container(
                height: 50,
                decoration: BoxDecoration(
                  color: const Color(0xFF1F2C34),
                  borderRadius: BorderRadius.circular(28),
                ),
                padding: const EdgeInsets.only(left: 18, right: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Theme(
                        data: Theme.of(context).copyWith(
                          inputDecorationTheme: const InputDecorationTheme(
                            filled: true,
                            fillColor: Colors.transparent,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            errorBorder: InputBorder.none,
                            focusedErrorBorder: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                        child: TextField(
                          controller: _replyCtrl,
                          focusNode: _replyFocus,
                          style: const TextStyle(color: Colors.white, fontSize: 16.5),
                          cursorColor: const Color(0xFF25D366),
                          textInputAction: TextInputAction.send,
                          decoration: const InputDecoration(
                            hintText: 'Reply',
                            hintStyle: TextStyle(color: Color(0xFF8696A0), fontSize: 16.5),
                            filled: true,
                            fillColor: Colors.transparent,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 12),
                          ),
                          onTap: () {
                            setState(() => _chromeVisible = true);
                            _hideTimer?.cancel();
                          },
                          onSubmitted: (v) => _sendReply(v),
                        ),
                      ),
                    ),
                    _reactBtn('❤️', () => _onQuickReact('❤️')),
                    const SizedBox(width: 6),
                    _reactBtn('😂', () => _onQuickReact('😂')),
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: () => _toast('Emoji'),
                      customBorder: const CircleBorder(),
                      child: const Padding(
                        padding: EdgeInsets.all(2),
                        child: Icon(Icons.add_reaction_outlined, color: Colors.white, size: 26),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _reactBtn(String emoji, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 4),
        child: Text(emoji, style: const TextStyle(fontSize: 22, height: 1)),
      ),
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString();
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    if (h > 0) return '$h:${m.padLeft(2, '0')}:$s';
    return '$m:$s';
  }
}
