import 'dart:async';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:record/record.dart';

/// WhatsApp-style tap-to-record panel (recording + paused review).
class VoiceRecordPanel extends StatefulWidget {
  final AudioRecorder recorder;
  final String filePath;
  final VoidCallback onDelete;
  final Future<void> Function(int durationMs) onSend;

  const VoiceRecordPanel({
    super.key,
    required this.recorder,
    required this.filePath,
    required this.onDelete,
    required this.onSend,
  });

  @override
  State<VoiceRecordPanel> createState() => _VoiceRecordPanelState();
}

class _VoiceRecordPanelState extends State<VoiceRecordPanel> {
  final _player = AudioPlayer();
  final _bars = <double>[];
  StreamSubscription<Amplitude>? _ampSub;
  Timer? _tick;
  Duration _pausedAccum = Duration.zero;
  DateTime? _segmentStart;
  bool _paused = false;
  bool _previewPlaying = false;
  bool _sending = false;
  Duration _previewPos = Duration.zero;
  Duration _previewDur = Duration.zero;

  @override
  void initState() {
    super.initState();
    _segmentStart = DateTime.now();
    _tick = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!_paused && mounted) setState(() {});
    });
    _ampSub = widget.recorder.onAmplitudeChanged(const Duration(milliseconds: 80)).listen((amp) {
      if (!mounted || _paused) return;
      // dBFS is typically -160..0; map to 0..1
      final level = ((amp.current + 45) / 45).clamp(0.05, 1.0);
      setState(() {
        _bars.add(level);
        if (_bars.length > 72) _bars.removeAt(0);
      });
    });
    _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _previewPos = p);
    });
    _player.onDurationChanged.listen((d) {
      if (mounted && d.inMilliseconds > 0) setState(() => _previewDur = d);
    });
    _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _previewPlaying = false;
          _previewPos = Duration.zero;
        });
      }
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _ampSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Duration get _totalElapsed {
    var t = _pausedAccum;
    if (!_paused && _segmentStart != null) {
      t += DateTime.now().difference(_segmentStart!);
    }
    return t;
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _pause() async {
    if (_paused) return;
    _pausedAccum = _totalElapsed;
    _segmentStart = null;
    await widget.recorder.pause();
    await _player.stop();
    if (!mounted) return;
    setState(() {
      _paused = true;
      _previewPlaying = false;
      _previewPos = Duration.zero;
      _previewDur = _pausedAccum;
    });
  }

  Future<void> _resume() async {
    if (!_paused) return;
    await _player.stop();
    await widget.recorder.resume();
    if (!mounted) return;
    setState(() {
      _paused = false;
      _previewPlaying = false;
      _previewPos = Duration.zero;
      _segmentStart = DateTime.now();
    });
  }

  Future<void> _togglePreview() async {
    if (!_paused || _sending) return;
    if (_previewPlaying) {
      await _player.pause();
      setState(() => _previewPlaying = false);
      return;
    }
    try {
      if (_player.state == PlayerState.paused) {
        await _player.resume();
      } else {
        await _player.play(DeviceFileSource(widget.filePath));
      }
      if (mounted) setState(() => _previewPlaying = true);
    } catch (_) {}
  }

  Future<void> _send() async {
    if (_sending) return;
    setState(() => _sending = true);
    await _player.stop();
    final durationMs = _totalElapsed.inMilliseconds;
    try {
      // Ensure file is finalized.
      if (await widget.recorder.isRecording() || await widget.recorder.isPaused()) {
        await widget.recorder.stop();
      }
    } catch (_) {}
    await widget.onSend(durationMs <= 0 ? 500 : durationMs);
  }

  Future<void> _delete() async {
    await _player.stop();
    try {
      await widget.recorder.cancel();
    } catch (_) {
      try {
        await widget.recorder.stop();
      } catch (_) {}
    }
    widget.onDelete();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = _paused
        ? (_previewPlaying && _previewDur > Duration.zero ? _previewPos : _pausedAccum)
        : _totalElapsed;
    final progress = (!_paused || _previewDur.inMilliseconds <= 0)
        ? 0.0
        : (_previewPos.inMilliseconds / _previewDur.inMilliseconds).clamp(0.0, 1.0);

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                if (_paused)
                  GestureDetector(
                    onTap: _togglePreview,
                    child: Icon(
                      _previewPlaying ? Icons.pause : Icons.play_arrow,
                      size: 28,
                      color: const Color(0xFF111B21),
                    ),
                  )
                else
                  Text(
                    _fmt(elapsed),
                    style: const TextStyle(
                      color: Color(0xFF111B21),
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 28,
                    child: CustomPaint(
                      painter: _LiveWavePainter(
                        bars: _bars.isEmpty ? _seedBars() : List.of(_bars),
                        progress: _paused ? progress : 1.0,
                        showThumb: _paused,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (_paused)
                  Text(
                    _fmt(_pausedAccum),
                    style: const TextStyle(
                      color: Color(0xFF111B21),
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  )
                else
                  const SizedBox(width: 4),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _RoundAction(
                  bg: const Color(0xFFFFE5E8),
                  onTap: _sending ? null : _delete,
                  child: const Icon(Icons.delete_outline_rounded, color: Color(0xFFE53935), size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _paused
                      ? _PillButton(
                          bg: const Color(0xFFE7F8EF),
                          onTap: _sending ? null : _resume,
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.mic_rounded, color: Color(0xFF008069), size: 22),
                              SizedBox(width: 8),
                              Text(
                                'Resume',
                                style: TextStyle(
                                  color: Color(0xFF008069),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        )
                      : _PillButton(
                          bg: const Color(0xFFF0F2F5),
                          onTap: _sending ? null : _pause,
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.pause, color: Color(0xFF111B21), size: 22),
                              SizedBox(width: 8),
                              Text(
                                'Pause',
                                style: TextStyle(
                                  color: Color(0xFF111B21),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                _RoundAction(
                  bg: const Color(0xFF00A884),
                  onTap: _sending ? null : _send,
                  child: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.send_rounded, color: Colors.white, size: 22),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<double> _seedBars() {
    final r = Random(7);
    return List.generate(40, (_) => 0.15 + r.nextDouble() * 0.35);
  }
}

class _RoundAction extends StatelessWidget {
  final Color bg;
  final VoidCallback? onTap;
  final Widget child;

  const _RoundAction({required this.bg, required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: bg,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(width: 48, height: 48, child: Center(child: child)),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  final Color bg;
  final VoidCallback? onTap;
  final Widget child;

  const _PillButton({required this.bg, required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: SizedBox(height: 48, child: Center(child: child)),
      ),
    );
  }
}

class _LiveWavePainter extends CustomPainter {
  final List<double> bars;
  final double progress;
  final bool showThumb;

  _LiveWavePainter({required this.bars, required this.progress, required this.showThumb});

  @override
  void paint(Canvas canvas, Size size) {
    const gap = 1.1;
    const barW = 2.0;
    final played = Paint()..color = const Color(0xFF00A884);
    final rest = Paint()..color = const Color(0xFFAEB6BC);
    final midY = size.height / 2;
    var x = 0.0;
    var i = 0;
    while (x + barW <= size.width) {
      final amp = bars.isEmpty ? 0.2 : bars[i % bars.length];
      final h = (3.0 + amp * (size.height - 4)).clamp(3.0, size.height);
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(x + barW / 2, midY), width: barW, height: h),
        const Radius.circular(1),
      );
      final through = !showThumb || ((x + barW / 2) / size.width <= progress);
      canvas.drawRRect(rect, (showThumb && through) ? played : rest);
      x += barW + gap;
      i++;
    }
    if (showThumb) {
      final thumbX = (size.width * progress).clamp(5.0, size.width - 5);
      canvas.drawCircle(Offset(thumbX, midY), 5.5, Paint()..color = const Color(0xFF00A884));
    }
  }

  @override
  bool shouldRepaint(covariant _LiveWavePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.showThumb != showThumb ||
      oldDelegate.bars.length != bars.length ||
      (bars.isNotEmpty && oldDelegate.bars.isNotEmpty && oldDelegate.bars.last != bars.last);
}

/// WhatsApp hold-to-record bar: slide left to cancel, slide up to lock.
class VoiceHoldBar extends StatelessWidget {
  final Duration elapsed;
  final double dragDx;
  final double dragDy;
  final bool willCancel;
  final bool willLock;

  const VoiceHoldBar({
    super.key,
    required this.elapsed,
    required this.dragDx,
    required this.dragDy,
    required this.willCancel,
    required this.willLock,
  });

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final slideX = dragDx.clamp(-120.0, 0.0);
    final lockLift = (-dragDy).clamp(0.0, 70.0);

    return SafeArea(
      top: false,
      child: SizedBox(
        height: 130,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Vertical lock rail above the mic.
            Positioned(
              right: 10,
              bottom: 58,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 80),
                width: 48,
                height: 96,
                transform: Matrix4.translationValues(0, -lockLift * 0.15, 0),
                decoration: BoxDecoration(
                  color: willLock ? const Color(0xFFE7F8EF) : Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: const [
                    BoxShadow(color: Color(0x22000000), blurRadius: 6, offset: Offset(0, 2)),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      willLock ? Icons.lock_rounded : Icons.lock_outline_rounded,
                      size: 22,
                      color: willLock ? const Color(0xFF008069) : const Color(0xFF54656F),
                    ),
                    const SizedBox(height: 10),
                    Icon(
                      Icons.keyboard_arrow_up_rounded,
                      size: 22,
                      color: willLock ? const Color(0xFF008069) : const Color(0xFF8696A0),
                    ),
                  ],
                ),
              ),
            ),
            // Main hold bar
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Transform.translate(
                      offset: Offset(slideX, 0),
                      child: Container(
                        height: 52,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: const [
                            BoxShadow(color: Color(0x1A000000), blurRadius: 4, offset: Offset(0, 1)),
                          ],
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.mic, color: Color(0xFFE53935), size: 22),
                            const SizedBox(width: 8),
                            Text(
                              _fmt(elapsed),
                              style: const TextStyle(
                                color: Color(0xFF111B21),
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                            const Spacer(),
                            Opacity(
                              opacity: willCancel ? 0.35 : 1,
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.chevron_left,
                                    size: 20,
                                    color: willCancel ? const Color(0xFFE53935) : const Color(0xFF8696A0),
                                  ),
                                  Text(
                                    willCancel ? 'Release to cancel' : 'Slide to cancel',
                                    style: TextStyle(
                                      color: willCancel ? const Color(0xFFE53935) : const Color(0xFF667781),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Transform.translate(
                    offset: Offset(slideX * 0.15, -lockLift),
                    child: Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: willCancel ? const Color(0xFFE53935) : const Color(0xFF00A884),
                        shape: BoxShape.circle,
                        boxShadow: const [
                          BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 3)),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        willCancel ? Icons.delete_outline_rounded : Icons.mic_rounded,
                        color: Colors.white,
                        size: 26,
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
