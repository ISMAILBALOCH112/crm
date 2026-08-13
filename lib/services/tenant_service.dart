import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class TenantService {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  static const _inviteCodeValidity = Duration(hours: 48);

  String _generateInviteCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no 0/O/1/I ambiguity
    final rand = Random.secure();
    return List.generate(7, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  /// Creates a new tenant, makes the current user its admin, and links the
  /// user's profile to it. Also writes an inviteCodes/{code} lookup doc so
  /// requestToJoin can find the tenant before the joiner has membership.
  Future<String> createTenant(String businessName) async {
    final uid = _auth.currentUser!.uid;
    final tenantRef = _firestore.collection('tenants').doc();
    final inviteCode = _generateInviteCode();
    final expiresAt = DateTime.now().add(_inviteCodeValidity);

    await tenantRef.set({
      'businessName': businessName,
      'inviteCode': inviteCode,
      'inviteCodeExpiresAt': Timestamp.fromDate(expiresAt),
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': uid,
    });

    await tenantRef.collection('members').doc(uid).set({
      'role': 'admin',
      'joinedAt': FieldValue.serverTimestamp(),
    });

    await _firestore.collection('inviteCodes').doc(inviteCode).set({
      'tenantId': tenantRef.id,
      'expiresAt': Timestamp.fromDate(expiresAt),
    });

    await _firestore.collection('users').doc(uid).update({'tenantId': tenantRef.id});

    return tenantRef.id;
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

  /// Admin action: grants the requester real membership and clears their
  /// pending request.
  Future<void> approveRequest(String tenantId, String requesterUid) async {
    await _firestore
        .collection('tenants')
        .doc(tenantId)
        .collection('members')
        .doc(requesterUid)
        .set({'role': 'agent', 'joinedAt': FieldValue.serverTimestamp()});

    await _firestore
        .collection('tenants')
        .doc(tenantId)
        .collection('pendingRequests')
        .doc(requesterUid)
        .delete();
  }

  /// Admin action: dismisses a join request without granting access. The
  /// doc is kept (marked 'rejected') rather than deleted so the requester's
  /// own pending screen can show a clear declined message instead of just
  /// looking stuck.
  Future<void> rejectRequest(String tenantId, String requesterUid) {
    return _firestore
        .collection('tenants')
        .doc(tenantId)
        .collection('pendingRequests')
        .doc(requesterUid)
        .update({'status': 'rejected'});
  }

  /// Admin action: invalidates the current invite code immediately and
  /// issues a fresh one, in case the old one leaked.
  Future<void> regenerateInviteCode(String tenantId, String oldCode) async {
    final newCode = _generateInviteCode();
    final expiresAt = DateTime.now().add(_inviteCodeValidity);

    await _firestore.collection('inviteCodes').doc(newCode).set({
      'tenantId': tenantId,
      'expiresAt': Timestamp.fromDate(expiresAt),
    });

    await _firestore.collection('tenants').doc(tenantId).update({
      'inviteCode': newCode,
      'inviteCodeExpiresAt': Timestamp.fromDate(expiresAt),
    });

    await _firestore.collection('inviteCodes').doc(oldCode).delete();
  }

  /// Called once a pending requester's membership doc appears, to record
  /// the approval on their own profile so future app loads skip straight
  /// to Home instead of re-checking the pending path.
  Future<void> markApproved(String tenantId) async {
    final uid = _auth.currentUser!.uid;
    await _firestore.collection('users').doc(uid).set({
      'tenantId': tenantId,
      'pendingTenantId': FieldValue.delete(),
    }, SetOptions(merge: true));
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchUserProfile() {
    final uid = _auth.currentUser!.uid;
    return _firestore.collection('users').doc(uid).snapshots();
  }

  /// Streams the current user's own membership doc under a tenant — used
  /// both to check "am I approved yet" and, once approved, their role.
  Stream<DocumentSnapshot<Map<String, dynamic>>> watchMembership(String tenantId) {
    final uid = _auth.currentUser!.uid;
    return _firestore.collection('tenants').doc(tenantId).collection('members').doc(uid).snapshots();
  }

  /// Only the still-open requests — rejected ones are kept (not deleted)
  /// so the requester can see the decision, but shouldn't clutter this list.
  /// Not ordered: a status filter plus an orderBy on a different field would
  /// need a composite index, which isn't worth it for a short admin list.
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

  /// Streams the current user's own pending-request doc under a tenant, so
  /// they can see whether it's still pending or was rejected.
  Stream<DocumentSnapshot<Map<String, dynamic>>> watchOwnPendingRequest(String tenantId) {
    final uid = _auth.currentUser!.uid;
    return _firestore.collection('tenants').doc(tenantId).collection('pendingRequests').doc(uid).snapshots();
  }

  /// Clears a rejected (or abandoned) request so the user falls back to
  /// the business setup screen and can try a different code.
  Future<void> clearPendingRequest() async {
    final uid = _auth.currentUser!.uid;
    await _firestore.collection('users').doc(uid).update({'pendingTenantId': FieldValue.delete()});
  }
}
