import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/conversation_message.dart';

/// App-level in-memory cache of conversation messages (plain data, not snapshots).
class ConversationMessageCache {
  ConversationMessageCache._();

  static final Map<String, List<ConversationMessage>> _messages = {};
  static final Set<String> _snapshotReady = {};

  static String _key(String tenantId, String phone) => '$tenantId|$phone';

  /// True after at least one Firestore snapshot was applied for this chat.
  static bool isSnapshotReady(String tenantId, String phone) {
    return _snapshotReady.contains(_key(tenantId, phone));
  }

  /// Cached messages for immediate UI hydration, or null if never loaded.
  static List<ConversationMessage>? peek(String tenantId, String phone) {
    return _messages[_key(tenantId, phone)];
  }

  static void putFromSnapshot(String tenantId, String phone, QuerySnapshot<Map<String, dynamic>> snapshot) {
    final key = _key(tenantId, phone);
    _snapshotReady.add(key);
    _messages[key] = snapshot.docs
        .where((d) => d.data()['deleted'] != true)
        .map(
          (d) => ConversationMessage(
            id: d.id,
            data: Map<String, dynamic>.from(d.data()),
          ),
        )
        .toList();
  }
}
