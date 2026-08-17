import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

/// WhatsApp attach sheet: actions + recent grid; drag/scroll up → full Recents picker.
class ChatAttachSheet extends StatefulWidget {
  const ChatAttachSheet({super.key});

  @override
  State<ChatAttachSheet> createState() => _ChatAttachSheetState();
}

class _ChatAttachSheetState extends State<ChatAttachSheet> {
  final _sheetCtrl = DraggableScrollableController();
  List<AssetPathEntity> _albums = [];
  AssetPathEntity? _album;
  List<AssetEntity> _assets = [];
  bool _loading = true;
  double _extent = 0.58;
  int _page = 0;
  bool _loadingMore = false;

  bool get _expanded => _extent >= 0.78;

  @override
  void initState() {
    super.initState();
    _loadAlbums();
  }

  @override
  void dispose() {
    _sheetCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAlbums() async {
    try {
      final state = await PhotoManager.requestPermissionExtend();
      if (!state.isAuth && !state.hasAccess) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final paths = await PhotoManager.getAssetPathList(type: RequestType.common);
      if (paths.isEmpty) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      _albums = paths;
      _album = paths.first;
      await _loadPage(reset: true);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadPage({bool reset = false}) async {
    if (_album == null) return;
    if (reset) {
      _page = 0;
      _assets = [];
    }
    setState(() {
      if (reset) _loading = true;
      _loadingMore = !reset;
    });
    try {
      final next = await _album!.getAssetListPaged(page: _page, size: 60);
      if (!mounted) return;
      setState(() {
        _assets = reset ? next : [..._assets, ...next];
        _page += 1;
        _loading = false;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  Future<void> _pickAlbum() async {
    if (_albums.isEmpty) return;
    final chosen = await showModalBottomSheet<AssetPathEntity>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final a in _albums)
              ListTile(
                title: Text(a.name),
                trailing: a.id == _album?.id ? const Icon(Icons.check, color: Color(0xFF00A884)) : null,
                onTap: () => Navigator.pop(ctx, a),
              ),
          ],
        ),
      ),
    );
    if (chosen == null || chosen.id == _album?.id) return;
    setState(() => _album = chosen);
    await _loadPage(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    final bottom = MediaQuery.of(context).padding.bottom;

    return SizedBox(
      height: h,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          // Dim tap area — closes when not expanded gesture
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.pop(context),
              child: const ColoredBox(color: Colors.transparent),
            ),
          ),
          if (!_expanded)
            Positioned(
              left: 6,
              right: 6,
              bottom: h * _extent + 8,
              child: IgnorePointer(
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: const [
                            BoxShadow(color: Color(0x22000000), blurRadius: 4, offset: Offset(0, 1)),
                          ],
                        ),
                        child: const Row(
                          children: [
                            SizedBox(width: 10),
                            Icon(Icons.emoji_emotions_outlined, color: Color(0xFF8696A0), size: 24),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text('Message', style: TextStyle(color: Color(0xFF8696A0), fontSize: 16)),
                            ),
                            Icon(Icons.attach_file_rounded, color: Color(0xFF54656F), size: 22),
                            SizedBox(width: 10),
                            Icon(Icons.camera_alt_rounded, color: Color(0xFF8696A0), size: 22),
                            SizedBox(width: 12),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 48,
                      height: 48,
                      decoration: const BoxDecoration(color: Color(0xFF00A884), shape: BoxShape.circle),
                      child: const Icon(Icons.mic_rounded, color: Colors.white, size: 22),
                    ),
                  ],
                ),
              ),
            ),
          NotificationListener<DraggableScrollableNotification>(
            onNotification: (n) {
              setState(() => _extent = n.extent);
              return false;
            },
            child: DraggableScrollableSheet(
              controller: _sheetCtrl,
              expand: true,
              initialChildSize: 0.58,
              minChildSize: 0.48,
              maxChildSize: 0.94,
              builder: (context, scrollController) {
                return Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    children: [
                      CustomScrollView(
                        controller: scrollController,
                        slivers: [
                          SliverToBoxAdapter(
                            child: Column(
                              children: [
                                const SizedBox(height: 10),
                                Container(
                                  width: 36,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFD1D7DB),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                                if (_expanded) ...[
                                  const SizedBox(height: 8),
                                  _ExpandedHeader(
                                    albumName: _album?.name.isNotEmpty == true ? _album!.name : 'Recents',
                                    onClose: () => Navigator.pop(context),
                                    onAlbum: _pickAlbum,
                                  ),
                                ] else ...[
                                  const SizedBox(height: 16),
                                  _ActionsGrid(
                                    onGallery: () => _sheetCtrl.animateTo(
                                      0.94,
                                      duration: const Duration(milliseconds: 280),
                                      curve: Curves.easeOutCubic,
                                    ),
                                    onCamera: () => Navigator.pop(context, 'camera'),
                                    onDocument: () => Navigator.pop(context, 'document'),
                                    onAudio: () => Navigator.pop(context, 'audio'),
                                    onProduct: () => Navigator.pop(context, 'product'),
                                  ),
                                  const SizedBox(height: 12),
                                ],
                              ],
                            ),
                          ),
                          if (_loading)
                            const SliverToBoxAdapter(
                              child: Padding(
                                padding: EdgeInsets.all(24),
                                child: Center(
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00A884)),
                                ),
                              ),
                            )
                          else
                            SliverPadding(
                              padding: EdgeInsets.fromLTRB(2, 0, 2, 72 + bottom),
                              sliver: SliverGrid(
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: _expanded ? 4 : 3,
                                  crossAxisSpacing: 2,
                                  mainAxisSpacing: 2,
                                ),
                                delegate: SliverChildBuilderDelegate(
                                  (context, i) {
                                    final asset = _assets[i];
                                    if (i == _assets.length - 8 && !_loadingMore) {
                                      WidgetsBinding.instance.addPostFrameCallback((_) => _loadPage());
                                    }
                                    return _RecentThumb(
                                      asset: asset,
                                      onTap: () => Navigator.pop(context, 'recent:${asset.id}'),
                                    );
                                  },
                                  childCount: _assets.length,
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (_expanded)
                        Positioned(
                          right: 16,
                          bottom: 16 + bottom,
                          child: Material(
                            color: Colors.white,
                            elevation: 4,
                            borderRadius: BorderRadius.circular(16),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () => Navigator.pop(context, 'document'),
                              child: const SizedBox(
                                width: 52,
                                height: 52,
                                child: Icon(Icons.folder_outlined, color: Color(0xFF54656F), size: 26),
                              ),
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
      ),
    );
  }
}

class _ExpandedHeader extends StatelessWidget {
  final String albumName;
  final VoidCallback onClose;
  final VoidCallback onAlbum;

  const _ExpandedHeader({
    required this.albumName,
    required this.onClose,
    required this.onAlbum,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 8, 10),
      child: Row(
        children: [
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close, color: Color(0xFF111B21), size: 24),
          ),
          Expanded(
            child: Center(
              child: InkWell(
                onTap: onAlbum,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        albumName,
                        style: const TextStyle(
                          color: Color(0xFF111B21),
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Icon(Icons.expand_more, color: Color(0xFF111B21), size: 22),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}

class _ActionsGrid extends StatelessWidget {
  final VoidCallback onGallery;
  final VoidCallback onCamera;
  final VoidCallback onDocument;
  final VoidCallback onAudio;
  final VoidCallback onProduct;

  const _ActionsGrid({
    required this.onGallery,
    required this.onCamera,
    required this.onDocument,
    required this.onAudio,
    required this.onProduct,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          Row(
            children: [
              _AttachAction(
                label: 'Gallery',
                bg: const Color(0xFFE8F0FE),
                color: const Color(0xFF1A73E8),
                icon: Icons.image_rounded,
                onTap: onGallery,
              ),
              _AttachAction(
                label: 'Camera',
                bg: const Color(0xFFFCE8EC),
                color: const Color(0xFFE91E63),
                icon: Icons.photo_camera_rounded,
                onTap: onCamera,
              ),
              _AttachAction(
                label: 'Location',
                bg: const Color(0xFFE6F4EA),
                color: const Color(0xFF1E8E3E),
                icon: Icons.location_on_rounded,
                onTap: () => Navigator.pop(context, 'location'),
              ),
              _AttachAction(
                label: 'Contact',
                bg: const Color(0xFFE8F0FE),
                color: const Color(0xFF1A73E8),
                icon: Icons.person_rounded,
                onTap: () => Navigator.pop(context, 'contact'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _AttachAction(
                label: 'Document',
                bg: const Color(0xFFF3E8FD),
                color: const Color(0xFF7B61C4),
                icon: Icons.description_rounded,
                onTap: onDocument,
              ),
              _AttachAction(
                label: 'Audio',
                bg: const Color(0xFFFFF3E0),
                color: const Color(0xFFF9A825),
                icon: Icons.headphones_rounded,
                onTap: onAudio,
              ),
              _AttachAction(
                label: 'Product',
                bg: const Color(0xFFE8F5E9),
                color: const Color(0xFF2E7D32),
                icon: Icons.inventory_2_rounded,
                onTap: onProduct,
              ),
              _AttachAction(
                label: 'Payment',
                bg: const Color(0xFFE0F2F1),
                color: const Color(0xFF00897B),
                icon: Icons.account_balance_wallet_rounded,
                onTap: () => Navigator.pop(context, 'payment'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AttachAction extends StatelessWidget {
  final String label;
  final Color bg;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  const _AttachAction({
    required this.label,
    required this.bg,
    required this.color,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(40),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF54656F),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentThumb extends StatelessWidget {
  final AssetEntity asset;
  final VoidCallback onTap;

  const _RecentThumb({required this.asset, required this.onTap});

  String _fmtDur(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = asset.type == AssetType.video;
    return FutureBuilder<Uint8List?>(
      future: asset.thumbnailDataWithSize(const ThumbnailSize(300, 300)),
      builder: (context, snap) {
        final bytes = snap.data;
        return GestureDetector(
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(
                color: const Color(0xFFF0F2F5),
                child: bytes == null ? const SizedBox.shrink() : Image.memory(bytes, fit: BoxFit.cover),
              ),
              if (isVideo)
                Positioned(
                  left: 6,
                  bottom: 6,
                  child: Row(
                    children: [
                      const Icon(Icons.videocam, color: Colors.white, size: 14),
                      const SizedBox(width: 3),
                      Text(
                        _fmtDur(asset.videoDuration),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          shadows: [Shadow(blurRadius: 3, color: Colors.black54)],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
