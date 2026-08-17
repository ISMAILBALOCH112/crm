import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:photo_manager/photo_manager.dart';

/// WhatsApp-style in-chat camera UI.
class ChatCameraScreen extends StatefulWidget {
  const ChatCameraScreen({super.key});

  @override
  State<ChatCameraScreen> createState() => _ChatCameraScreenState();
}

class _ChatCameraScreenState extends State<ChatCameraScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _cameraIndex = 0;
  bool _flashOff = true;
  bool _busy = false;
  List<AssetEntity> _recentMedia = [];

  bool get _isFrontCamera =>
      _cameras.isNotEmpty && _cameras[_cameraIndex].lensDirection == CameraLensDirection.front;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
    _initCamera();
    _loadRecentMedia();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _controller?.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed && _cameras.isNotEmpty) {
      _startController(_cameraIndex);
      _loadRecentMedia();
    }
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) return;
      _cameraIndex = _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
      if (_cameraIndex < 0) _cameraIndex = 0;
      await _startController(_cameraIndex);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open camera. Check permission and try again.')),
        );
      }
    }
  }

  Future<void> _startController(int index) async {
    final old = _controller;
    _controller = null;
    if (old != null) await old.dispose();

    final isFront = _cameras[index].lensDirection == CameraLensDirection.front;
    final controller = CameraController(
      _cameras[index],
      isFront ? ResolutionPreset.medium : ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    await controller.initialize();
    if (!mounted) {
      await controller.dispose();
      return;
    }
    if (!isFront) {
      await controller.setFlashMode(_flashOff ? FlashMode.off : FlashMode.auto);
    }
    setState(() => _controller = controller);
  }

  Future<void> _loadRecentMedia() async {
    final state = await PhotoManager.requestPermissionExtend(
      requestOption: const PermissionRequestOption(
        androidPermission: AndroidPermission(
          type: RequestType.common,
          mediaLocation: false,
        ),
      ),
    );
    if (!state.hasAccess && !state.isLimited) return;

    final filter = FilterOptionGroup(
      orders: [const OrderOption(type: OrderOptionType.createDate, asc: false)],
    );
    final paths = await PhotoManager.getAssetPathList(
      onlyAll: true,
      type: RequestType.common,
      filterOption: filter,
    );
    if (paths.isEmpty) return;

    final assets = await paths.first.getAssetListPaged(page: 0, size: 20);
    if (!mounted) return;
    setState(() => _recentMedia = assets);
  }

  Future<void> _flipCamera() async {
    if (_cameras.length < 2 || _busy) return;
    setState(() => _busy = true);
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    await _startController(_cameraIndex);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _toggleFlash() async {
    if (_controller == null || _isFrontCamera) return;
    setState(() => _flashOff = !_flashOff);
    await _controller!.setFlashMode(_flashOff ? FlashMode.off : FlashMode.auto);
  }

  Future<void> _capturePhoto() async {
    if (_controller == null || !_controller!.value.isInitialized || _busy) return;

    setState(() => _busy = true);
    try {
      final photo = await _controller!.takePicture();
      if (!mounted) return;
      Navigator.of(context).pop(XFile(photo.path));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not capture photo.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openGallery() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (file != null && mounted) Navigator.of(context).pop(file);
  }

  Future<void> _pickRecent(AssetEntity asset) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final file = await asset.file;
      if (file != null && mounted) Navigator.of(context).pop(XFile(file.path));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _buildCameraPreview(CameraController controller) {
    return LayoutBuilder(
      builder: (context, constraints) {
        var previewSize = controller.value.previewSize;
        if (previewSize == null) return const SizedBox.shrink();

        final isPortrait = MediaQuery.orientationOf(context) == Orientation.portrait;
        if (isPortrait) {
          previewSize = Size(previewSize.height, previewSize.width);
        }

        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.center,
            maxWidth: constraints.maxWidth,
            maxHeight: constraints.maxHeight,
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: previewSize.width,
                height: previewSize.height,
                child: CameraPreview(controller),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final previewReady = controller != null && controller.value.isInitialized;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final topInset = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (previewReady)
            _buildCameraPreview(controller)
          else
            const Center(child: CircularProgressIndicator(color: Colors.white54)),

          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 300 + bottomInset,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.25),
                    Colors.black.withValues(alpha: 0.65),
                  ],
                  stops: const [0.0, 0.35, 1.0],
                ),
              ),
            ),
          ),

          Positioned(
            top: topInset + 10,
            left: 16,
            child: _TopBarButton(
              icon: Icons.close,
              iconSize: 26,
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
          if (!_isFrontCamera)
            Positioned(
              top: topInset + 10,
              right: 16,
              child: _TopBarButton(
                icon: _flashOff ? Icons.flash_off : Icons.flash_auto,
                iconSize: 24,
                onTap: _toggleFlash,
              ),
            ),

          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.only(bottom: bottomInset + 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  _RecentStrip(photos: _recentMedia, onPick: _pickRecent),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 84,
                    child: Row(
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 28),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: _SideControlButton(icon: Icons.photo_outlined, onTap: _openGallery),
                            ),
                          ),
                        ),
                        _ShutterButton(onTap: _capturePhoto, busy: _busy),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 28),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                _SideControlButton(icon: Icons.flip_camera_ios_outlined, onTap: _flipCamera),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBarButton extends StatelessWidget {
  final IconData icon;
  final double iconSize;
  final VoidCallback onTap;

  const _TopBarButton({required this.icon, required this.iconSize, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.35),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(icon, color: Colors.white, size: iconSize),
        ),
      ),
    );
  }
}

class _SideControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _SideControlButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.42),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

class _ShutterButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool busy;

  const _ShutterButton({required this.onTap, required this.busy});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: Container(
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3.5),
        ),
        alignment: Alignment.center,
        child: Container(
          width: 62,
          height: 62,
          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          child: busy
              ? const Padding(
                  padding: EdgeInsets.all(18),
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black45),
                )
              : null,
        ),
      ),
    );
  }
}

class _RecentStrip extends StatelessWidget {
  final List<AssetEntity> photos;
  final ValueChanged<AssetEntity> onPick;

  const _RecentStrip({required this.photos, required this.onPick});

  @override
  Widget build(BuildContext context) {
    if (photos.isEmpty) return const SizedBox(height: 74);

    return SizedBox(
      height: 74,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: photos.length,
        separatorBuilder: (_, _) => const SizedBox(width: 4),
        itemBuilder: (context, index) {
          final asset = photos[index];
          return _MediaThumb(asset: asset, onTap: () => onPick(asset));
        },
      ),
    );
  }
}

class _MediaThumb extends StatefulWidget {
  final AssetEntity asset;
  final VoidCallback onTap;

  const _MediaThumb({required this.asset, required this.onTap});

  @override
  State<_MediaThumb> createState() => _MediaThumbState();
}

class _MediaThumbState extends State<_MediaThumb> {
  Uint8List? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await widget.asset.thumbnailDataWithSize(const ThumbnailSize(200, 280));
    if (mounted && data != null) setState(() => _data = data);
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.asset.type == AssetType.video;

    return GestureDetector(
      onTap: widget.onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: SizedBox(
          width: 56,
          height: 74,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _data == null
                  ? Container(color: const Color(0xFF2A2A2A))
                  : Image.memory(_data!, fit: BoxFit.cover),
              if (isVideo)
                Positioned(
                  left: 4,
                  bottom: 4,
                  child: Icon(Icons.videocam, color: Colors.white.withValues(alpha: 0.92), size: 15),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
