import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

import '../config/emailjs_config.dart';

class OtpService {
  static const _emailJsEndpoint = 'https://api.emailjs.com/api/v1.0/email/send';

  static const _otpValidity = Duration(minutes: 5);

  final _firestore = FirebaseFirestore.instance;

  String _generateCode() {
    final rand = Random.secure();
    return (100000 + rand.nextInt(900000)).toString();
  }

  Future<void> sendSignupOtp(String email) async {
    final code = _generateCode();
    final expiresAt = DateTime.now().add(_otpValidity);

    await _firestore.collection('otp_verifications').doc(email).set({
      'code': code,
      'expiresAt': Timestamp.fromDate(expiresAt),
      'createdAt': FieldValue.serverTimestamp(),
    });

    final response = await http.post(
      Uri.parse(_emailJsEndpoint),
      headers: {'origin': 'http://localhost', 'Content-Type': 'application/json'},
      body: jsonEncode({
        'service_id': emailJsServiceId,
        'template_id': emailJsSignupTemplateId,
        'user_id': emailJsPublicKey,
        'template_params': {
          'to_email': email,
          'otp_code': code,
        },
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to send OTP email: ${response.body}');
    }
  }

  Future<bool> verifyOtp(String email, String enteredCode) async {
    final doc = await _firestore.collection('otp_verifications').doc(email).get();
    if (!doc.exists) return false;

    final data = doc.data()!;
    final storedCode = data['code'] as String;
    final expiresAt = (data['expiresAt'] as Timestamp).toDate();

    if (DateTime.now().isAfter(expiresAt)) return false;
    if (storedCode != enteredCode) return false;

    await _firestore.collection('otp_verifications').doc(email).delete();
    return true;
  }
}
