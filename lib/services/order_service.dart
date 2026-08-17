import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'order_notify_service.dart';
import 'shared_replay_stream.dart';

enum OrderStatus { pending, confirmed, shipped, delivered, returned, cancelled }

extension OrderStatusX on OrderStatus {
  String get label => switch (this) {
        OrderStatus.pending => 'New',
        OrderStatus.confirmed => 'Confirmed',
        OrderStatus.shipped => 'Shipped',
        OrderStatus.delivered => 'Delivered',
        OrderStatus.returned => 'Returned',
        OrderStatus.cancelled => 'Cancelled',
      };

  String get badgeLabel => label.toUpperCase();

  String get value => name;

  static OrderStatus fromString(String? raw) {
    return OrderStatus.values.firstWhere(
      (s) => s.name == raw,
      orElse: () => OrderStatus.pending,
    );
  }
}

enum PaymentStatus { unpaid, partial, paid }

enum PaymentMethod { cod, jazzcash, easypaisa }

extension PaymentMethodX on PaymentMethod {
  String get value => name;

  String get label => switch (this) {
        PaymentMethod.cod => 'COD',
        PaymentMethod.jazzcash => 'JazzCash',
        PaymentMethod.easypaisa => 'EasyPaisa',
      };

  static PaymentMethod fromString(String? raw) {
    return PaymentMethod.values.firstWhere(
      (e) => e.name == (raw ?? '').trim().toLowerCase(),
      orElse: () => PaymentMethod.cod,
    );
  }
}

extension PaymentStatusX on PaymentStatus {
  String get label => switch (this) {
        PaymentStatus.unpaid => 'Unpaid',
        PaymentStatus.partial => 'Partial',
        PaymentStatus.paid => 'Paid',
      };

  String get badgeLabel => label.toUpperCase();

  String get value => name;

  static PaymentStatus fromString(String? raw) {
    return PaymentStatus.values.firstWhere(
      (s) => s.name == raw,
      orElse: () => PaymentStatus.unpaid,
    );
  }

  /// Normalize status from amount vs total (COD / advance payments).
  static PaymentStatus fromAmounts({required double paidAmount, required double totalAmount}) {
    final total = totalAmount < 0 ? 0.0 : totalAmount;
    final paid = paidAmount < 0 ? 0.0 : paidAmount;
    if (total <= 0) return paid > 0 ? PaymentStatus.paid : PaymentStatus.unpaid;
    if (paid <= 0) return PaymentStatus.unpaid;
    if (paid + 0.001 >= total) return PaymentStatus.paid;
    return PaymentStatus.partial;
  }
}

class OrderItem {
  final String name;
  final int qty;
  final double price;

  const OrderItem({required this.name, required this.qty, required this.price});

  double get lineTotal => qty * price;

  Map<String, dynamic> toMap() => {'name': name, 'qty': qty, 'price': price};

  factory OrderItem.fromMap(Map<String, dynamic> map) {
    return OrderItem(
      name: map['name'] as String? ?? '',
      qty: (map['qty'] as num?)?.toInt() ?? 1,
      price: (map['price'] as num?)?.toDouble() ?? 0,
    );
  }
}

class CrmOrder {
  final String id;
  final int orderNumber;
  final String customerPhone;
  final String customerName;
  final List<OrderItem> items;
  final double totalAmount;
  final OrderStatus status;
  final PaymentStatus paymentStatus;
  final PaymentMethod paymentMethod;
  final double paidAmount;
  final String? notes;
  final String? orderCode;
  final String? trackingNumber;
  final String? courier;
  final String? city;
  final String? address;
  final String? courierStatus;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? createdBy;

  const CrmOrder({
    required this.id,
    required this.orderNumber,
    required this.customerPhone,
    required this.customerName,
    required this.items,
    required this.totalAmount,
    required this.status,
    this.paymentStatus = PaymentStatus.unpaid,
    this.paymentMethod = PaymentMethod.cod,
    this.paidAmount = 0,
    this.notes,
    this.orderCode,
    this.trackingNumber,
    this.courier,
    this.city,
    this.address,
    this.courierStatus,
    this.createdAt,
    this.updatedAt,
    this.createdBy,
  });

  String get displayId => orderCode ?? '#$orderNumber';

  String get itemsSummary {
    if (items.isEmpty) return 'No items';
    if (items.length == 1) return '${items.first.name} × ${items.first.qty}';
    return '${items.length} items';
  }

  double get balanceDue {
    final due = totalAmount - paidAmount;
    return due < 0 ? 0 : due;
  }

  bool get canSyncCn {
    final tracking = trackingNumber?.trim() ?? '';
    if (tracking.isEmpty) return false;
    if (courier == null || courier == 'Manual') return false;
    return status != OrderStatus.delivered &&
        status != OrderStatus.cancelled &&
        status != OrderStatus.returned;
  }

  CrmOrder copyWith({
    OrderStatus? status,
    PaymentStatus? paymentStatus,
    PaymentMethod? paymentMethod,
    double? paidAmount,
    String? trackingNumber,
    String? courier,
    String? courierStatus,
  }) {
    return CrmOrder(
      id: id,
      orderNumber: orderNumber,
      customerPhone: customerPhone,
      customerName: customerName,
      items: items,
      totalAmount: totalAmount,
      status: status ?? this.status,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paidAmount: paidAmount ?? this.paidAmount,
      notes: notes,
      orderCode: orderCode,
      trackingNumber: trackingNumber ?? this.trackingNumber,
      courier: courier ?? this.courier,
      city: city,
      address: address,
      courierStatus: courierStatus ?? this.courierStatus,
      createdAt: createdAt,
      updatedAt: updatedAt,
      createdBy: createdBy,
    );
  }

  factory CrmOrder.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    return CrmOrder.fromSnapshot(doc);
  }

  factory CrmOrder.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    final rawItems = data['items'] as List<dynamic>? ?? [];
    final total = (data['totalAmount'] as num?)?.toDouble() ?? 0;
    final paid = (data['paidAmount'] as num?)?.toDouble() ?? 0;
    final storedPayment = data['paymentStatus'] as String?;
    final payment = storedPayment != null
        ? PaymentStatusX.fromString(storedPayment)
        : PaymentStatusX.fromAmounts(paidAmount: paid, totalAmount: total);
    return CrmOrder(
      id: doc.id,
      orderNumber: (data['orderNumber'] as num?)?.toInt() ?? 0,
      customerPhone: data['customerPhone'] as String? ?? '',
      customerName: data['customerName'] as String? ?? '',
      items: rawItems.map((e) => OrderItem.fromMap(Map<String, dynamic>.from(e as Map))).toList(),
      totalAmount: total,
      status: OrderStatusX.fromString(data['status'] as String?),
      paymentStatus: payment,
      paymentMethod: PaymentMethodX.fromString(data['paymentMethod'] as String?),
      paidAmount: paid,
      notes: data['notes'] as String?,
      orderCode: data['orderCode'] as String?,
      trackingNumber: data['trackingNumber'] as String?,
      courier: data['courier'] as String?,
      city: data['city'] as String?,
      address: data['address'] as String?,
      courierStatus: data['courierStatus'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      createdBy: data['createdBy'] as String?,
    );
  }
}

class OrderService {
  static final _orderStreams = <String, SharedReplayStream<QuerySnapshot<Map<String, dynamic>>>>{};
  static final _recentOrderStreams = <String, SharedReplayStream<QuerySnapshot<Map<String, dynamic>>>>{};

  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> _ordersRef(String tenantId) {
    return _firestore.collection('tenants').doc(tenantId).collection('orders');
  }

  DocumentReference<Map<String, dynamic>> _counterRef(String tenantId) {
    return _firestore.collection('tenants').doc(tenantId).collection('meta').doc('orderCounter');
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchOrders(String tenantId) {
    final cached = _orderStreams.putIfAbsent(
      tenantId,
      () => SharedReplayStream(
        () => _ordersRef(tenantId).orderBy('createdAt', descending: true).snapshots(),
      ),
    );
    return cached.stream;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchRecentOrders(String tenantId, {int limit = 80}) {
    final key = '$tenantId|$limit';
    final cached = _recentOrderStreams.putIfAbsent(
      key,
      () => SharedReplayStream(
        () => _ordersRef(tenantId).orderBy('createdAt', descending: true).limit(limit).snapshots(),
      ),
    );
    return cached.stream;
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchOrder(String tenantId, String orderId) {
    return _ordersRef(tenantId).doc(orderId).snapshots();
  }

  Future<int> _nextOrderNumber(String tenantId) async {
    return _firestore.runTransaction((tx) async {
      final snap = await tx.get(_counterRef(tenantId));
      final last = (snap.data()?['lastNumber'] as num?)?.toInt() ?? 1000;
      final next = last + 1;
      tx.set(_counterRef(tenantId), {'lastNumber': next}, SetOptions(merge: true));
      return next;
    });
  }

  Future<CrmOrder> createOrder({
    required String tenantId,
    required String customerPhone,
    required String customerName,
    required List<OrderItem> items,
    String? notes,
    String? city,
    String? address,
    PaymentMethod paymentMethod = PaymentMethod.cod,
    bool scheduleWhatsAppConfirm = false,
    int whatsAppDelayMinutes = 30,
  }) async {
    final uid = _auth.currentUser!.uid;
    final orderNumber = await _nextOrderNumber(tenantId);
    final total = items.fold<double>(0, (running, i) => running + i.lineTotal);
    final now = Timestamp.now();
    final orderCode = 'WT-$orderNumber';

    final data = <String, dynamic>{
      'orderNumber': orderNumber,
      'orderCode': orderCode,
      'customerPhone': customerPhone.trim(),
      'customerName': customerName.trim(),
      'items': items.map((i) => i.toMap()).toList(),
      'totalAmount': total,
      'status': OrderStatus.pending.value,
      'paymentStatus': PaymentStatus.unpaid.value,
      'paymentMethod': paymentMethod.value,
      'paidAmount': 0,
      'courier': 'Manual',
      'createdAt': now,
      'updatedAt': now,
      'createdBy': uid,
    };
    final trimmedNotes = notes?.trim();
    if (trimmedNotes != null && trimmedNotes.isNotEmpty) {
      data['notes'] = trimmedNotes;
    }
    final trimmedCity = city?.trim();
    if (trimmedCity != null && trimmedCity.isNotEmpty) {
      data['city'] = trimmedCity;
    }
    final trimmedAddress = address?.trim();
    if (trimmedAddress != null && trimmedAddress.isNotEmpty) {
      data['address'] = trimmedAddress;
    }
    if (scheduleWhatsAppConfirm) {
      final delay = whatsAppDelayMinutes < 0 ? 30 : whatsAppDelayMinutes;
      data['whatsappConfirmStatus'] = 'scheduled';
      data['whatsappConfirmDelayMinutes'] = delay;
      data['whatsappConfirmDueAt'] = Timestamp.fromDate(
        DateTime.now().add(Duration(minutes: delay)),
      );
    }

    final doc = await _ordersRef(tenantId).add(data);

    // Cancel pending auto follow-up — this chat already has an order.
    try {
      final phone = OrderNotifyService.normalizePhone(customerPhone);
      if (phone.length >= 10) {
        await _firestore.collection('tenants').doc(tenantId).collection('contacts').doc(phone).set(
          {
            'hasOrder': true,
            'abandonedCartStatus': 'converted',
            'abandonedCartConvertedAt': FieldValue.serverTimestamp(),
            'autoFollowUpAwaitingReply': false,
          },
          SetOptions(merge: true),
        );
      }
    } catch (_) {}

    return CrmOrder(
      id: doc.id,
      orderNumber: orderNumber,
      customerPhone: customerPhone.trim(),
      customerName: customerName.trim(),
      items: items,
      totalAmount: total,
      status: OrderStatus.pending,
      paymentStatus: PaymentStatus.unpaid,
      paymentMethod: paymentMethod,
      paidAmount: 0,
      notes: trimmedNotes,
      orderCode: orderCode,
      courier: 'Manual',
      city: trimmedCity,
      address: trimmedAddress,
      createdAt: now.toDate(),
      updatedAt: now.toDate(),
      createdBy: uid,
    );
  }

  Future<void> updateStatus({
    required String tenantId,
    required String orderId,
    required OrderStatus status,
  }) {
    final data = <String, dynamic>{
      'status': status.value,
      'updatedAt': Timestamp.now(),
    };
    if (status != OrderStatus.pending) {
      data['whatsappConfirmStatus'] = 'skipped';
    }
    return _ordersRef(tenantId).doc(orderId).update(data);
  }

  Future<void> updatePayment({
    required String tenantId,
    required String orderId,
    required PaymentStatus paymentStatus,
    required double totalAmount,
    double? paidAmount,
    PaymentMethod? paymentMethod,
  }) {
    final total = totalAmount < 0 ? 0.0 : totalAmount;
    final double paid = switch (paymentStatus) {
      PaymentStatus.unpaid => 0,
      PaymentStatus.paid => total,
      PaymentStatus.partial => (paidAmount ?? 0).clamp(0, total).toDouble(),
    };
    final resolved = PaymentStatusX.fromAmounts(paidAmount: paid, totalAmount: total);
    final data = <String, dynamic>{
      'paymentStatus': resolved.value,
      'paidAmount': resolved == PaymentStatus.paid ? total : paid,
      'updatedAt': Timestamp.now(),
    };
    if (paymentMethod != null) data['paymentMethod'] = paymentMethod.value;
    return _ordersRef(tenantId).doc(orderId).update(data);
  }

  Future<void> updatePaymentMethod({
    required String tenantId,
    required String orderId,
    required PaymentMethod paymentMethod,
  }) {
    return _ordersRef(tenantId).doc(orderId).update({
      'paymentMethod': paymentMethod.value,
      'updatedAt': Timestamp.now(),
    });
  }

  Future<void> updateOrder({
    required String tenantId,
    required String orderId,
    required String customerPhone,
    required String customerName,
    required List<OrderItem> items,
    String? notes,
    String? city,
    String? address,
    PaymentMethod? paymentMethod,
  }) {
    final total = items.fold<double>(0, (running, i) => running + i.lineTotal);
    final data = <String, dynamic>{
      'customerPhone': customerPhone.trim(),
      'customerName': customerName.trim(),
      'items': items.map((i) => i.toMap()).toList(),
      'totalAmount': total,
      'updatedAt': Timestamp.now(),
    };
    if (paymentMethod != null) data['paymentMethod'] = paymentMethod.value;
    final trimmedNotes = notes?.trim();
    if (trimmedNotes != null && trimmedNotes.isNotEmpty) {
      data['notes'] = trimmedNotes;
    } else {
      data['notes'] = FieldValue.delete();
    }
    final trimmedCity = city?.trim();
    if (trimmedCity != null && trimmedCity.isNotEmpty) {
      data['city'] = trimmedCity;
    } else {
      data['city'] = FieldValue.delete();
    }
    final trimmedAddress = address?.trim();
    if (trimmedAddress != null && trimmedAddress.isNotEmpty) {
      data['address'] = trimmedAddress;
    } else {
      data['address'] = FieldValue.delete();
    }
    return _ordersRef(tenantId).doc(orderId).update(data);
  }

  Future<void> deleteOrders({required String tenantId, required List<String> orderIds}) async {
    final batch = _firestore.batch();
    for (final id in orderIds) {
      batch.delete(_ordersRef(tenantId).doc(id));
    }
    await batch.commit();
  }

  Future<void> updateTracking({
    required String tenantId,
    required String orderId,
    required String trackingNumber,
    String courier = 'Manual',
    OrderStatus? status,
  }) {
    final data = <String, dynamic>{
      'trackingNumber': trackingNumber.trim(),
      'courier': courier,
      'updatedAt': Timestamp.now(),
    };
    if (status != null) {
      data['status'] = status.value;
      if (status != OrderStatus.pending) {
        data['whatsappConfirmStatus'] = 'skipped';
      }
    }
    return _ordersRef(tenantId).doc(orderId).update(data);
  }
}
