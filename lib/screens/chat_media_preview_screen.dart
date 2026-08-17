import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

class ChatMediaPreviewResult {
  final List<XFile> files;
  final String? caption;

  const ChatMediaPreviewResult({required this.files, this.caption});
}

bool isChatVideoFile(XFile file) {
  final p = file.path.toLowerCase();
  return p.endsWith('.mp4') ||
      p.endsWith('.mov') ||
      p.endsWith('.mkv') ||
      p.endsWith('.webm') ||
      p.endsWith('.3gp') ||
      p.endsWith('.avi');
}

/// WhatsApp-style preview before sending one or more images.
Future<ChatMediaPreviewResult?> openChatMediaPreview(
  BuildContext context, {
  required List<XFile> files,
}) {
  if (files.isEmpty) return Future.value(null);
  return Navigator.of(context).push<ChatMediaPreviewResult>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => ChatMediaPreviewScreen(initialFiles: files),
    ),
  );
}

/// Full-screen video preview with caption before send.
Future<ChatMediaPreviewResult?> openChatVideoPreview(
  BuildContext context, {
  required XFile file,
}) {
  return Navigator.of(context).push<ChatMediaPreviewResult>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => ChatMediaPreviewScreen(initialFiles: [file], videoMode: true),
    ),
  );
}

class ChatMediaPreviewScreen extends StatefulWidget {
  final List<XFile> initialFiles;
  final bool videoMode;

  const ChatMediaPreviewScreen({
    super.key,
    required this.initialFiles,
    this.videoMode = false,
  });

  @override
  State<ChatMediaPreviewScreen> createState() => _ChatMediaPreviewScreenState();
}

class _ChatMediaPreviewScreenState extends State<ChatMediaPreviewScreen> {
  late final List<XFile> _files;
  late final PageController _pageCtrl;
  final _captionCtrl = TextEditingController();
  int _index = 0;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _files = List<XFile>.from(widget.initialFiles);
    _pageCtrl = PageController();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _captionCtrl.dispose();
    super.dispose();
  }

  Future<void> _addMore() async {
    try {
      final more = await ImagePicker().pickMultiImage(imageQuality: 85, limit: 30);
      if (more.isEmpty || !mounted) return;
      setState(() {
        _files.addAll(more);
        _index = _files.length - 1;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pageCtrl.hasClients) {
          _pageCtrl.jumpToPage(_index);
        }
      });
    } catch (_) {}
  }

  void _removeAt(int i) {
    if (_files.length <= 1) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _files.removeAt(i);
      if (_index >= _files.length) _index = _files.length - 1;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageCtrl.hasClients) {
        _pageCtrl.jumpToPage(_index);
      }
    });
  }

  void _confirmSend() {
    if (_sending || _files.isEmpty) return;
    setState(() => _sending = true);
    final caption = _captionCtrl.text.trim();
    Navigator.of(context).pop(
      ChatMediaPreviewResult(
        files: List<XFile>.from(_files),
        caption: caption.isEmpty ? null : caption,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.videoMode) return _buildVideoPreview(context);
    return _buildImagePreview(context);
  }

  Widget _buildVideoPreview(BuildContext context) {
    final file = _files[_index];
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                  const Expanded(
                    child: Text(
                      'Video preview',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Expanded(
              child: _VideoPreviewPlayer(path: file.path),
            ),
            Container(
              color: const Color(0xFF1F2C34),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _captionCtrl,
                      style: const TextStyle(color: Colors.white),
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Add a caption…',
                        hintStyle: const TextStyle(color: Colors.white54),
                        filled: true,
                        fillColor: const Color(0xFF2A3942),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Material(
                    color: const Color(0xFF25D366),
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _sending ? null : _confirmSend,
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: _sending
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.send_rounded, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePreview(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                  Expanded(
                    child: Text(
                      _files.length == 1 ? 'Preview' : '${_index + 1} / ${_files.length}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Add more',
                    onPressed: _sending ? null : _addMore,
                    icon: const Icon(Icons.add_photo_alternate_outlined, color: Colors.white),
                  ),
                  IconButton(
                    tooltip: 'Remove',
                    onPressed: _sending ? null : () => _removeAt(_index),
                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.white70),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageCtrl,
                itemCount: _files.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) {
                  final path = _files[i].path;
                  return InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    child: Center(
                      child: Image.file(
                        File(path),
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white54, size: 64),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (_files.length > 1)
              SizedBox(
                height: 72,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: _files.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final selected = i == _index;
                    return GestureDetector(
                      onTap: () {
                        _pageCtrl.animateToPage(i, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
                        setState(() => _index = i);
                      },
                      child: Container(
                        width: 56,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: selected ? const Color(0xFF25D366) : Colors.white24,
                            width: selected ? 2.5 : 1,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Image.file(File(_files[i].path), fit: BoxFit.cover),
                      ),
                    );
                  },
                ),
              ),
            Container(
              color: const Color(0xFF1F2C34),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _captionCtrl,
                      style: const TextStyle(color: Colors.white),
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: _files.length > 1 ? 'Caption (first image)' : 'Add a caption…',
                        hintStyle: const TextStyle(color: Colors.white54),
                        filled: true,
                        fillColor: const Color(0xFF2A3942),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Material(
                    color: const Color(0xFF25D366),
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _sending ? null : _confirmSend,
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: _sending
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.send_rounded, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoPreviewPlayer extends StatefulWidget {
  final String path;

  const _VideoPreviewPlayer({required this.path});

  @override
  State<_VideoPreviewPlayer> createState() => _VideoPreviewPlayerState();
}

class _VideoPreviewPlayerState extends State<_VideoPreviewPlayer> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
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
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    setState(() {
      if (c.value.isPlaying) {
        c.pause();
      } else {
        c.play();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return const Center(
        child: Icon(Icons.videocam_off_outlined, color: Colors.white54, size: 64),
      );
    }
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(color: Colors.white54));
    }

    return GestureDetector(
      onTap: _togglePlay,
      child: Center(
        child: AspectRatio(
          aspectRatio: c.value.aspectRatio.clamp(0.5, 2.5),
          child: Stack(
            alignment: Alignment.center,
            children: [
              VideoPlayer(c),
              if (!c.value.isPlaying)
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: const Color(0x66000000),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withValues(alpha: 0.95), width: 2),
                  ),
                  child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 42),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
