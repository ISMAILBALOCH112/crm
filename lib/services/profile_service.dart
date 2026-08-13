import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../config/cloudinary_config.dart';

class ProfileService {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  /// Uploads a picked photo to Cloudinary (free tier, unsigned preset) and
  /// records its URL on the current user's `users/{uid}` doc.
  Future<String> uploadProfilePhoto(XFile file) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('https://api.cloudinary.com/v1_1/$cloudinaryCloudName/image/upload'),
    )
      ..fields['upload_preset'] = cloudinaryUploadPreset
      ..files.add(await http.MultipartFile.fromPath('file', file.path));

    final response = await request.send();
    final body = jsonDecode(await response.stream.bytesToString()) as Map<String, dynamic>;

    if (response.statusCode != 200) {
      throw Exception((body['error'] as Map<String, dynamic>?)?['message'] as String? ?? 'Could not upload photo.');
    }

    final url = body['secure_url'] as String;
    await _firestore.collection('users').doc(_auth.currentUser!.uid).update({'photoUrl': url});
    return url;
  }
}
