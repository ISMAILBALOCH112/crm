import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// WhatsApp-style Click-to-WhatsApp ad card shown on inbound messages with referral metadata.
class ChatAdReferralCard extends StatelessWidget {
  final Map<String, dynamic> referral;

  const ChatAdReferralCard({super.key, required this.referral});

  String? get _headline => (referral['headline'] as String?)?.trim();
  String? get _sourceUrl => (referral['sourceUrl'] as String?)?.trim();
  String? get _mediaType => (referral['mediaType'] as String?)?.trim().toLowerCase();
  String? get _imageUrl {
    final image = (referral['imageUrl'] as String?)?.trim();
    if (image != null && image.isNotEmpty) return image;
    final thumb = (referral['thumbnailUrl'] as String?)?.trim();
    if (thumb != null && thumb.isNotEmpty) return thumb;
    return null;
  }

  bool get _isVideo => _mediaType == 'video' || (referral['videoUrl'] as String?)?.trim().isNotEmpty == true;

  String get _linkLabel {
    final url = _sourceUrl;
    if (url == null || url.isEmpty) return 'fb.me';
    try {
      final host = Uri.parse(url).host.toLowerCase();
      if (host.contains('fb.me')) return 'fb.me';
      return host;
    } catch (_) {
      return 'fb.me';
    }
  }

  Future<void> _openLink() async {
    final url = _sourceUrl;
    if (url == null || url.isEmpty) return;
    final uri = Uri.parse(url.startsWith('http') ? url : 'https://$url');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final headline = _headline;
    final imageUrl = _imageUrl;
    if (headline == null && imageUrl == null && (_sourceUrl == null || _sourceUrl!.isEmpty)) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE9EDEF)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (imageUrl != null)
            AspectRatio(
              aspectRatio: 1.05,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: const Color(0xFFF0F2F5),
                      alignment: Alignment.center,
                      child: Icon(
                        _isVideo ? Icons.videocam_outlined : Icons.image_outlined,
                        color: const Color(0xFF8696A0),
                        size: 40,
                      ),
                    ),
                  ),
                  if (_isVideo)
                    Center(
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white.withValues(alpha: 0.95), width: 2),
                        ),
                        child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 34),
                      ),
                    ),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1877F2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(Icons.facebook, color: Colors.white, size: 14),
                    ),
                  ),
                ],
              ),
            ),
          InkWell(
            onTap: _openLink,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      _linkLabel,
                      style: const TextStyle(
                        color: Color(0xFF667781),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (headline != null && headline.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        headline,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          color: Color(0xFF111B21),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                        ),
                      ),
                    ),
                  ],
                  if (_sourceUrl != null && _sourceUrl!.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.link, size: 16, color: Color(0xFF8696A0)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
