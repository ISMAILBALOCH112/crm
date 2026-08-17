/// Holds invite token from deep link until signup completes.
class InviteSession {
  InviteSession._();

  static String? pendingToken;

  static void setToken(String? token) {
    final t = token?.trim();
    pendingToken = (t == null || t.isEmpty) ? null : t;
  }

  static String? peek() => pendingToken;

  static String? take() {
    final t = pendingToken;
    pendingToken = null;
    return t;
  }

  /// Extracts token from full link, URI, or raw token string.
  static String? extractToken(String? raw) {
    final s = raw?.trim() ?? '';
    if (s.isEmpty) return null;

    if (!s.contains('://') && !s.contains('/') && !s.contains(' ') && s.length >= 16) {
      return s;
    }

    final uri = Uri.tryParse(s);
    if (uri != null && uri.hasScheme) {
      final fromUri = parseUri(uri);
      if (fromUri != null) return fromUri;
    }

    final match = RegExp(r'(?:watech://invite/|invite/)([A-Za-z0-9]+)').firstMatch(s);
    if (match != null) return match.group(1);

    final qMatch = RegExp(r'[?&](?:token|invite)=([A-Za-z0-9]+)').firstMatch(s);
    if (qMatch != null) return qMatch.group(1);

    return null;
  }

  /// Parses `watech://invite/<token>`, `https://…/invite/<token>`, or query forms.
  static String? parseUri(Uri uri) {
    if (uri.scheme == 'watech') {
      if (uri.host == 'invite') {
        if (uri.pathSegments.isNotEmpty) {
          final last = uri.pathSegments.last;
          if (last.isNotEmpty) return last;
        }
        final q = uri.queryParameters['token'];
        if (q != null && q.trim().isNotEmpty) return q.trim();
      }
      if (uri.pathSegments.contains('invite')) {
        final i = uri.pathSegments.indexOf('invite');
        if (i + 1 < uri.pathSegments.length) return uri.pathSegments[i + 1];
      }
    }
    if (uri.pathSegments.length >= 2 && uri.pathSegments.contains('invite')) {
      final i = uri.pathSegments.indexOf('invite');
      if (i + 1 < uri.pathSegments.length) {
        final t = uri.pathSegments[i + 1];
        if (t.isNotEmpty && t != 'index.html') return t;
      }
    }
    final q = uri.queryParameters['invite'] ?? uri.queryParameters['token'];
    if (q != null && q.trim().isNotEmpty) return q.trim();
    return null;
  }
}
