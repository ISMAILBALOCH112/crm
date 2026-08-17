import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../config/cloudinary_config.dart';

class MediaUploadService {
  /// Resize/compress before upload so Cloudinary + WhatsApp send feels instant.
  Future<Uint8List> compressForChat(Uint8List bytes) async {
    if (bytes.length < 280 * 1024) return bytes;
    try {
      final out = await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: 1280,
        minHeight: 1280,
        quality: 82,
        format: CompressFormat.jpeg,
      );
      if (out.isNotEmpty && out.length < bytes.length) return out;
    } catch (_) {}
    return bytes;
  }

  /// Uploads an image to Cloudinary (unsigned preset) and returns the HTTPS URL.
  Future<String> uploadImage(XFile file) async {
    final bytes = await file.readAsBytes();
    final name = file.name.trim().isEmpty ? 'image.jpg' : file.name;
    return uploadImageBytes(bytes, filename: name);
  }

  Future<String> uploadImageBytes(Uint8List bytes, {String filename = 'image.jpg'}) async {
    final compressed = await compressForChat(bytes);
    final name = filename.toLowerCase().endsWith('.jpg') || filename.toLowerCase().endsWith('.jpeg')
        ? filename
        : 'image.jpg';
    return _uploadBytes(compressed, filename: name, resourceType: 'image', folder: 'chat');
  }

  /// Stickers for WhatsApp must be WebP (ideally ~512px).
  Future<String> uploadSticker(XFile file) async {
    final url = await _uploadPath(file.path, resourceType: 'image', folder: 'chat/stickers');
    return cloudinaryWebpStickerUrl(url);
  }

  Future<String> uploadVideo(XFile file) async {
    return _uploadPath(file.path, resourceType: 'video', folder: 'chat');
  }

  Future<String> uploadAudio(String path) async {
    final lower = path.toLowerCase();
    final filename = lower.endsWith('.ogg')
        ? 'voice.ogg'
        : lower.endsWith('.opus')
            ? 'voice.ogg'
            : lower.endsWith('.m4a')
                ? 'voice.m4a'
                : lower.endsWith('.mp3')
                    ? 'voice.mp3'
                    : 'voice.m4a';
    // Raw keeps the real extension. "auto" remuxes AAC to video/mp4 and WhatsApp fails it.
    return _uploadPath(path, resourceType: 'raw', folder: 'chat', filename: filename);
  }

  Future<String> uploadRawFile(String path, {String folder = 'invoices'}) async {
    try {
      return await _uploadPath(path, resourceType: 'raw', folder: folder);
    } catch (_) {
      return _uploadPath(path, resourceType: 'auto', folder: folder);
    }
  }

  Future<String> _uploadBytes(
    List<int> bytes, {
    required String filename,
    required String resourceType,
    required String folder,
  }) async {
    final request = http.MultipartRequest('POST', Uri.parse(_uploadEndpoint(resourceType)))
      ..fields['upload_preset'] = cloudinaryUploadPreset
      ..fields['folder'] = folder
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    return _sendUpload(request);
  }

  Future<String> _uploadPath(
    String path, {
    required String resourceType,
    required String folder,
    String? filename,
  }) async {
    final request = http.MultipartRequest('POST', Uri.parse(_uploadEndpoint(resourceType)))
      ..fields['upload_preset'] = cloudinaryUploadPreset
      ..fields['folder'] = folder
      ..files.add(await http.MultipartFile.fromPath('file', path, filename: filename));
    return _sendUpload(request);
  }

  String _uploadEndpoint(String resourceType) {
    if (resourceType == 'video') {
      return 'https://api.cloudinary.com/v1_1/$cloudinaryCloudName/video/upload';
    }
    if (resourceType == 'auto') {
      return 'https://api.cloudinary.com/v1_1/$cloudinaryCloudName/auto/upload';
    }
    if (resourceType == 'raw') {
      return 'https://api.cloudinary.com/v1_1/$cloudinaryCloudName/raw/upload';
    }
    return 'https://api.cloudinary.com/v1_1/$cloudinaryCloudName/image/upload';
  }

  Future<String> _sendUpload(http.MultipartRequest request) async {

    final response = await request.send();
    final body = jsonDecode(await response.stream.bytesToString()) as Map<String, dynamic>;

    if (response.statusCode != 200) {
      throw Exception((body['error'] as Map<String, dynamic>?)?['message'] as String? ?? 'Upload failed.');
    }

    final url = body['secure_url'] as String?;
    if (url == null || url.isEmpty) throw Exception('Upload failed.');
    return url;
  }
}

/// Inserts Cloudinary delivery transforms so Meta gets a WebP sticker.
String cloudinaryWebpStickerUrl(String url) {
  const marker = '/upload/';
  final i = url.indexOf(marker);
  if (i < 0) return url;
  final head = url.substring(0, i + marker.length);
  final tail = url.substring(i + marker.length);
  if (tail.startsWith('f_webp')) return url;
  return '${head}f_webp,w_512,h_512,c_fit/$tail';
}
