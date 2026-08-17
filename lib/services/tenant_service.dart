import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'shared_replay_stream.dart';

class TenantService {
  static final _profileStreams = <String, SharedReplayStream<DocumentSnapshot<Map<String, dynamic>>>>{};

  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  static const _inviteCodeValidity = Duration(hours: 48);

  /// HTTPS invite (opens web → app). Also works as deep path on hosting.
  static const inviteWebHost = 'crmsetup-fb6f6.web.app';

  /// Prefer https share link; app still accepts `watech://invite/<token>`.
  static String inviteLinkUrl(String token) => 'https://$inviteWebHost/invite/$token';

  static String inviteAppLinkUrl(String token) => 'watech://invite/$token';

  String _generateInviteCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no 0/O/1/I ambiguity
    final rand = Random.secure();
    return List.generate(7, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  String _generateInviteToken() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';
    final rand = Random.secure();
    return List.generate(24, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  Future<void> _writeInviteLink({
    required String tenantId,
    required String token,
    required DateTime expiresAt,
    String? oldToken,
  }) async {
    final uid = _auth.currentUser!.uid;
    await _firestore.collection('inviteLinks').doc(token).set({
      'tenantId': tenantId,
      'expiresAt': Timestamp.fromDate(expiresAt),
      'createdBy': uid,
    });
    await _firestore.collection('tenants').doc(tenantId).update({
      'inviteLinkToken': token,
      'inviteLinkExpiresAt': Timestamp.fromDate(expiresAt),
    });
    if (oldToken != null && oldToken.isNotEmpty && oldToken != token) {
      try {
        await _firestore.collection('inviteLinks').doc(oldToken).delete();
      } catch (_) {}
    }
  }

  /// Creates a new tenant, makes the current user its admin, and links the
  /// user's profile to it. Also writes invite code + invite link lookups.
  Future<String> createTenant(String businessName) async {
    final uid = _auth.currentUser!.uid;
    final tenantRef = _firestore.collection('tenants').doc();
    final inviteCode = _generateInviteCode();
    final inviteToken = _generateInviteToken();
    final expiresAt = DateTime.now().add(_inviteCodeValidity);

    await tenantRef.set({
      'businessName': businessName,
      'inviteCode': inviteCode,
      'inviteCodeExpiresAt': Timestamp.fromDate(expiresAt),
      'inviteLinkToken': inviteToken,
      'inviteLinkExpiresAt': Timestamp.fromDate(expiresAt),
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': uid,
      'planId': 'trial_7',
      'planStatus': 'active',
      'planExpiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(days: 7))),
      'planActivatedAt': FieldValue.serverTimestamp(),
    });

    final profile = await _firestore.collection('users').doc(uid).get();
    final profileData = profile.data() ?? {};
    await tenantRef.collection('members').doc(uid).set({
      'role': 'admin',
      'joinedAt': FieldValue.serverTimestamp(),
      'name': (profileData['name'] as String?)?.trim() ?? '',
      'email': (profileData['email'] as String?)?.trim() ?? (_auth.currentUser?.email ?? ''),
    });

    await _firestore.collection('inviteCodes').doc(inviteCode).set({
      'tenantId': tenantRef.id,
      'expiresAt': Timestamp.fromDate(expiresAt),
    });

    await _firestore.collection('inviteLinks').doc(inviteToken).set({
      'tenantId': tenantRef.id,
      'expiresAt': Timestamp.fromDate(expiresAt),
      'createdBy': uid,
    });

    await _firestore.collection('users').doc(uid).update({'tenantId': tenantRef.id});

    return tenantRef.id;
  }

  /// Ensures the tenant has a non-expired invite link token; creates one if needed.
  Future<String> ensureInviteLink(String tenantId) async {
    final snap = await _firestore.collection('tenants').doc(tenantId).get();
    final data = snap.data() ?? {};
    final existing = (data['inviteLinkToken'] as String?)?.trim() ?? '';
    final exp = data['inviteLinkExpiresAt'];
    if (existing.isNotEmpty && exp is Timestamp && DateTime.now().isBefore(exp.toDate())) {
      final linkDoc = await _firestore.collection('inviteLinks').doc(existing).get();
      if (linkDoc.exists) return existing;
    }
    final token = _generateInviteToken();
    final expiresAt = DateTime.now().add(_inviteCodeValidity);
    await _writeInviteLink(
      tenantId: tenantId,
      token: token,
      expiresAt: expiresAt,
      oldToken: existing.isEmpty ? null : existing,
    );
    return token;
  }

  /// Admin: rotate invite link.
  Future<String> regenerateInviteLink(String tenantId) async {
    final snap = await _firestore.collection('tenants').doc(tenantId).get();
    final oldToken = (snap.data()?['inviteLinkToken'] as String?) ?? '';
    final token = _generateInviteToken();
    final expiresAt = DateTime.now().add(_inviteCodeValidity);
    await _writeInviteLink(
      tenantId: tenantId,
      token: token,
      expiresAt: expiresAt,
      oldToken: oldToken,
    );
    return token;
  }

  /// Looks up a tenant by invite code and files a join request under it.
  /// The requester does NOT get access yet — an admin must approve first.
  Future<void> requestToJoin(String inviteCode) async {
    final uid = _auth.currentUser!.uid;
    final code = inviteCode.trim().toUpperCase();

    final codeDoc = await _firestore.collection('inviteCodes').doc(code).get();
    if (!codeDoc.exists) {
      throw Exception('That invite code is not valid.');
    }
    final data = codeDoc.data()!;
    final expiresAt = (data['expiresAt'] as Timestamp).toDate();
    if (DateTime.now().isAfter(expiresAt)) {
      throw Exception('That invite code has expired.');
    }
    final tenantId = data['tenantId'] as String;

    await _firestore
        .collection('tenants')
        .doc(tenantId)
        .collection('pendingRequests')
        .doc(uid)
        .set({
      'email': _auth.currentUser!.email,
      'status': 'pending',
      'requestedAt': FieldValue.serverTimestamp(),
    });

    await _firestore
        .collection('users')
        .doc(uid)
        .set({'pendingTenantId': tenantId}, SetOptions(merge: true));
  }

  /// Invite-link signup: join as agent immediately (no pending approval).
  Future<String> acceptInviteLink(String rawToken) async {
    final uid = _auth.currentUser!.uid;
    final token = rawToken.trim();
    if (token.isEmpty) throw Exception('Invite link is not valid.');

    final userSnap = await _firestore.collection('users').doc(uid).get();
    final existingTenant = userSnap.data()?['tenantId'] as String?;
    if (existingTenant != null && existingTenant.isNotEmpty) {
      throw Exception('You already belong to a team.');
    }

    final linkDoc = await _firestore.collection('inviteLinks').doc(token).get();
    if (!linkDoc.exists) {
      throw Exception('That invite link is not valid.');
    }
    final data = linkDoc.data()!;
    final expiresAt = (data['expiresAt'] as Timestamp).toDate();
    if (DateTime.now().isAfter(expiresAt)) {
      throw Exception('That invite link has expired.');
    }
    final tenantId = data['tenantId'] as String;

    // Prefer profile name/email from users doc when available.
    final profile = await _firestore.collection('users').doc(uid).get();
    final profileData = profile.data() ?? {};
    await _firestore.collection('tenants').doc(tenantId).collection('members').doc(uid).set({
      'role': 'agent',
      'joinedAt': FieldValue.serverTimestamp(),
      'inviteToken': token,
      'name': (profileData['name'] as String?)?.trim() ?? '',
      'email': (profileData['email'] as String?)?.trim() ?? (_auth.currentUser?.email ?? ''),
    });

    await _firestore.collection('users').doc(uid).set({
      'tenantId': tenantId,
      'pendingTenantId': FieldValue.delete(),
    }, SetOptions(merge: true));

    return tenantId;
  }

  Future<void> approveRequest(String tenantId, String requesterUid) async {
    final pending = await _firestore
        .collection('tenants')
        .doc(tenantId)
        .collection('pendingRequests')
        .doc(requesterUid)
        .get();
    final email = pending.data()?['email'] as String? ?? '';

    await _firestore
        .collection('tenants')
        .doc(tenantId)
        .collection('members')
        .doc(requesterUid)
        .set({
      'role': 'agent',
      'joinedAt': FieldValue.serverTimestamp(),
      'email': email,
      'name': '',
    });

    await _firestore
        .collection('tenants')
        .doc(tenantId)
        .collection('pendingRequests')
        .doc(requesterUid)
        .delete();
  }

  Future<void> rejectRequest(String tenantId, String requesterUid) {
    return _firestore
        .collection('tenants')
        .doc(tenantId)
        .collection('pendingRequests')
        .doc(requesterUid)
        .update({'status': 'rejected'});
  }

  Future<void> markApproved(String tenantId) async {
    final uid = _auth.currentUser!.uid;
    await _firestore.collection('users').doc(uid).set({
      'tenantId': tenantId,
      'pendingTenantId': FieldValue.delete(),
    }, SetOptions(merge: true));
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchMembers(String tenantId) {
    return _firestore.collection('tenants').doc(tenantId).collection('members').snapshots();
  }

  /// Admin removes an agent (or another admin except last admin — caller should check).
  Future<void> removeMember(String tenantId, String memberUid) async {
    final me = _auth.currentUser!.uid;
    if (memberUid == me) {
      throw Exception('You cannot remove yourself.');
    }

    final memberRef = _firestore.collection('tenants').doc(tenantId).collection('members').doc(memberUid);
    final memberSnap = await memberRef.get();
    if (!memberSnap.exists) return;

    if (memberSnap.data()?['role'] == 'admin') {
      final admins = await _firestore
          .collection('tenants')
          .doc(tenantId)
          .collection('members')
          .where('role', isEqualTo: 'admin')
          .get();
      if (admins.docs.length <= 1) {
        throw Exception('Cannot remove the last admin.');
      }
    }

    await memberRef.delete();
    await _firestore.collection('users').doc(memberUid).set({
      'tenantId': FieldValue.delete(),
      'pendingTenantId': FieldValue.delete(),
    }, SetOptions(merge: true));
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchUserProfile() {
    final uid = _auth.currentUser!.uid;
    final cached = _profileStreams.putIfAbsent(
      uid,
      () => SharedReplayStream(() => _firestore.collection('users').doc(uid).snapshots()),
    );
    return cached.stream;
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchMembership(String tenantId) {
    final uid = _auth.currentUser!.uid;
    return _firestore.collection('tenants').doc(tenantId).collection('members').doc(uid).snapshots();
  }

  /// Admin promotes/demotes a member. Cannot demote the last admin.
  Future<void> setMemberRole({
    required String tenantId,
    required String memberUid,
    required String role,
  }) async {
    if (role != 'admin' && role != 'agent') {
      throw Exception('Invalid role.');
    }

    final memberRef = _firestore.collection('tenants').doc(tenantId).collection('members').doc(memberUid);
    final memberSnap = await memberRef.get();
    if (!memberSnap.exists) {
      throw Exception('Member not found.');
    }

    final current = memberSnap.data()?['role'] as String? ?? 'agent';
    if (current == role) return;

    if (current == 'admin' && role == 'agent') {
      final admins = await _firestore
          .collection('tenants')
          .doc(tenantId)
          .collection('members')
          .where('role', isEqualTo: 'admin')
          .get();
      if (admins.docs.length <= 1) {
        throw Exception('Cannot demote the last admin.');
      }
    }

    await memberRef.update({'role': role});
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchPendingRequests(String tenantId) {
    return _firestore
        .collection('tenants')
        .doc(tenantId)
        .collection('pendingRequests')
        .where('status', isEqualTo: 'pending')
        .snapshots();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchTenant(String tenantId) {
    return _firestore.collection('tenants').doc(tenantId).snapshots();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchOwnPendingRequest(String tenantId) {
    final uid = _auth.currentUser!.uid;
    return _firestore.collection('tenants').doc(tenantId).collection('pendingRequests').doc(uid).snapshots();
  }

  Future<void> clearPendingRequest() async {
    final uid = _auth.currentUser!.uid;
    await _firestore.collection('users').doc(uid).update({'pendingTenantId': FieldValue.delete()});
  }
}
