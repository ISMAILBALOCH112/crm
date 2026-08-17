/// Free-tier Cloudinary account used for profile photo uploads (no Firebase
/// Storage, which now requires the Blaze billing plan even on the free
/// quota). Uploads use an unsigned preset, so no secret key is needed here.
const String cloudinaryCloudName = 'vtdxdwve';
const String cloudinaryUploadPreset = 'frph1y9b';

/// Delivery URL Flutter can actually decode (HEIC/AVIF originals stay as-is
/// on Cloudinary, but Image.network/Image.file cannot paint them).
String cloudinaryDisplayImageUrl(String url) {
  if (url.isEmpty) return url;
  const imageMarker = '/image/upload/';
  final imageAt = url.indexOf(imageMarker);
  if (imageAt >= 0) {
    final rest = url.substring(imageAt + imageMarker.length);
    if (RegExp(r'(^|,)f_(jpg|png|webp|auto|gif)').hasMatch(rest)) return url;
    return '${url.substring(0, imageAt + imageMarker.length)}f_jpg,q_auto,c_limit,w_1280/$rest';
  }
  const rawMarker = '/raw/upload/';
  final rawAt = url.indexOf(rawMarker);
  if (rawAt >= 0 && url.contains('res.cloudinary.com')) {
    return '${url.substring(0, rawAt)}/image/upload/f_jpg,q_auto,c_limit,w_1280/${url.substring(rawAt + rawMarker.length)}';
  }
  return url;
}
