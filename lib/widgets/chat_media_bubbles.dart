import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../config/cloudinary_config.dart';
import '../services/chat_media_cache.dart';
import 'chat_media_viewer.dart';

String formatMediaSize(int? bytes) {
  if (bytes == null || bytes <= 0) return '';
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) {
    final v = kb >= 100 ? kb.round().toString() : kb.toStringAsFixed(kb >= 10 ? 0 : 1);
    return '$v kB';
  }
  final mb = kb / 1024;
  return '${mb.toStringAsFixed(1)} MB';
}

/// Center pill download control (WhatsApp image style).
class _WaDownloadChip extends StatelessWidget {
  final String label;
  final double? progress;
  final VoidCallback? onTap;

  const _WaDownloadChip({required this.label, this.progress, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: progress != null ? null : onTap,
        borderRadius: BorderRadius.circular(24),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0x99000000),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 28,
                  height: 28,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (progress != null)
                        CircularProgressIndicator(
                          value: progress! <= 0 || progress! >= 1 ? null : progress,
                          strokeWidth: 2,
                          color: Colors.white,
                          backgroundColor: const Color(0x44FFFFFF),
                        )
                      else
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.6),
                          ),
                        ),
                      const Icon(Icons.arrow_downward_rounded, color: Colors.white, size: 16),
                    ],
                  ),
                ),
                if (label.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w500),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom-left video download label (icon + size on media, WhatsApp style).
class _WaVideoDownloadBadge extends StatelessWidget {
  final String label;
  final double? progress;
  final VoidCallback? onTap;

  const _WaVideoDownloadBadge({required this.label, this.progress, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: progress != null ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: progress != null
                ? CircularProgressIndicator(
                    value: progress! <= 0 || progress! >= 1 ? null : progress,
                    strokeWidth: 1.6,
                    color: Colors.white,
                  )
                : const Icon(Icons.arrow_downward_rounded, color: Colors.white, size: 16),
          ),
          if (label.isNotEmpty) ...[
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                shadows: [Shadow(color: Color(0xAA000000), blurRadius: 4)],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _WaMetaPill extends StatelessWidget {
  final Widget child;
  const _WaMetaPill({required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0x99000000),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: child,
      ),
    );
  }
}

/// WhatsApp-style photo: download chip until cached, then clear local image.
class ChatImageBubble extends StatefulWidget {
  final String url;
  final String caption;
  final Widget meta;
  final DateTime? timestamp;
  final bool isOutbound;
  final String? title;
  final double maxWidth;
  final String? tenantId;
  final String? phone;
  final String? waMessageId;

  const ChatImageBubble({
    super.key,
    required this.url,
    required this.caption,
    required this.meta,
    required this.maxWidth,
    this.timestamp,
    this.isOutbound = false,
    this.title,
    this.tenantId,
    this.phone,
    this.waMessageId,
  });

  @override
  State<ChatImageBubble> createState() => _ChatImageBubbleState();
}

class _ChatImageBubbleState extends State<ChatImageBubble> with AutomaticKeepAliveClientMixin {
  File? _local;
  Uint8List? _bytes;
  bool _downloading = false;
  double? _progress;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  String get _displayUrl => cloudinaryDisplayImageUrl(widget.url);

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void didUpdateWidget(covariant ChatImageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _bootstrap();
  }

  bool _looksLikeHeic(List<int> b) {
    if (b.length < 12) return false;
    final ftyp = String.fromCharCodes(b.sublist(4, 8));
    if (ftyp != 'ftyp') return false;
    final brand = String.fromCharCodes(b.sublist(8, 12)).toLowerCase();
    return brand.startsWith('hei') || brand == 'mif1' || brand == 'msf1';
  }

  Future<void> _bootstrap() async {
    final display = _displayUrl;
    try {
      var cached = await ChatMediaCache.getIfCached(display);
      cached ??= await ChatMediaCache.getIfCached(widget.url);
      if (cached != null) {
        final data = await cached.readAsBytes();
        if (data.isNotEmpty && !_looksLikeHeic(data)) {
          if (!mounted) return;
          setState(() {
            _local = cached;
            _bytes = data;
          });
          return;
        }
      }
      final f = await ChatMediaCache.download(display);
      final data = await f.readAsBytes();
      if (!mounted) return;
      setState(() {
        _local = f;
        _bytes = data;
      });
    } catch (_) {}
  }

  Future<void> _download() async {
    if (_downloading || _bytes != null) return;
    setState(() {
      _downloading = true;
      _progress = 0;
      _error = null;
    });
    try {
      final f = await ChatMediaCache.download(
        _displayUrl,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      final data = await f.readAsBytes();
      if (!mounted) return;
      setState(() {
        _local = f;
        _bytes = data;
        _downloading = false;
        _progress = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _progress = null;
        _error = 'Download failed';
      });
    }
  }

  Widget _networkOrPlaceholder() {
    final url = _displayUrl;
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        headers: const {'Accept': 'image/jpeg,image/png,image/webp,image/*;q=0.8'},
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return const ColoredBox(
            color: Color(0xFF2A3942),
            child: Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
              ),
            ),
          );
        },
        errorBuilder: (_, __, ___) => const ColoredBox(
          color: Color(0xFFECEFF1),
          child: Center(
            child: Icon(Icons.broken_image_outlined, color: Color(0xFF8696A0), size: 40),
          ),
        ),
      );
    }
    return const ColoredBox(
      color: Color(0xFF2A3942),
      child: Center(
        child: Icon(Icons.broken_image_outlined, color: Color(0xFF8696A0), size: 40),
      ),
    );
  }

  Widget _paintedImage() {
    final data = _bytes;
    if (data != null && data.isNotEmpty) {
      return Image.memory(
        data,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _networkOrPlaceholder(),
      );
    }
    return _networkOrPlaceholder();
  }

  void _open() {
    openChatMediaViewer(
      context,
      kind: ChatMediaKind.image,
      url: _displayUrl,
      localPath: _local?.path,
      caption: widget.caption,
      timestamp: widget.timestamp,
      isOutbound: widget.isOutbound,
      title: widget.title,
      tenantId: widget.tenantId,
      phone: widget.phone,
      waMessageId: widget.waMessageId,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final caption = widget.caption.trim();
    final maxH = (MediaQuery.of(context).size.height * 0.42).clamp(160.0, 420.0);
    final downloaded = _bytes != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: _open,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: widget.maxWidth,
              height: maxH * 0.72,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _paintedImage(),
                  if (!downloaded && _error != null)
                    Center(
                      child: _WaDownloadChip(
                        label: _error ?? '...',
                        progress: _downloading ? (_progress ?? 0) : null,
                        onTap: _download,
                      ),
                    ),
                  if (caption.isEmpty)
                    Positioned(
                      right: 7,
                      bottom: 7,
                      child: _WaMetaPill(child: widget.meta),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (caption.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
            child: Text(caption, style: const TextStyle(color: Color(0xFF111B21), fontSize: 14.2, height: 1.25)),
          ),
          Align(
            alignment: Alignment.bottomRight,
            child: Padding(padding: const EdgeInsets.fromLTRB(6, 4, 6, 4), child: widget.meta),
          ),
        ],
      ],
    );
  }
}

class ChatVideoBubble extends StatefulWidget {
  final String url;
  final String caption;
  final Widget meta;
  final DateTime? timestamp;
  final bool isOutbound;
  final String? title;
  final String? tenantId;
  final String? phone;
  final String? waMessageId;

  const ChatVideoBubble({
    super.key,
    required this.url,
    required this.caption,
    required this.meta,
    this.timestamp,
    this.isOutbound = false,
    this.title,
    this.tenantId,
    this.phone,
    this.waMessageId,
  });

  @override
  State<ChatVideoBubble> createState() => _ChatVideoBubbleState();
}

class _ChatVideoBubbleState extends State<ChatVideoBubble> {
  File? _local;
  VideoPlayerController? _preview;
  bool _ready = false;
  bool _failed = false;
  bool _checking = true;
  bool _downloading = false;
  double? _progress;
  int? _bytes;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void didUpdateWidget(covariant ChatVideoBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _preview?.dispose();
      _preview = null;
      _bootstrap();
    }
  }

  Future<void> _bootstrap() async {
    setState(() {
      _checking = true;
      _local = null;
      _ready = false;
      _failed = false;
      _downloading = false;
      _progress = null;
    });
    final cached = await ChatMediaCache.getIfCached(widget.url);
    if (!mounted) return;
    if (cached != null) {
      setState(() {
        _local = cached;
        _checking = false;
      });
      await _loadPreview(cached);
      return;
    }
    if (widget.isOutbound) {
      try {
        final f = await ChatMediaCache.download(widget.url);
        if (!mounted) return;
        setState(() {
          _local = f;
          _checking = false;
        });
        await _loadPreview(f);
        return;
      } catch (_) {}
    }
    final n = await ChatMediaCache.remoteBytes(widget.url);
    if (!mounted) return;
    setState(() {
      _bytes = n;
      _checking = false;
    });
  }

  Future<void> _loadPreview(File file) async {
    try {
      final c = VideoPlayerController.file(file);
      await c.initialize();
      await c.setVolume(0);
      await c.pause();
      if (!mounted) {
        await c.dispose();
        return;
      }
      await _preview?.dispose();
      setState(() {
        _preview = c;
        _ready = true;
        _failed = false;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _download({bool openAfter = false}) async {
    if (_downloading || _local != null) {
      if (openAfter && _local != null) _openViewer();
      return;
    }
    setState(() {
      _downloading = true;
      _progress = 0;
    });
    try {
      final f = await ChatMediaCache.download(
        widget.url,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      setState(() {
        _local = f;
        _downloading = false;
        _progress = null;
      });
      await _loadPreview(f);
      if (openAfter && mounted) _openViewer();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _progress = null;
        _failed = true;
      });
    }
  }

  void _onPlayTap() {
    if (_local != null) {
      _openViewer();
    } else {
      _download(openAfter: true);
    }
  }

  void _openViewer() {
    openChatMediaViewer(
      context,
      kind: ChatMediaKind.video,
      url: widget.url,
      localPath: _local?.path,
      caption: widget.caption,
      timestamp: widget.timestamp,
      isOutbound: widget.isOutbound,
      title: widget.title,
      tenantId: widget.tenantId,
      phone: widget.phone,
      waMessageId: widget.waMessageId,
    );
  }

  @override
  void dispose() {
    _preview?.dispose();
    super.dispose();
  }

  String _durationLabel() {
    final d = _preview?.value.duration ?? Duration.zero;
    if (d.inMilliseconds <= 0) return '';
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final caption = widget.caption.trim();
    final duration = _durationLabel();
    final sizeLabel = formatMediaSize(_bytes);
    final downloaded = _local != null;
    final ratio = (_preview?.value.isInitialized == true)
        ? _preview!.value.aspectRatio.clamp(0.75, 1.55)
        : 4 / 3;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onTap: _onPlayTap,
          child: AspectRatio(
            aspectRatio: ratio,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: const Color(0xFF1C252B),
                    child: _failed && !downloaded
                        ? const Center(
                            child: Icon(Icons.videocam_off_outlined, color: Colors.white54, size: 40),
                          )
                        : downloaded && _ready && _preview != null
                            ? ColorFiltered(
                                colorFilter: const ColorFilter.mode(Color(0x33000000), BlendMode.darken),
                                child: FittedBox(
                                  fit: BoxFit.cover,
                                  child: SizedBox(
                                    width: _preview!.value.size.width,
                                    height: _preview!.value.size.height,
                                    child: VideoPlayer(_preview!),
                                  ),
                                ),
                              )
                            : const ColoredBox(color: Color(0xFF2A3942)),
                  ),
                  if (!_checking)
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
                  if (!downloaded && !_checking)
                    Positioned(
                      left: 8,
                      bottom: 8,
                      child: _WaVideoDownloadBadge(
                        label: sizeLabel.isNotEmpty ? sizeLabel : '...',
                        progress: _downloading ? (_progress ?? 0) : null,
                        onTap: () => _download(),
                      ),
                    ),
                  if (downloaded && duration.isNotEmpty)
                    Positioned(
                      left: 8,
                      bottom: 8,
                      child: Text(
                        duration,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          shadows: [Shadow(color: Color(0xAA000000), blurRadius: 4)],
                        ),
                      ),
                    ),
                  if (_checking)
                    const Center(
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                      ),
                    ),
                  if (caption.isEmpty)
                    Positioned(
                      right: 7,
                      bottom: 7,
                      child: _WaMetaPill(child: widget.meta),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (caption.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
            child: Text(caption, style: const TextStyle(color: Color(0xFF111B21), fontSize: 14.2, height: 1.25)),
          ),
          Align(
            alignment: Alignment.bottomRight,
            child: Padding(padding: const EdgeInsets.fromLTRB(8, 4, 8, 6), child: widget.meta),
          ),
        ],
      ],
    );
  }
}

/// WhatsApp-style GIF: muted looping video inside a bubble (not a static photo).
class ChatGifBubble extends StatefulWidget {
  final String url;
  final Widget meta;

  const ChatGifBubble({super.key, required this.url, required this.meta});

  @override
  State<ChatGifBubble> createState() => _ChatGifBubbleState();
}

class _ChatGifBubbleState extends State<ChatGifBubble> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(0);
      await c.play();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _controller = c);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: c != null && c.value.isInitialized ? c.value.aspectRatio.clamp(0.7, 1.6) : 1.2,
          child: ColoredBox(
            color: const Color(0xFF111B21),
            child: _failed
                ? const Center(child: Icon(Icons.gif_box_outlined, color: Colors.white54, size: 40))
                : c == null || !c.value.isInitialized
                    ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Stack(
                        fit: StackFit.expand,
                        children: [
                          FittedBox(
                            fit: BoxFit.cover,
                            child: SizedBox(
                              width: c.value.size.width,
                              height: c.value.size.height,
                              child: VideoPlayer(c),
                            ),
                          ),
                          const Positioned(
                            left: 8,
                            bottom: 8,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Color(0x99000000),
                                borderRadius: BorderRadius.all(Radius.circular(4)),
                              ),
                              child: Padding(
                                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                child: Text(
                                  'GIF',
                                  style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
          ),
        ),
        Align(
          alignment: Alignment.bottomRight,
          child: Padding(padding: const EdgeInsets.fromLTRB(8, 4, 8, 6), child: widget.meta),
        ),
      ],
    );
  }
}

/// WhatsApp sticker: no filled bubble — just the sticker + tiny ticks.
class ChatStickerBubble extends StatelessWidget {
  final String url;
  final Widget meta;
  final bool isOutbound;

  const ChatStickerBubble({
    super.key,
    required this.url,
    required this.meta,
    required this.isOutbound,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: isOutbound ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.network(
          url,
          width: 148,
          height: 148,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          loadingBuilder: (_, child, progress) {
            if (progress == null) return child;
            return const SizedBox(
              width: 148,
              height: 148,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          },
          errorBuilder: (_, __, ___) => const SizedBox(
            width: 148,
            height: 148,
            child: Center(child: Icon(Icons.sticky_note_2_outlined, color: Color(0xFF8696A0), size: 40)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 2, right: 2),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(padding: const EdgeInsets.fromLTRB(6, 2, 6, 2), child: meta),
          ),
        ),
      ],
    );
  }
}

/// WhatsApp voice note bubble.
///
/// Sent:     [avatar/1x] [play] [waveform]
/// Received: [play] [waveform] [avatar/1x]
class ChatAudioBubble extends StatefulWidget {
  final String url;
  final bool isOutbound;
  final String? photoUrl;
  final String letter;
  final int? durationMs;
  final Widget meta;

  const ChatAudioBubble({
    super.key,
    required this.url,
    required this.isOutbound,
    required this.letter,
    required this.meta,
    this.photoUrl,
    this.durationMs,
  });

  @override
  State<ChatAudioBubble> createState() => _ChatAudioBubbleState();
}

class _ChatAudioBubbleState extends State<ChatAudioBubble> {
  static AudioPlayer? _active;
  static const _speeds = [1.0, 1.5, 2.0];
  static const _avatarSize = 52.0;

  final _player = AudioPlayer();
  bool _playing = false;
  double _speed = 1.0;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  late final List<double> _bars;

  @override
  void initState() {
    super.initState();
    _bars = _waWaveform(widget.url);
    if (widget.durationMs != null && widget.durationMs! > 0) {
      _duration = Duration(milliseconds: widget.durationMs!);
    }
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      await _player.setSource(UrlSource(widget.url));
      final d = await _player.getDuration();
      if (d != null && d.inMilliseconds > 0 && mounted) {
        setState(() => _duration = d);
      }
    } catch (_) {}
    _player.onDurationChanged.listen((d) {
      if (d.inMilliseconds > 0 && mounted) setState(() => _duration = d);
    });
    _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _playing = s == PlayerState.playing);
    });
    _player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _playing = false;
        _position = Duration.zero;
      });
    });
  }

  @override
  void dispose() {
    if (_active == _player) _active = null;
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
      return;
    }
    if (_active != null && _active != _player) {
      await _active!.stop();
    }
    _active = _player;
    if (_player.state == PlayerState.paused) {
      await _player.resume();
    } else {
      await _player.play(UrlSource(widget.url));
    }
    await _player.setPlaybackRate(_speed);
  }

  Future<void> _cycleSpeed() async {
    final i = _speeds.indexOf(_speed);
    _speed = _speeds[(i < 0 ? 0 : i + 1) % _speeds.length];
    await _player.setPlaybackRate(_speed);
    if (mounted) setState(() {});
  }

  Future<void> _seek(double progress) async {
    if (_duration.inMilliseconds <= 0) return;
    final ms = (_duration.inMilliseconds * progress.clamp(0.0, 1.0)).round();
    await _player.seek(Duration(milliseconds: ms));
    if (mounted) setState(() => _position = Duration(milliseconds: ms));
  }

  String _fmt(Duration d) {
    final total = d.inMilliseconds < 0 ? Duration.zero : d;
    final m = total.inMinutes;
    final s = total.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Widget _avatarSlot() {
    if (_playing) {
      final label = _speed == 1.5 ? '1.5×' : '${_speed.toInt()}×';
      return GestureDetector(
        onTap: _cycleSpeed,
        child: Container(
          width: _avatarSize,
          height: _avatarSize,
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: Color(0xFF00A884), shape: BoxShape.circle),
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontSize: label.length > 2 ? 13 : 15,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
        ),
      );
    }
    return _VoiceAvatar(
      photoUrl: widget.photoUrl,
      letter: widget.letter,
      isOutbound: widget.isOutbound,
      size: _avatarSize,
    );
  }

  Widget _playButton() {
    return GestureDetector(
      onTap: _toggle,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 34,
        height: 30,
        child: Icon(
          _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
          size: 30,
          color: const Color(0xFF54656F),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final progress = _duration.inMilliseconds <= 0
        ? 0.0
        : (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0);
    final shown = (_playing || _position > Duration.zero) ? _position : _duration;

    final wave = SizedBox(
      height: 30,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => _seek(d.localPosition.dx / constraints.maxWidth),
            onHorizontalDragUpdate: (d) => _seek(d.localPosition.dx / constraints.maxWidth),
            child: CustomPaint(
              size: Size(constraints.maxWidth, 30),
              painter: _WaveformPainter(bars: _bars, progress: progress),
            ),
          );
        },
      ),
    );

    // Play sits on the same row/height as the waveform bars (not the duration).
    final playAndWave = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _playButton(),
        const SizedBox(width: 2),
        Expanded(child: wave),
      ],
    );

    final metaRow = Padding(
      padding: const EdgeInsets.only(left: 36, top: 4),
      child: Row(
        children: [
          Text(
            _fmt(shown),
            style: const TextStyle(color: Color(0xFF667781), fontSize: 11, height: 1),
          ),
          const Spacer(),
          widget.meta,
        ],
      ),
    );

    final body = Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [playAndWave, metaRow],
      ),
    );

    // Sent: avatar | play+wave
    // Received: play+wave | avatar
    final children = widget.isOutbound
        ? <Widget>[_avatarSlot(), const SizedBox(width: 4), body]
        : <Widget>[body, const SizedBox(width: 6), _avatarSlot()];

    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, 8, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: children,
      ),
    );
  }
}

class _VoiceAvatar extends StatelessWidget {
  final String? photoUrl;
  final String letter;
  final bool isOutbound;
  final double size;

  const _VoiceAvatar({
    required this.letter,
    required this.isOutbound,
    required this.size,
    this.photoUrl,
  });

  static const _inboundPalette = [
    Color(0xFFE17076),
    Color(0xFF7BC862),
    Color(0xFF65AADD),
    Color(0xFFEE7E46),
    Color(0xFFA695E7),
  ];

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoUrl != null && photoUrl!.isNotEmpty;
    // WhatsApp sent bubble: peach circle + letter. Received: colored person icon.
    final bg = isOutbound
        ? const Color(0xFFE9D5C3)
        : _inboundPalette[letter.hashCode.abs() % _inboundPalette.length];
    final mic = size * 0.32;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: bg,
              image: hasPhoto ? DecorationImage(image: NetworkImage(photoUrl!), fit: BoxFit.cover) : null,
            ),
            alignment: Alignment.center,
            child: hasPhoto
                ? null
                : isOutbound
                    ? Text(
                        letter.isNotEmpty ? letter[0].toUpperCase() : '?',
                        style: TextStyle(
                          color: const Color(0xFF6D4C41),
                          fontWeight: FontWeight.w600,
                          fontSize: size * 0.42,
                          height: 1,
                        ),
                      )
                    : Icon(Icons.person, size: size * 0.62, color: Colors.white),
          ),
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: mic,
              height: mic,
              decoration: BoxDecoration(
                color: const Color(0xFF00A884),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: Icon(Icons.mic, size: mic * 0.62, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> bars;
  final double progress;

  _WaveformPainter({required this.bars, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    // WhatsApp: thin dense rounded bars, blue played, grey rest, blue thumb.
    const gap = 1.0;
    const barW = 1.55;
    final played = Paint()..color = const Color(0xFF53BDEB);
    final rest = Paint()..color = const Color(0xFFAFB9BF);
    final midY = size.height / 2;

    var x = 0.0;
    var i = 0;
    while (x + barW <= size.width) {
      final amp = bars[i % bars.length];
      final h = (2.2 + amp * (size.height - 2.5)).clamp(2.2, size.height);
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(x + barW / 2, midY), width: barW, height: h),
        const Radius.circular(0.85),
      );
      final through = (x + barW / 2) / size.width <= progress;
      canvas.drawRRect(rect, through ? played : rest);
      x += barW + gap;
      i++;
    }

    final thumbX = (size.width * progress).clamp(5.5, size.width - 5.5);
    final c = Offset(thumbX, midY);
    canvas.drawCircle(c, 6.8, Paint()..color = Colors.white);
    canvas.drawCircle(c, 5.4, Paint()..color = const Color(0xFF53BDEB));
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.bars != bars;
}

/// Speech-like envelope matching WhatsApp's look (quiet gaps + consonant peaks).
List<double> _waWaveform(String seed) {
  final r = Random(seed.hashCode);
  final out = <double>[];
  while (out.length < 140) {
    final quiet = 1 + r.nextInt(4);
    for (var i = 0; i < quiet && out.length < 140; i++) {
      out.add(0.04 + r.nextDouble() * 0.07);
    }
    final burst = 6 + r.nextInt(20);
    var amp = 0.22 + r.nextDouble() * 0.45;
    for (var i = 0; i < burst && out.length < 140; i++) {
      amp += (r.nextDouble() - 0.42) * 0.42;
      amp = amp.clamp(0.1, 1.0);
      if (r.nextDouble() > 0.88) amp = (amp + 0.35).clamp(0.1, 1.0);
      if (r.nextDouble() < 0.1) amp = 0.1 + r.nextDouble() * 0.18;
      out.add(amp);
    }
  }
  return out;
}

class ChatDocumentBubble extends StatelessWidget {
  final String url;
  final String filename;
  final String caption;
  final Widget meta;

  const ChatDocumentBubble({
    super.key,
    required this.url,
    required this.filename,
    required this.caption,
    required this.meta,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F2F5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.picture_as_pdf_outlined, color: Color(0xFF075E54)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      filename,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFF111B21), fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (caption.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(caption, style: const TextStyle(color: Color(0xFF111B21), fontSize: 14.2)),
            ),
          Align(alignment: Alignment.bottomRight, child: Padding(padding: const EdgeInsets.only(top: 4), child: meta)),
        ],
      ),
    );
  }
}
