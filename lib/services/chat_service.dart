import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../config/backend_config.dart';

class ChatService {
  final _firestore = FirebaseFirestore.instance;

  Stream<QuerySnapshot<Map<String, dynamic>>> watchContacts(String tenantId) {
    return _firestore
        .collection('tenants')
        .doc(tenantId)
        .collection('contacts')
        .orderBy('lastMessageAt', descending: true)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchMessages(String tenantId, String phone) {
    return _firestore
        .collection('tenants')
        .doc(tenantId)
        .collection('contacts')
        .doc(phone)
        .collection('messages')
        .orderBy('timestamp')
        .snapshots();
  }

  /// Sends via the backend (which actually calls the WhatsApp Cloud API and
  /// writes the resulting message to Firestore) rather than writing to
  /// Firestore directly — the client has no way to make a message really
  /// leave WhatsApp, so it must never fake that locally.
  Future<void> sendMessage({required String tenantId, required String to, required String text}) async {
    final idToken = await FirebaseAuth.instance.currentUser!.getIdToken();

    final response = await http.post(
      Uri.parse('$backendBaseUrl/tenants/$tenantId/send'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $idToken'},
      body: jsonEncode({'to': to, 'text': text}),
    );

    if (response.statusCode != 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(data['error']?.toString() ?? 'Could not send message.');
    }
  }
}
