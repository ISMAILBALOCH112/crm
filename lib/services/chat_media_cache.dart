import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Downloads chat image/video to app documents and reuses the local file.
class ChatMediaCache {
  ChatMediaCache._();

  static final Map<String, int> _sizeCache = {};
  static final Map<String, Future<File>> _inFlight = {};

  static String _fileName(String url) {
    var ext = '.bin';
    final uri = Uri.tryParse(url);
    if (uri != null && uri.pathSegments.isNotEmpty) {
      final seg = uri.pathSegments.last;
      final dot = seg.lastIndexOf('.');
      if (dot >= 0 && dot < seg.length - 1) {
        final e = seg.substring(dot).toLowerCase();
        if (RegExp(r'^\.[a-z0-9]{1,5}$').hasMatch(e)) ext = e;
      }
    }
    final key = url.hashCode.toUnsigned(32).toRadixString(16);
    return 'm_$key$ext';
  }

  static Future<Directory> _dir() async {
    final root = await getApplicationDocumentsDirectory();
    final d = Directory('${root.path}${Platform.pathSeparator}chat_media');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static Future<File> fileFor(String url) async {
    final d = await _dir();
    return File('${d.path}${Platform.pathSeparator}${_fileName(url)}');
  }

  /// Copies an already-local file (just sent from gallery) into the cache
  /// so the chat bubble can show it immediately.
  static Future<File> putLocal(String url, String path) async {
    final dest = await fileFor(url);
    if (await dest.exists() && await dest.length() > 0) return dest;
    await File(path).copy(dest.path);
    return dest;
  }

  /// Writes picker/network bytes into the cache. Prefer this over [putLocal]
  /// on Android — gallery paths are often `content://` and [File.copy] fails.
  static Future<File> putBytes(String url, List<int> bytes) async {
    final dest = await fileFor(url);
    if (await dest.exists() && await dest.length() > 0) return dest;
    await dest.writeAsBytes(bytes, flush: true);
    return dest;
  }

  static Future<File?> getIfCached(String url) async {
    if (url.isEmpty) return null;
    final f = await fileFor(url);
    if (await f.exists() && await f.length() > 0) return f;
    return null;
  }

  /// HEAD (or cached) remote content-length for download labels.
  static Future<int?> remoteBytes(String url) async {
    if (url.isEmpty) return null;
    final cached = _sizeCache[url];
    if (cached != null) return cached;
    try {
      final res = await http.head(Uri.parse(url)).timeout(const Duration(seconds: 6));
      final len = int.tryParse(res.headers['content-length'] ?? '');
      if (len != null && len > 0) {
        _sizeCache[url] = len;
        return len;
      }
    } catch (_) {}
    return null;
  }

  static Future<File> download(
    String url, {
    void Function(double? progress)? onProgress,
  }) {
    final existing = _inFlight[url];
    if (existing != null) return existing;

    final future = _download(url, onProgress: onProgress);
    _inFlight[url] = future;
    future.whenComplete(() => _inFlight.remove(url));
    return future;
  }

  static Future<File> _download(
    String url, {
    void Function(double? progress)? onProgress,
  }) async {
    final f = await fileFor(url);
    if (await f.exists() && await f.length() > 0) {
      onProgress?.call(1);
      return f;
    }

    final tmp = File('${f.path}.part');
    if (await tmp.exists()) {
      try {
        await tmp.delete();
      } catch (_) {}
    }

    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(url));
      final res = await client.send(req).timeout(const Duration(seconds: 90));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw HttpException('download failed (${res.statusCode})', uri: Uri.parse(url));
      }
      final total = res.contentLength;
      if (total != null && total > 0) _sizeCache[url] = total;

      final sink = tmp.openWrite();
      var received = 0;
      await for (final chunk in res.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total != null && total > 0) {
          onProgress?.call((received / total).clamp(0.0, 1.0));
        } else {
          onProgress?.call(null);
        }
      }
      await sink.close();
      if (await f.exists()) {
        try {
          await f.delete();
        } catch (_) {}
      }
      await tmp.rename(f.path);
      onProgress?.call(1);
      return f;
    } catch (e) {
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
      rethrow;
    } finally {
      client.close();
    }
  }
}
