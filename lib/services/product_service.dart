import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CatalogProduct {
  final String id;
  final String name;
  final double price;
  final String? description;
  final String? sku;
  final String? imageUrl;
  final bool active;
  final DateTime? updatedAt;

  const CatalogProduct({
    required this.id,
    required this.name,
    required this.price,
    this.description,
    this.sku,
    this.imageUrl,
    this.active = true,
    this.updatedAt,
  });

  String get priceLabel => 'PKR ${price.toStringAsFixed(0)}';

  factory CatalogProduct.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return CatalogProduct(
      id: doc.id,
      name: (data['name'] as String?)?.trim() ?? '',
      price: (data['price'] as num?)?.toDouble() ?? 0,
      description: data['description'] as String?,
      sku: data['sku'] as String?,
      imageUrl: data['imageUrl'] as String?,
      active: data['active'] != false,
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }
}

class ProductService {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> _ref(String tenantId) {
    return _firestore.collection('tenants').doc(tenantId).collection('products');
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchProducts(String tenantId) {
    return _ref(tenantId).orderBy('name').snapshots();
  }

  Future<String> createProduct({
    required String tenantId,
    required String name,
    required double price,
    String? description,
    String? sku,
    String? imageUrl,
  }) async {
    final uid = _auth.currentUser!.uid;
    final doc = await _ref(tenantId).add({
      'name': name.trim(),
      'price': price,
      'description': description?.trim().isEmpty == true ? null : description?.trim(),
      'sku': sku?.trim().isEmpty == true ? null : sku?.trim(),
      'imageUrl': imageUrl?.trim().isEmpty == true ? null : imageUrl?.trim(),
      'active': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'createdBy': uid,
    });
    return doc.id;
  }

  Future<void> updateProduct({
    required String tenantId,
    required String productId,
    required String name,
    required double price,
    String? description,
    String? sku,
    String? imageUrl,
    bool? active,
  }) {
    return _ref(tenantId).doc(productId).set({
      'name': name.trim(),
      'price': price,
      'description': (description?.trim().isEmpty ?? true) ? null : description!.trim(),
      'sku': (sku?.trim().isEmpty ?? true) ? null : sku!.trim(),
      'imageUrl': (imageUrl?.trim().isEmpty ?? true) ? null : imageUrl!.trim(),
      if (active != null) 'active': active,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteProduct({required String tenantId, required String productId}) {
    return _ref(tenantId).doc(productId).delete();
  }
}
