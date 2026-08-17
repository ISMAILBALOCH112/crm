import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Registers FCM token on the signed-in user for inbound WhatsApp pushes.
class PushService {
  PushService._();
  static final instance = PushService._();

  final _messaging = FirebaseMessaging.instance;
  final _firestore = FirebaseFirestore.instance;

  Future<void> init() async {
    try {
      await _messaging.requestPermission(alert: true, badge: true, sound: true);
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
      final token = await _messaging.getToken();
      if (token != null) await saveToken(token);
      _messaging.onTokenRefresh.listen(saveToken);
    } catch (e) {
      debugPrint('PushService.init failed: $e');
    }
  }

  Future<void> saveToken(String token) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || token.isEmpty) return;
    await _firestore.collection('users').doc(uid).set({
      'fcmToken': token,
      'fcmUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // No-op: system tray shows notification when app is backgrounded.
}
