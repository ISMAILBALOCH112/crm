import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../config/backend_config.dart';

class CourierField {
  final String key;
  final String label;
  final bool optional;

  const CourierField({required this.key, required this.label, this.optional = false});
}

class CourierKind {
  final String id;
  final String label;
  final List<CourierField> fields;

  const CourierKind({required this.id, required this.label, required this.fields});
}

const kCouriers = [
  CourierKind(id: 'PostEx', label: 'PostEx', fields: [CourierField(key: 'postexToken', label: 'API token')]),
  CourierKind(
    id: 'Leopard',
    label: 'Leopard',
    fields: [
      CourierField(key: 'leopardApiKey', label: 'API key'),
      CourierField(key: 'leopardApiPassword', label: 'API password'),
      CourierField(key: 'leopardOriginCityId', label: 'Origin city id (or self)', optional: true),
    ],
  ),
  CourierKind(
    id: 'TCS',
    label: 'TCS',
    fields: [
      CourierField(key: 'tcsClientId', label: 'Client id'),
      CourierField(key: 'tcsClientSecret', label: 'Client secret'),
      CourierField(key: 'tcsUsername', label: 'Username'),
      CourierField(key: 'tcsPassword', label: 'Password'),
      CourierField(key: 'tcsAccount', label: 'TCS account'),
      CourierField(key: 'tcsShipperName', label: 'Shipper name'),
      CourierField(key: 'tcsShipperAddress', label: 'Shipper address'),
      CourierField(key: 'tcsShipperCity', label: 'Shipper city'),
      CourierField(key: 'tcsShipperPhone', label: 'Shipper phone 03xx', optional: true),
    ],
  ),
  CourierKind(
    id: 'Trax',
    label: 'Trax',
    fields: [
      CourierField(key: 'traxApiKey', label: 'API key'),
      CourierField(key: 'traxOriginCity', label: 'Origin city', optional: true),
    ],
  ),
  CourierKind(
    id: 'BlueEx',
    label: 'BlueEx',
    fields: [
      CourierField(key: 'blueexUsername', label: 'Username'),
      CourierField(key: 'blueexPassword', label: 'Password'),
      CourierField(key: 'blueexAccount', label: 'Account no'),
      CourierField(key: 'blueexOriginCity', label: 'Origin city code', optional: true),
    ],
  ),
  CourierKind(
    id: 'CallCourier',
    label: 'Call Courier',
    fields: [
      CourierField(key: 'callCourierLoginId', label: 'Login id'),
      CourierField(key: 'callCourierApiKey', label: 'API key'),
      CourierField(key: 'callCourierOrigin', label: 'Origin city', optional: true),
      CourierField(key: 'callCourierShipperName', label: 'Shipper name', optional: true),
    ],
  ),
  CourierKind(id: 'M&P', label: 'M&P', fields: [CourierField(key: 'mpApiKey', label: 'API key')]),
  CourierKind(id: 'Rider', label: 'Rider', fields: [CourierField(key: 'riderApiKey', label: 'API key')]),
  CourierKind(id: 'Daewoo', label: 'Daewoo FastEx', fields: [CourierField(key: 'daewooApiKey', label: 'API key')]),
];

class CourierService {
  final _auth = FirebaseAuth.instance;

  Future<String> _idToken() async {
    final token = await _auth.currentUser?.getIdToken();
    if (token == null) throw Exception('Not signed in.');
    return token;
  }

  Future<Map<String, bool>> fetchConfigured(String tenantId) async {
    final token = await _idToken();
    final response = await http.get(
      Uri.parse('$backendBaseUrl/tenants/$tenantId/courier/status'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode != 200) return {};
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final raw = body['configured'] as Map<String, dynamic>? ?? {};
    return raw.map((k, v) => MapEntry(k, v == true));
  }

  Future<void> saveCredentials({
    required String tenantId,
    required String courierId,
    required Map<String, String> fields,
  }) async {
    final token = await _idToken();
    final response = await http.post(
      Uri.parse('$backendBaseUrl/tenants/$tenantId/courier/$courierId/credentials'),
      headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
      body: jsonEncode(fields),
    );
    if (response.statusCode != 200) {
      throw Exception(_error(response) ?? 'Could not save $courierId credentials.');
    }
  }

  Future<String> bookCn({
    required String tenantId,
    required String orderId,
    required String courier,
  }) async {
    final token = await _idToken();
    final response = await http.post(
      Uri.parse('$backendBaseUrl/tenants/$tenantId/orders/$orderId/book-cn'),
      headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
      body: jsonEncode({'courier': courier}),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw Exception(body['error'] as String? ?? 'Could not book CN.');
    }
    return body['trackingNumber'] as String;
  }

  Future<Map<String, dynamic>> syncAll(String tenantId) async {
    final token = await _idToken();
    final response = await http.post(
      Uri.parse('$backendBaseUrl/tenants/$tenantId/orders/sync-cns'),
      headers: {'Authorization': 'Bearer $token'},
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw Exception(body['error'] as String? ?? 'Could not sync CNs.');
    }
    return body;
  }

  Future<Map<String, dynamic>> syncOne({
    required String tenantId,
    required String orderId,
  }) async {
    final token = await _idToken();
    final response = await http.post(
      Uri.parse('$backendBaseUrl/tenants/$tenantId/orders/$orderId/sync-cn'),
      headers: {'Authorization': 'Bearer $token'},
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw Exception(body['error'] as String? ?? 'Could not sync CN.');
    }
    return body;
  }

  String? _error(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body['error'] is String) return body['error'] as String;
    } catch (_) {}
    return response.body.trim().isEmpty ? null : response.body.trim();
  }
}
