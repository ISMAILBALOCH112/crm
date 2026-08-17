import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../services/media_upload_service.dart';
import '../services/product_service.dart';
import '../theme/app_theme.dart';

class CatalogScreen extends StatefulWidget {
  final String tenantId;
  final bool pickMode;
  final bool canManage;

  const CatalogScreen({
    super.key,
    required this.tenantId,
    this.pickMode = false,
    this.canManage = true,
  });

  static Future<void> open(BuildContext context, String tenantId, {bool canManage = true}) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CatalogScreen(tenantId: tenantId, canManage: canManage),
      ),
    );
  }

  static Future<CatalogProduct?> pick(BuildContext context, String tenantId) {
    return Navigator.of(context).push<CatalogProduct>(
      MaterialPageRoute(
        builder: (_) => CatalogScreen(tenantId: tenantId, pickMode: true, canManage: false),
      ),
    );
  }

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  final _productService = ProductService();

  Future<void> _openEditor({CatalogProduct? existing}) async {
    if (!widget.canManage) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _ProductEditorDialog(tenantId: widget.tenantId, existing: existing),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(existing == null ? 'Product added' : 'Product updated')),
      );
    }
  }

  Future<void> _delete(CatalogProduct product) async {
    if (!widget.canManage) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete product?'),
        content: Text('Remove "${product.name}" from catalog?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _productService.deleteProduct(tenantId: widget.tenantId, productId: product.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.pickMode ? 'Pick product' : 'CRM catalog',
              style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 18),
            ),
            if (!widget.pickMode)
              const Text(
                'In-app products — not Meta Commerce sync',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w500),
              ),
          ],
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        actions: [
          if (!widget.pickMode && widget.canManage)
            IconButton(
              tooltip: 'Add product',
              onPressed: () => _openEditor(),
              icon: const Icon(Icons.add_rounded, color: AppColors.primary),
            ),
        ],
      ),
      floatingActionButton: widget.pickMode || !widget.canManage
          ? null
          : FloatingActionButton(
              onPressed: () => _openEditor(),
              backgroundColor: AppColors.primary,
              child: const Icon(Icons.add, color: Colors.white),
            ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _productService.watchProducts(widget.tenantId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primary));
          }
          var products = snapshot.data!.docs.map(CatalogProduct.fromDoc).toList();
          if (widget.pickMode) {
            products = products.where((p) => p.active).toList();
          }
          if (products.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.inventory_2_outlined, size: 48, color: AppColors.textSecondary),
                    const SizedBox(height: 12),
                    Text(
                      widget.pickMode ? 'No products yet' : 'Add your first product',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 15),
                    ),
                    if (!widget.pickMode) ...[
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () => _openEditor(),
                        icon: const Icon(Icons.add),
                        label: const Text('Add product'),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
            itemCount: products.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final product = products[index];
              return Material(
                color: AppColors.surfaceSolid,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {
                    if (widget.pickMode) {
                      Navigator.pop(context, product);
                    } else if (widget.canManage) {
                      _openEditor(existing: product);
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            width: 56,
                            height: 56,
                            child: product.imageUrl != null && product.imageUrl!.isNotEmpty
                                ? Image.network(product.imageUrl!, fit: BoxFit.cover)
                                : Container(
                                    color: AppColors.primary.withValues(alpha: 0.1),
                                    child: const Icon(Icons.shopping_bag_outlined, color: AppColors.primary),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                product.name,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: product.active ? AppColors.textPrimary : AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                product.priceLabel,
                                style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600),
                              ),
                              if (product.description?.trim().isNotEmpty == true)
                                Text(
                                  product.description!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.9), fontSize: 12),
                                ),
                            ],
                          ),
                        ),
                        if (!widget.pickMode && widget.canManage)
                          IconButton(
                            tooltip: 'Delete',
                            onPressed: () => _delete(product),
                            icon: const Icon(Icons.delete_outline, color: AppColors.error, size: 20),
                          )
                        else if (widget.pickMode)
                          const Icon(Icons.chevron_right, color: AppColors.textSecondary),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _ProductEditorDialog extends StatefulWidget {
  final String tenantId;
  final CatalogProduct? existing;

  const _ProductEditorDialog({required this.tenantId, this.existing});

  @override
  State<_ProductEditorDialog> createState() => _ProductEditorDialogState();
}

class _ProductEditorDialogState extends State<_ProductEditorDialog> {
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _desc = TextEditingController();
  final _sku = TextEditingController();
  final _products = ProductService();
  final _upload = MediaUploadService();
  String? _imageUrl;
  bool _active = true;
  bool _saving = false;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _name.text = e.name;
      _price.text = e.price.toStringAsFixed(0);
      _desc.text = e.description ?? '';
      _sku.text = e.sku ?? '';
      _imageUrl = e.imageUrl;
      _active = e.active;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _desc.dispose();
    _sku.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (file == null) return;
    setState(() => _uploading = true);
    try {
      final url = await _upload.uploadImage(file);
      if (mounted) setState(() => _imageUrl = url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final price = double.tryParse(_price.text.trim()) ?? 0;
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name required')));
      return;
    }
    if (price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Price required')));
      return;
    }
    setState(() => _saving = true);
    try {
      final existing = widget.existing;
      if (existing == null) {
        await _products.createProduct(
          tenantId: widget.tenantId,
          name: name,
          price: price,
          description: _desc.text,
          sku: _sku.text,
          imageUrl: _imageUrl,
        );
      } else {
        await _products.updateProduct(
          tenantId: widget.tenantId,
          productId: existing.id,
          name: name,
          price: price,
          description: _desc.text,
          sku: _sku.text,
          imageUrl: _imageUrl,
          active: _active,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add product' : 'Edit product'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: _uploading ? null : _pickImage,
              child: Container(
                height: 120,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.surfaceBorder),
                ),
                clipBehavior: Clip.antiAlias,
                child: _uploading
                    ? const Center(child: CircularProgressIndicator())
                    : _imageUrl != null && _imageUrl!.isNotEmpty
                        ? Image.network(_imageUrl!, fit: BoxFit.cover)
                        : const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_a_photo_outlined, color: AppColors.textSecondary),
                              SizedBox(height: 6),
                              Text('Add photo', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                            ],
                          ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _price,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Price (PKR)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _sku,
              decoration: const InputDecoration(labelText: 'SKU (optional)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _desc,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder()),
            ),
            if (widget.existing != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active'),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Save'),
        ),
      ],
    );
  }
}
