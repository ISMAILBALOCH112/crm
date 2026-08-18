import 'dart:async';

/// One Firestore listener shared by many [StreamBuilder]s.
///
/// Re-subscribes when the last UI listener goes away (tab dispose), and
/// immediately replays the last snapshot to a new listener so the inbox
/// does not flash empty.
class SharedReplayStream<T> {
  SharedReplayStream(this._create);

  final Stream<T> Function() _create;
  StreamController<T>? _controller;
  StreamSubscription<T>? _sub;
  int _listeners = 0;
  T? _latest;
  bool _hasLatest = false;

  T? get peekLatest => _hasLatest ? _latest : null;

  Stream<T> get stream {
    _controller ??= StreamController<T>.broadcast(
      onListen: _onListen,
      onCancel: _onCancel,
    );
    return _controller!.stream;
  }

  void _onListen() {
    _listeners++;
    if (_sub == null) {
      _sub = _create().listen(
        (event) {
          _latest = event;
          _hasLatest = true;
          _controller?.add(event);
        },
        onError: (Object e, StackTrace st) => _controller?.addError(e, st),
      );
    } else if (_hasLatest) {
      _controller?.add(_latest as T);
    }
  }

  void _onCancel() {
    _listeners--;
    if (_listeners > 0) return;
    _sub?.cancel();
    _sub = null;
    _listeners = 0;
  }
}
