import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../config/backend_config.dart';
import 'shared_replay_stream.dart';

class TenantBilling {
  final String? planId;
  final String planStatus;
  final DateTime? planExpiresAt;
  final bool writeAllowed;
  final String? planLockReason;

  const TenantBilling({
    required this.planId,
    required this.planStatus,
    required this.planExpiresAt,
    required this.writeAllowed,
    this.planLockReason,
  });

  factory TenantBilling.fromTenantData(Map<String, dynamic>? data) {
    final expires = (data?['planExpiresAt'] as Timestamp?)?.toDate();
    final active = expires == null || expires.isAfter(DateTime.now());
    return TenantBilling(
      planId: data?['planId'] as String?,
      planStatus: active ? 'active' : 'expired',
      planExpiresAt: expires,
      writeAllowed: active,
      planLockReason: data?['planLockReason'] as String?,
    );
  }

  bool get wasKeyRevoked => planLockReason == 'key_revoked';
  bool get wasKeyDeleted => planLockReason == 'key_deleted';
  bool get wasKeyLocked => wasKeyRevoked || wasKeyDeleted;

  String get warningTitle {
    if (wasKeyRevoked) return 'License revoked';
    if (wasKeyDeleted) return 'License removed';
    if (!writeAllowed) return 'Plan expired';
    return 'Plan ending soon';
  }

  String get warningBody {
    if (wasKeyRevoked) {
      return 'Aapki license key revoke ho gai hai. App read-only hai — messages, broadcast aur naye orders band. Nayi key se renew karein.';
    }
    if (wasKeyDeleted) {
      return 'Aapki license key delete ho gai hai. App read-only hai jab tak nayi key activate na ho.';
    }
    if (!writeAllowed) {
      return 'App ab read-only hai. Messages, broadcast aur naye orders band hain jab tak renew na ho.';
    }
    return 'Jaldi renew karein taake service rukey nahi. Payment ke baad key activate karein.';
  }

  String get bannerText {
    if (wasKeyRevoked) return 'License revoked — read-only. Tap for payment guide.';
    if (wasKeyDeleted) return 'License removed — read-only. Tap for payment guide.';
    if (!writeAllowed) return 'Plan expired — read-only. Tap for payment guide.';
    return 'Plan ends soon — tap to renew.';
  }

  String get planLabel {
    switch (planId) {
      case 'trial_7':
        return '7-day trial';
      case 'd7':
        return '7 days';
      case 'd15':
        return '15 days';
      case 'm1':
        return '1 month';
      case 'm6':
        return '6 months';
      case 'm12':
        return '12 months';
      case 'custom':
        return 'Custom plan';
      default:
        return planId ?? 'No plan';
    }
  }

  String get expiryLabel {
    final exp = planExpiresAt;
    if (exp == null) return 'No expiry set';
    final d = exp.toLocal();
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  bool get isExpiringSoon {
    if (!writeAllowed || planExpiresAt == null) return false;
    final left = planExpiresAt!.difference(DateTime.now());
    return left.inDays <= 3 && left.inSeconds > 0;
  }

  int? get daysLeft {
    if (planExpiresAt == null) return null;
    return planExpiresAt!.difference(DateTime.now()).inDays;
  }
}

class BillingPlanOption {
  final String planId;
  final String label;
  final int durationDays;

  const BillingPlanOption({
    required this.planId,
    required this.label,
    required this.durationDays,
  });
}

class LicenseKeyRow {
  final String key;
  final String planId;
  final int durationDays;
  final String? label;
  final String status;
  final String? usedByTenantId;
  final DateTime? createdAt;

  const LicenseKeyRow({
    required this.key,
    required this.planId,
    required this.durationDays,
    required this.status,
    this.label,
    this.usedByTenantId,
    this.createdAt,
  });
}

class SubscriptionService {
  static final Map<String, TenantBilling> _billingMem = {};
  static final _billingStreams = <String, SharedReplayStream<TenantBilling>>{};

  static TenantBilling? cachedBilling(String tenantId) => _billingMem[tenantId];

  static void rememberBilling(String tenantId, TenantBilling billing) {
    _billingMem[tenantId] = billing;
  }

  static void forgetBilling(String tenantId) {
    _billingMem.remove(tenantId);
  }
  final _firestore = FirebaseFirestore.instance;

  Stream<TenantBilling> watchBilling(String tenantId) {
    final cached = _billingStreams.putIfAbsent(
      tenantId,
      () => SharedReplayStream(
        () => _firestore.collection('tenants').doc(tenantId).snapshots().map((snap) {
          final billing = TenantBilling.fromTenantData(snap.data());
          rememberBilling(tenantId, billing);
          return billing;
        }),
      ),
    );
    return cached.stream;
  }

  Future<TenantBilling> fetchBilling(String tenantId, {bool force = false}) async {
    if (!force) {
      final cached = cachedBilling(tenantId);
      if (cached != null) return cached;
    }
    final snap = await _firestore.collection('tenants').doc(tenantId).get();
    final billing = TenantBilling.fromTenantData(snap.data());
    rememberBilling(tenantId, billing);
    return billing;
  }

  Future<String> _idToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('You are not signed in.');
    return (await user.getIdToken())!;
  }

  Stream<bool> watchIsPlatformAdmin() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Stream.value(false);
    return _firestore.collection('platformAdmins').doc(uid).snapshots().map((s) => s.exists);
  }

  Future<TenantBilling> redeemKey({required String tenantId, required String key}) async {
    final token = await _idToken();
    final response = await http.post(
      Uri.parse('$backendBaseUrl/tenants/$tenantId/billing/redeem'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      body: jsonEncode({'key': key}),
    );
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception((data is Map ? data['error'] : null) ?? 'Could not redeem key.');
    }
    forgetBilling(tenantId);
    return fetchBilling(tenantId, force: true);
  }

  Future<List<String>> createLicenseKeys({
    required String planId,
    int count = 1,
    int? durationDays,
    String? notes,
  }) async {
    final token = await _idToken();
    final response = await http.post(
      Uri.parse('$backendBaseUrl/platform/license-keys'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      body: jsonEncode({
        'planId': planId,
        'count': count,
        if (durationDays != null) 'durationDays': durationDays,
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      }),
    );
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception((data is Map ? data['error'] : null) ?? 'Could not create keys.');
    }
    final keys = (data['keys'] as List?)?.map((e) => e.toString()).toList() ?? [];
    return keys;
  }

  Future<List<LicenseKeyRow>> listLicenseKeys({String? status}) async {
    final token = await _idToken();
    final uri = Uri.parse('$backendBaseUrl/platform/license-keys').replace(
      queryParameters: status == null || status.isEmpty ? null : {'status': status},
    );
    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception((data is Map ? data['error'] : null) ?? 'Could not load keys.');
    }
    final list = (data['keys'] as List?) ?? [];
    return list.map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      return LicenseKeyRow(
        key: m['key']?.toString() ?? '',
        planId: m['planId']?.toString() ?? '',
        durationDays: (m['durationDays'] as num?)?.toInt() ?? 0,
        label: m['label']?.toString(),
        status: m['status']?.toString() ?? '',
        usedByTenantId: m['usedByTenantId']?.toString(),
        createdAt: m['createdAt'] != null ? DateTime.tryParse(m['createdAt'].toString()) : null,
      );
    }).toList();
  }

  Future<String?> revokeLicenseKey(String key) async {
    final token = await _idToken();
    final encoded = Uri.encodeComponent(key);
    final response = await http.post(
      Uri.parse('$backendBaseUrl/platform/license-keys/$encoded/revoke'),
      headers: {'Authorization': 'Bearer $token'},
    );
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception((data is Map ? data['error'] : null) ?? 'Could not revoke key.');
    }
    return data is Map ? data['lockedTenantId']?.toString() : null;
  }

  Future<String?> deleteLicenseKey(String key) async {
    final token = await _idToken();
    final encoded = Uri.encodeComponent(key);
    final response = await http.delete(
      Uri.parse('$backendBaseUrl/platform/license-keys/$encoded'),
      headers: {'Authorization': 'Bearer $token'},
    );
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception((data is Map ? data['error'] : null) ?? 'Could not delete key.');
    }
    return data is Map ? data['lockedTenantId']?.toString() : null;
  }

  Future<List<BillingPlanOption>> listPlans() async {
    final token = await _idToken();
    final response = await http.get(
      Uri.parse('$backendBaseUrl/platform/plans'),
      headers: {'Authorization': 'Bearer $token'},
    );
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      return const [
        BillingPlanOption(planId: 'd7', label: '7 days', durationDays: 7),
        BillingPlanOption(planId: 'd15', label: '15 days', durationDays: 15),
        BillingPlanOption(planId: 'm1', label: '1 month', durationDays: 30),
        BillingPlanOption(planId: 'm6', label: '6 months', durationDays: 182),
        BillingPlanOption(planId: 'm12', label: '12 months', durationDays: 365),
      ];
    }
    final list = (data['plans'] as List?) ?? [];
    return list.map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      return BillingPlanOption(
        planId: m['planId']?.toString() ?? '',
        label: m['label']?.toString() ?? '',
        durationDays: (m['durationDays'] as num?)?.toInt() ?? 0,
      );
    }).toList();
  }

  static String readOnlyMessage =
      'Plan expired — read-only. Renew with a license key to send messages, broadcast, or create orders.';
}
