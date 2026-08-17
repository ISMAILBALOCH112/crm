import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../config/backend_config.dart';
import 'chat_media_cache.dart';
import 'media_upload_service.dart';
import 'shared_replay_stream.dart';

class ChatContact {
  final String phone;
  final String name;
  final DateTime? lastMessageAt;
  final DateTime? lastReadAt;
  final int unreadCount;
  final bool isFavorite;
  final bool isPinned;
  final bool isArchived;
  final bool isMuted;
  final bool isGroup;
  final String? lastMessageDirection;
  final String? lastMessageText;
  final List<String> tags;
  final String? city;
  final String? assigneeUid;
  final String? assigneeName;
  final DateTime? lastCustomerMessageAt;

  const ChatContact({
    required this.phone,
    required this.name,
    this.lastMessageAt,
    this.lastReadAt,
    this.unreadCount = 0,
    this.isFavorite = false,
    this.isPinned = false,
    this.isArchived = false,
    this.isMuted = false,
    this.isGroup = false,
    this.lastMessageDirection,
    this.lastMessageText,
    this.tags = const [],
    this.city,
    this.assigneeUid,
    this.assigneeName,
    this.lastCustomerMessageAt,
  });

  factory ChatContact.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    return ChatContact.fromData(doc.id, doc.data());
  }

  factory ChatContact.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> doc) {
    return ChatContact.fromData(doc.id, doc.data() ?? {});
  }

  factory ChatContact.fromData(String phone, Map<String, dynamic> data) {
    return ChatContact(
      phone: phone,
      name: data['name'] as String? ?? phone,
      lastMessageAt: (data['lastMessageAt'] as Timestamp?)?.toDate(),
      lastReadAt: (data['lastReadAt'] as Timestamp?)?.toDate(),
      unreadCount: (data['unreadCount'] as num?)?.toInt() ?? 0,
      isFavorite: data['isFavorite'] == true,
      isPinned: data['isPinned'] == true || data['isFavorite'] == true,
      isArchived: data['isArchived'] == true,
      isMuted: data['isMuted'] == true,
      isGroup: data['isGroup'] == true || phone.contains('@g.us'),
      lastMessageDirection: data['lastMessageDirection'] as String?,
      lastMessageText: data['lastMessageText'] as String?,
      tags: (data['tags'] as List<dynamic>? ?? []).map((e) => '$e').toList(),
      city: data['city'] as String?,
      assigneeUid: data['assigneeUid'] as String?,
      assigneeName: data['assigneeName'] as String?,
      lastCustomerMessageAt: (data['lastCustomerMessageAt'] as Timestamp?)?.toDate(),
    );
  }

  String get listPreview {
    final text = lastMessageText?.trim();
    if (text != null && text.isNotEmpty) {
      final prefix = lastMessageDirection == 'outbound' ? 'You: ' : '';
      if (text == 'Photo') return '${prefix}Photo';
      if (text == 'Video') return '${prefix}Video';
      if (text == 'Voice message') return '${prefix}Voice message';
      return '$prefix$text';
    }
    return phone;
  }

  bool get isUnread {
    if (unreadCount > 0) return true;
    if (lastMessageDirection == 'outbound') return false;
    if (lastReadAt != null && lastMessageAt != null) {
      return lastMessageAt!.isAfter(lastReadAt!);
    }
    return false;
  }
}

class ChatService {
  static const defaultInboxTags = ['VIP', 'Unpaid', 'Returning', 'Hot lead', 'New', 'COD Pending'];

  static final _contactsStreams = <String, SharedReplayStream<QuerySnapshot<Map<String, dynamic>>>>{};
  static final _messageStreams = <String, SharedReplayStream<QuerySnapshot<Map<String, dynamic>>>>{};
  static final _chatTagListStreams = <String, SharedReplayStream<List<String>>>{};

  final _firestore = FirebaseFirestore.instance;
  final _mediaUpload = MediaUploadService();

  DocumentReference<Map<String, dynamic>> _contactRef(String tenantId, String phone) {
    return _firestore.collection('tenants').doc(tenantId).collection('contacts').doc(phone);
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchContacts(String tenantId) {
    final cached = _contactsStreams.putIfAbsent(
      tenantId,
      () => SharedReplayStream(
        () => _firestore
            .collection('tenants')
            .doc(tenantId)
            .collection('contacts')
            .orderBy('lastMessageAt', descending: true)
            .snapshots(),
      ),
    );
    return cached.stream;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchMessages(String tenantId, String phone) {
    final key = '$tenantId|$phone';
    final cached = _messageStreams.putIfAbsent(
      key,
      () => SharedReplayStream(
        () => _firestore
            .collection('tenants')
            .doc(tenantId)
            .collection('contacts')
            .doc(phone)
            .collection('messages')
            .orderBy('timestamp', descending: true)
            .limit(80)
            .snapshots(),
      ),
    );
    return cached.stream;
  }

  /// Sends via the backend (which actually calls the WhatsApp Cloud API and
  /// writes the resulting message to Firestore) rather than writing to
  /// Firestore directly â€” the client has no way to make a message really
  /// leave WhatsApp, so it must never fake that locally.
  Future<void> sendMessage({
    required String tenantId,
    required String to,
    required String text,
    String? replyToMessageId,
  }) {
    final body = <String, dynamic>{'to': to, 'text': text};
    if (replyToMessageId != null && replyToMessageId.trim().isNotEmpty) {
      body['replyToMessageId'] = replyToMessageId.trim();
    }
    return _postSend(tenantId: tenantId, body: body);
  }

  Future<List<WaTemplate>> listWaTemplates(String tenantId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('You are not signed in.');
    final idToken = await user.getIdToken();
    late final http.Response response;
    try {
      response = await http.get(
        Uri.parse('$backendBaseUrl/tenants/$tenantId/wa-templates'),
        headers: {'Authorization': 'Bearer $idToken'},
      );
    } catch (_) {
      throw Exception('Could not reach the server.');
    }
    final data = _decodeMap(response.body);
    if (response.statusCode != 200) {
      throw Exception(data['error']?.toString() ?? 'Could not load templates.');
    }
    final list = data['templates'] as List<dynamic>? ?? [];
    return list.map((e) => WaTemplate.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<void> sendTemplate({
    required String tenantId,
    required String to,
    required String name,
    required String languageCode,
    List<Map<String, dynamic>>? components,
  }) {
    return _postSend(tenantId: tenantId, body: {
        'to': to,
        'template': {
          'name': name,
          'languageCode': languageCode,
          if (components != null && components.isNotEmpty) 'components': components,
        },
      },
    );
  }

  Map<String, dynamic> _decodeMap(String body) {
    try {
      final data = jsonDecode(body);
      if (data is Map<String, dynamic>) return data;
      if (data is Map) return Map<String, dynamic>.from(data);
    } catch (_) {}
    return {};
  }

  Future<String> uploadImageBytes(Uint8List bytes, {String filename = 'image.jpg'}) {
    return _mediaUpload.uploadImageBytes(bytes, filename: filename);
  }

  /// Uploads to Cloudinary then sends via WhatsApp through the backend.
  Future<String> sendImage({
    required String tenantId,
    required String to,
    required XFile file,
    String? caption,
    Uint8List? bytes,
  }) async {
    final data = bytes ?? await file.readAsBytes();
    final name = file.name.trim().isEmpty ? 'image.jpg' : file.name;
    final imageUrl = await _mediaUpload.uploadImageBytes(data, filename: name);
    await sendImageUrl(
      tenantId: tenantId,
      to: to,
      imageUrl: imageUrl,
      caption: caption,
      bytes: data,
    );
    return imageUrl;
  }

  Future<void> sendImageUrl({
    required String tenantId,
    required String to,
    required String imageUrl,
    String? caption,
    Uint8List? bytes,
  }) async {
    final body = <String, dynamic>{'to': to, 'imageUrl': imageUrl};
    if (caption != null && caption.trim().isNotEmpty) body['caption'] = caption.trim();
    await _postSend(tenantId: tenantId, body: body);
    if (bytes != null && bytes.isNotEmpty) {
      unawaited(_cacheSentImage(imageUrl, bytes));
    }
  }

  Future<void> _cacheSentImage(String imageUrl, Uint8List bytes) async {
    try {
      await ChatMediaCache.putBytes(imageUrl, bytes);
    } catch (_) {}
  }

  /// GIF â†’ MP4 upload, stored/shown as gif (WhatsApp receives looping video).
  Future<void> sendGif({
    required String tenantId,
    required String to,
    required XFile file,
  }) async {
    final gifUrl = await _mediaUpload.uploadVideo(file);
    await _postSend(tenantId: tenantId, body: {'to': to, 'gifUrl': gifUrl});
  }

  /// Sticker â†’ WebP, WhatsApp sticker message (not a photo).
  Future<void> sendSticker({
    required String tenantId,
    required String to,
    required XFile file,
  }) async {
    final stickerUrl = await _mediaUpload.uploadSticker(file);
    await _postSend(tenantId: tenantId, body: {'to': to, 'stickerUrl': stickerUrl});
  }

  Future<void> sendVideo({
    required String tenantId,
    required String to,
    required XFile file,
    String? caption,
  }) async {
    final videoUrl = await _mediaUpload.uploadVideo(file);
    final body = <String, dynamic>{'to': to, 'videoUrl': videoUrl};
    if (caption != null && caption.trim().isNotEmpty) body['caption'] = caption.trim();
    await _postSend(tenantId: tenantId, body: body);
  }

  Future<void> sendAudio({
    required String tenantId,
    required String to,
    required String path,
    bool voice = true,
    int? durationMs,
  }) async {
    final audioUrl = await _mediaUpload.uploadAudio(path);
    await _postSend(tenantId: tenantId, body: {
        'to': to,
        'audioUrl': audioUrl,
        'voice': voice,
        if (durationMs != null && durationMs > 0) 'durationMs': durationMs,
      },
    );
  }

  Future<void> sendDocumentFile({
    required String tenantId,
    required String to,
    required String path,
    required String filename,
    String? caption,
  }) async {
    final documentUrl = await _mediaUpload.uploadRawFile(path, folder: 'chat');
    await sendDocument(
      tenantId: tenantId,
      to: to,
      documentUrl: documentUrl,
      filename: filename,
      caption: caption,
    );
  }

  Future<void> sendDocument({
    required String tenantId,
    required String to,
    required String documentUrl,
    required String filename,
    String? caption,
  }) async {
    final body = <String, dynamic>{
      'to': to,
      'documentUrl': documentUrl,
      'filename': filename,
    };
    if (caption != null && caption.trim().isNotEmpty) body['caption'] = caption.trim();
    await _postSend(tenantId: tenantId, body: body);
  }

  /// Re-send an existing message payload to another WhatsApp number.
  Future<void> forwardMessageData({
    required String tenantId,
    required String to,
    required Map<String, dynamic> data,
  }) async {
    final type = (data['type'] as String?)?.trim() ?? 'text';
    final text = (data['text'] as String?)?.trim() ?? '';
    final caption = text.isNotEmpty ? text : null;
    final imageUrl = (data['imageUrl'] as String?)?.trim();
    final mediaUrl = (data['mediaUrl'] as String?)?.trim();
    final documentUrl = (data['documentUrl'] as String?)?.trim();
    final filename = (data['filename'] as String?)?.trim();

    if (type == 'image' && imageUrl != null && imageUrl.isNotEmpty) {
      await _postSend(tenantId: tenantId, body: {
          'to': to,
          'imageUrl': imageUrl,
          if (caption != null) 'caption': caption,
        },
      );
      return;
    }
    if (type == 'video' && mediaUrl != null && mediaUrl.isNotEmpty) {
      await _postSend(tenantId: tenantId, body: {
          'to': to,
          'videoUrl': mediaUrl,
          if (caption != null) 'caption': caption,
        },
      );
      return;
    }
    if (type == 'gif' && mediaUrl != null && mediaUrl.isNotEmpty) {
      await _postSend(tenantId: tenantId, body: {
          'to': to,
          'gifUrl': mediaUrl,
          if (caption != null) 'caption': caption,
        },
      );
      return;
    }
    if (type == 'sticker' && mediaUrl != null && mediaUrl.isNotEmpty) {
      await _postSend(tenantId: tenantId, body: {'to': to, 'stickerUrl': mediaUrl},
      );
      return;
    }
    if (type == 'audio' && mediaUrl != null && mediaUrl.isNotEmpty) {
      await _postSend(tenantId: tenantId, body: {
          'to': to,
          'audioUrl': mediaUrl,
          'voice': true,
          if (data['durationMs'] != null) 'durationMs': data['durationMs'],
        },
      );
      return;
    }
    if (type == 'document' && documentUrl != null && documentUrl.isNotEmpty) {
      await _postSend(tenantId: tenantId, body: {
          'to': to,
          'documentUrl': documentUrl,
          'filename': (filename != null && filename.isNotEmpty) ? filename : 'file',
          if (caption != null) 'caption': caption,
        },
      );
      return;
    }
    if (imageUrl != null && imageUrl.isNotEmpty) {
      await _postSend(tenantId: tenantId, body: {
          'to': to,
          'imageUrl': imageUrl,
          if (caption != null) 'caption': caption,
        },
      );
      return;
    }
    if (text.isEmpty) {
      throw Exception('This message cannot be forwarded.');
    }
    await sendMessage(tenantId: tenantId, to: to, text: text);
  }

  /// Share a catalog product: image+caption, plus interactive Order button when possible.
  Future<void> shareProduct({
    required String tenantId,
    required String to,
    required String name,
    required double price,
    String? description,
    String? sku,
    String? imageUrl,
  }) async {
    final buf = StringBuffer('🛍️ *$name*\n💰 PKR ${price.toStringAsFixed(0)}');
    final desc = description?.trim();
    if (desc != null && desc.isNotEmpty) buf.write('\n$desc');
    final code = sku?.trim();
    if (code != null && code.isNotEmpty) buf.write('\nSKU: $code');
    final text = buf.toString();
    final img = imageUrl?.trim();
    if (img != null && img.isNotEmpty) {
      await _postSend(
        tenantId: tenantId,
        body: {'to': to, 'imageUrl': img, 'caption': text},
      );
    } else {
      await sendMessage(tenantId: tenantId, to: to, text: text);
    }
    // Follow with reply buttons so customer can tap Order (Cloud API interactive).
    final btnId = (code != null && code.isNotEmpty) ? 'p:${code.length > 20 ? code.substring(0, 20) : code}' : 'p:order';
    try {
      await _postSend(
        tenantId: tenantId,
        body: {
          'to': to,
          'interactiveButtons': {
            'body': 'Order *$name*?\nPKR ${price.toStringAsFixed(0)}',
            'buttons': [
              {'id': btnId, 'title': 'Order now'},
              {'id': 'p:ask', 'title': 'Ask question'},
            ],
          },
        },
      );
    } catch (_) {
      // Image/text already sent — interactive is an enhancement.
    }
  }

  Future<Map<String, dynamic>> _postSend({required String tenantId, required Map<String, dynamic> body}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('You are not signed in.');

    final idToken = await user.getIdToken();
    final uri = Uri.parse('$backendBaseUrl/tenants/$tenantId/send');

    late final http.Response response;
    try {
      response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $idToken'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 45));
    } catch (_) {
      throw Exception('Could not reach the server. Check your internet or ask admin if the backend is running.');
    }

    Map<String, dynamic> data = {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) data = decoded;
      if (decoded is Map) data = Map<String, dynamic>.from(decoded);
    } catch (_) {}

    if (response.statusCode != 200) {
      var message = 'Could not send message.';
      final error = data['error'];
      if (error is String && error.isNotEmpty) {
        message = error;
      } else if (error is Map && error['message'] != null) {
        message = error['message'].toString();
      } else if (response.body.trim().isNotEmpty) {
        message = response.body.trim();
      }
      throw Exception(message);
    }
    return data;
  }

  Future<void> retryFailedMessage({
    required String tenantId,
    required Map<String, dynamic> retryPayload,
  }) async {
    final body = Map<String, dynamic>.from(retryPayload);
    body.remove('retryPayload');
    await _postSend(tenantId: tenantId, body: body);
  }

  Future<void> markRead({required String tenantId, required String phone}) async {
    final ref = _contactRef(tenantId, phone);
    final snap = await ref.get();
    if (!snap.exists) return;

    // Local unread clear immediately for snappy UI.
    await ref.set({
      'unreadCount': 0,
      'lastReadAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // Also tell Meta so the customer gets blue ticks.
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final idToken = await user.getIdToken();
      await http.post(
        Uri.parse('$backendBaseUrl/tenants/$tenantId/chats/$phone/read'),
        headers: {'Authorization': 'Bearer $idToken'},
      );
    } catch (_) {
      // Local read already applied.
    }
  }

  /// Saves display name after the first outbound message (contact already exists from backend).
  Future<void> rememberContactName({
    required String tenantId,
    required String phone,
    required String name,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == phone) return;
    final ref = _contactRef(tenantId, phone);
    final snap = await ref.get();
    if (!snap.exists) return;
    final existing = (snap.data()?['name'] as String?)?.trim() ?? '';
    if (existing.isNotEmpty && existing != phone) return;
    await ref.set({'name': trimmed}, SetOptions(merge: true));
  }

  Future<void> markAllRead(String tenantId) async {
    final snap = await _firestore.collection('tenants').doc(tenantId).collection('contacts').get();
    if (snap.docs.isEmpty) return;

    final batch = _firestore.batch();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {
        'unreadCount': 0,
        'lastReadAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  Future<void> setFavorite({required String tenantId, required String phone, required bool isFavorite}) {
    return _contactRef(tenantId, phone).set({
      'isFavorite': isFavorite,
      // Pin and favorite stay in sync for list float + Favorites filter.
      'isPinned': isFavorite,
    }, SetOptions(merge: true));
  }

  Future<void> setPinned({required String tenantId, required String phone, required bool isPinned}) {
    return _contactRef(tenantId, phone).set({
      'isPinned': isPinned,
      'isFavorite': isPinned,
    }, SetOptions(merge: true));
  }

  Future<void> setAssignee({
    required String tenantId,
    required String phone,
    String? assigneeUid,
    String? assigneeName,
  }) {
    return _contactRef(tenantId, phone).set({
      'assigneeUid': assigneeUid,
      'assigneeName': assigneeName,
    }, SetOptions(merge: true));
  }

  Future<void> setArchived({required String tenantId, required String phone, required bool isArchived}) {
    return _contactRef(tenantId, phone).set({'isArchived': isArchived}, SetOptions(merge: true));
  }

  Future<void> setMuted({required String tenantId, required String phone, required bool isMuted}) {
    return _contactRef(tenantId, phone).set({'isMuted': isMuted}, SetOptions(merge: true));
  }

  Future<void> sendLocation({
    required String tenantId,
    required String to,
    required double latitude,
    required double longitude,
    String? name,
    String? address,
  }) {
    return _postSend(
      tenantId: tenantId,
      body: {
        'to': to,
        'location': {
          'latitude': latitude,
          'longitude': longitude,
          if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
          if (address != null && address.trim().isNotEmpty) 'address': address.trim(),
        },
      },
    );
  }

  Future<void> sendContactCard({
    required String tenantId,
    required String to,
    required String formattedName,
    required String phone,
  }) {
    return _postSend(
      tenantId: tenantId,
      body: {
        'to': to,
        'contacts': [
          {
            'name': {'formatted_name': formattedName, 'first_name': formattedName},
            'phones': [
              {'phone': phone, 'type': 'CELL', 'wa_id': phone.replaceAll(RegExp(r'\D'), '')},
            ],
          },
        ],
      },
    );
  }

  Future<Map<String, dynamic>> fetchWhatsappProfile(String tenantId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('You are not signed in.');
    final idToken = await user.getIdToken();
    late final http.Response response;
    try {
      response = await http.get(
        Uri.parse('$backendBaseUrl/tenants/$tenantId/whatsapp/profile'),
        headers: {'Authorization': 'Bearer $idToken'},
      );
    } catch (_) {
      throw Exception('Could not reach the server.');
    }
    final data = _decodeMap(response.body);
    if (response.statusCode != 200) {
      throw Exception(data['error']?.toString() ?? 'Could not load profile.');
    }
    return data;
  }

  DocumentReference<Map<String, dynamic>> _messageRef(String tenantId, String phone, String messageId) {
    return _contactRef(tenantId, phone).collection('messages').doc(messageId);
  }

  Future<void> softDeleteMessages({
    required String tenantId,
    required String phone,
    required Iterable<String> messageIds,
  }) async {
    final batch = _firestore.batch();
    for (final id in messageIds) {
      batch.set(
        _messageRef(tenantId, phone, id),
        {'deleted': true, 'deletedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
    }
    await batch.commit();
  }

  Future<void> setMessageStarred({
    required String tenantId,
    required String phone,
    required String messageId,
    required bool starred,
  }) {
    return _messageRef(tenantId, phone, messageId).set({'starred': starred}, SetOptions(merge: true));
  }

  DocumentReference<Map<String, dynamic>> _quickRepliesRef(String tenantId) {
    return _firestore.collection('tenants').doc(tenantId).collection('settings').doc('quickReplies');
  }

  Stream<List<QuickReply>> watchQuickReplies(String tenantId) {
    return _quickRepliesRef(tenantId).snapshots().map((snap) {
      final items = snap.data()?['items'] as List<dynamic>? ?? [];
      return items
          .whereType<Map>()
          .map((e) => QuickReply.fromMap(Map<String, dynamic>.from(e)))
          .where((q) => q.text.trim().isNotEmpty)
          .toList();
    });
  }

  Future<void> saveQuickReplies(String tenantId, List<QuickReply> items) {
    return _quickRepliesRef(tenantId).set({
      'items': items.map((e) => e.toMap()).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchContact(String tenantId, String phone) {
    return _contactRef(tenantId, phone).snapshots();
  }

  DocumentReference<Map<String, dynamic>> _chatTagsRef(String tenantId) {
    return _firestore.collection('tenants').doc(tenantId).collection('settings').doc('chatTags');
  }

  Stream<List<String>> watchChatTagCatalog(String tenantId) {
    final cached = _chatTagListStreams.putIfAbsent(
      tenantId,
      () => SharedReplayStream(
        () => _chatTagsRef(tenantId).snapshots().map((snap) {
          final list = snap.data()?['names'] as List<dynamic>? ?? const [];
          return list.map((e) => '$e'.trim()).where((t) => t.isNotEmpty).toList();
        }),
      ),
    );
    return cached.stream;
  }

  Future<void> addChatTagToCatalog(String tenantId, String tag) {
    final cleaned = tag.trim();
    if (cleaned.isEmpty) return Future.value();
    return _chatTagsRef(tenantId).set({
      'names': FieldValue.arrayUnion([cleaned]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> addTagToContacts({
    required String tenantId,
    required List<String> phones,
    required String tag,
  }) async {
    final cleaned = tag.trim();
    if (cleaned.isEmpty || phones.isEmpty) return;
    await addChatTagToCatalog(tenantId, cleaned);
    for (final phone in phones) {
      await _contactRef(tenantId, phone).set({
        'tags': FieldValue.arrayUnion([cleaned]),
      }, SetOptions(merge: true));
    }
  }

  Future<void> updateContactProfile({
    required String tenantId,
    required String phone,
    String? name,
    List<String>? tags,
    String? city,
    String? notes,
  }) async {
    final data = <String, dynamic>{};
    List<String>? cleanedTags;
    if (name != null) data['name'] = name.trim();
    if (tags != null) {
      cleanedTags = tags.map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
      data['tags'] = cleanedTags;
    }
    if (city != null) data['city'] = city.trim().isEmpty ? null : city.trim();
    if (notes != null) data['notes'] = notes.trim().isEmpty ? null : notes.trim();
    if (data.isEmpty) return;
    await _contactRef(tenantId, phone).set(data, SetOptions(merge: true));
    if (cleanedTags != null && cleanedTags.isNotEmpty) {
      await _chatTagsRef(tenantId).set({
        'names': FieldValue.arrayUnion(cleanedTags),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  Future<void> ensureContact({required String tenantId, required String phone, String? name}) async {
    final ref = _contactRef(tenantId, phone);
    final snap = await ref.get();
    if (snap.exists) {
      final existingName = snap.data()?['name'] as String?;
      if (name != null && name.isNotEmpty && (existingName == null || existingName.isEmpty)) {
        await ref.update({'name': name});
      }
      return;
    }

    await ref.set({
      'name': (name != null && name.isNotEmpty) ? name : phone,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'unreadCount': 0,
      'isFavorite': false,
      'isArchived': false,
      'isGroup': false,
    });
  }
}

class QuickReply {
  final String id;
  final String shortcut;
  final String text;

  const QuickReply({
    required this.id,
    required this.shortcut,
    required this.text,
  });

  factory QuickReply.fromMap(Map<String, dynamic> map) {
    return QuickReply(
      id: map['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
      shortcut: map['shortcut'] as String? ?? '',
      text: map['text'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'shortcut': shortcut,
        'text': text,
      };
}

class WaTemplate {
  final String name;
  final String language;
  final String? category;
  final String bodyText;
  final int bodyVarCount;
  final int headerVarCount;
  final String? headerFormat;

  const WaTemplate({
    required this.name,
    required this.language,
    required this.bodyText,
    this.category,
    this.bodyVarCount = 0,
    this.headerVarCount = 0,
    this.headerFormat,
  });

  factory WaTemplate.fromJson(Map<String, dynamic> json) {
    return WaTemplate(
      name: json['name'] as String? ?? '',
      language: json['language'] as String? ?? 'en_US',
      category: json['category'] as String?,
      bodyText: json['bodyText'] as String? ?? '',
      bodyVarCount: (json['bodyVarCount'] as num?)?.toInt() ?? 0,
      headerVarCount: (json['headerVarCount'] as num?)?.toInt() ?? 0,
      headerFormat: json['headerFormat'] as String?,
    );
  }

  String get displayLabel => category == null || category!.isEmpty ? name : '$name · $category';
}

