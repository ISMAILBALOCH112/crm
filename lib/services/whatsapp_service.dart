import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../config/backend_config.dart';

class WhatsappConnectResult {
  final String phoneNumber;
  final String webhookUrl;
  final String verifyToken;

  WhatsappConnectResult({required this.phoneNumber, required this.webhookUrl, required this.verifyToken});
}

class WhatsappService {
  /// Sends the tenant admin's own Meta credentials to the backend, which
  /// verifies them against the Graph API before storing them. Returns the
  /// webhook URL + verify token the admin still has to paste into their own
  /// Meta App Dashboard.
  Future<WhatsappConnectResult> connect({
    required String tenantId,
    required String phoneNumberId,
    required String accessToken,
    required String appSecret,
  }) async {
    final idToken = await FirebaseAuth.instance.currentUser!.getIdToken();

    final response = await http.post(
      Uri.parse('$backendBaseUrl/tenants/$tenantId/whatsapp/connect'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $idToken'},
      body: jsonEncode({
        'phoneNumberId': phoneNumberId,
        'accessToken': accessToken,
        'appSecret': appSecret,
      }),
    );

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw Exception(data['error'] as String? ?? 'Could not connect WhatsApp.');
    }

    return WhatsappConnectResult(
      phoneNumber: data['phoneNumber'] as String? ?? '',
      webhookUrl: data['webhookUrl'] as String,
      verifyToken: data['verifyToken'] as String,
    );
  }
}
