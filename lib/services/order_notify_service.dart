import 'package:cloud_firestore/cloud_firestore.dart';

import 'chat_service.dart';
import 'order_service.dart';

class OrderNotifyConfig {
  final bool enabled;
  final bool sendOnCreate;
  final bool sendOnStatusChange;
  final Map<OrderStatus, String> templates;

  const OrderNotifyConfig({
    this.enabled = true,
    this.sendOnCreate = true,
    this.sendOnStatusChange = true,
    required this.templates,
  });

  static const Map<OrderStatus, String> defaultTemplates = {
    OrderStatus.pending: 'Assalam o Alaikum {name}! 🌟',
    OrderStatus.confirmed:
        '{name}, aapka order {orderCode} confirm ho gaya hai.\nAmount: PKR {amount}\nJaldi ship karenge inshaAllah.',
    OrderStatus.shipped:
        '{name}, aapka order {orderCode} ship ho gaya hai.\nCourier: {courier}\nTracking: {tracking}',
    OrderStatus.delivered:
        '{name}, aapka order {orderCode} deliver ho gaya. Shukriya! 🙏',
    OrderStatus.returned:
        '{name}, aapka order {orderCode} courier se return ho gaya hai.\nTracking: {tracking}\nCourier: {courier}',
    OrderStatus.cancelled:
        '{name}, aapka order {orderCode} cancel kar diya gaya hai. Koi sawal ho to message karein.',
  };

  factory OrderNotifyConfig.defaults() => const OrderNotifyConfig(templates: defaultTemplates);

  factory OrderNotifyConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return OrderNotifyConfig.defaults();
    final raw = map['templates'] as Map<String, dynamic>? ?? {};
    final templates = <OrderStatus, String>{};
    for (final status in OrderStatus.values) {
      templates[status] = (raw[status.name] as String?)?.trim().isNotEmpty == true
          ? raw[status.name] as String
          : defaultTemplates[status]!;
    }
    return OrderNotifyConfig(
      enabled: map['enabled'] != false,
      sendOnCreate: map['sendOnCreate'] != false,
      sendOnStatusChange: map['sendOnStatusChange'] != false,
      templates: templates,
    );
  }

  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        'sendOnCreate': sendOnCreate,
        'sendOnStatusChange': sendOnStatusChange,
        'templates': {
          for (final e in templates.entries) e.key.name: e.value,
        },
        'updatedAt': FieldValue.serverTimestamp(),
      };

  OrderNotifyConfig copyWith({
    bool? enabled,
    bool? sendOnCreate,
    bool? sendOnStatusChange,
    Map<OrderStatus, String>? templates,
  }) {
    return OrderNotifyConfig(
      enabled: enabled ?? this.enabled,
      sendOnCreate: sendOnCreate ?? this.sendOnCreate,
      sendOnStatusChange: sendOnStatusChange ?? this.sendOnStatusChange,
      templates: templates ?? this.templates,
    );
  }
}

class OrderNotifyService {
  final _firestore = FirebaseFirestore.instance;
  final _chat = ChatService();

  DocumentReference<Map<String, dynamic>> _ref(String tenantId) {
    return _firestore.collection('tenants').doc(tenantId).collection('settings').doc('orderNotify');
  }

  Stream<OrderNotifyConfig> watchConfig(String tenantId) {
    return _ref(tenantId).snapshots().map((snap) => OrderNotifyConfig.fromMap(snap.data()));
  }

  Future<OrderNotifyConfig> loadConfig(String tenantId) async {
    final snap = await _ref(tenantId).get();
    return OrderNotifyConfig.fromMap(snap.data());
  }

  Future<void> saveConfig(String tenantId, OrderNotifyConfig config) {
    return _ref(tenantId).set(config.toMap(), SetOptions(merge: true));
  }

  static String normalizePhone(String raw) {
    var digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('00')) digits = digits.substring(2);
    if (digits.startsWith('0')) digits = '92${digits.substring(1)}';
    return digits;
  }

  static String fillTemplate(String template, CrmOrder order) {
    final amount = order.totalAmount.toStringAsFixed(0);
    final tracking = (order.trackingNumber == null || order.trackingNumber!.trim().isEmpty)
        ? '—'
        : order.trackingNumber!.trim();
    return template
        .replaceAll('{name}', order.customerName)
        .replaceAll('{orderCode}', order.displayId)
        .replaceAll('{amount}', amount)
        .replaceAll('{items}', order.itemsSummary)
        .replaceAll('{city}', order.city?.trim().isNotEmpty == true ? order.city! : '—')
        .replaceAll('{address}', order.address?.trim().isNotEmpty == true ? order.address! : '—')
        .replaceAll('{tracking}', tracking)
        .replaceAll('{courier}', order.courier ?? 'Manual')
        .replaceAll('{phone}', order.customerPhone)
        .replaceAll('{notes}', order.notes?.trim().isNotEmpty == true ? order.notes! : '—');
  }

  /// Immediate WhatsApp for status changes (not the delayed create prompt).
  Future<bool> notify({
    required String tenantId,
    required CrmOrder order,
    required bool isCreate,
    bool force = false,
  }) async {
    if (isCreate) return false;

    final config = await loadConfig(tenantId);
    if (!config.enabled) return false;
    if (!config.sendOnStatusChange && !force) return false;

    final template = config.templates[order.status]?.trim() ?? '';
    if (template.isEmpty) return false;

    final text = fillTemplate(template, order);
    final phone = normalizePhone(order.customerPhone);
    if (phone.length < 10) {
      throw Exception('Customer phone is not a valid WhatsApp number.');
    }

    await _chat.ensureContact(tenantId: tenantId, phone: phone, name: order.customerName);
    await _chat.sendMessage(tenantId: tenantId, to: phone, text: text);
    return true;
  }
}
