import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/chat_service.dart';
import '../services/order_notify_service.dart';
import '../services/order_service.dart';
import '../services/subscription_service.dart';
import '../theme/app_theme.dart';
import 'catalog_screen.dart';

class CreateOrderResult {
  final bool whatsAppScheduled;
  final int delayMinutes;
  final String whatsAppError;

  const CreateOrderResult({
    this.whatsAppScheduled = false,
    this.delayMinutes = 30,
    this.whatsAppError = '',
  });
}

class _DraftLine {
  String name;
  int qty;
  double unitPrice;

  _DraftLine({required this.name, this.qty = 1, required this.unitPrice});

  double get lineTotal => qty * unitPrice;
}

class CreateOrderScreen extends StatefulWidget {
  final String tenantId;
  final CrmOrder? existingOrder;
  final String? initialPhone;
  final String? initialName;

  const CreateOrderScreen({
    super.key,
    required this.tenantId,
    this.existingOrder,
    this.initialPhone,
    this.initialName,
  });

  static Future<CreateOrderResult?> show(
    BuildContext context,
    String tenantId, {
    String? initialPhone,
    String? initialName,
  }) {
    return showDialog<CreateOrderResult>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (_) => CreateOrderScreen(
        tenantId: tenantId,
        initialPhone: initialPhone,
        initialName: initialName,
      ),
    );
  }

  static Future<bool?> showEdit(BuildContext context, String tenantId, CrmOrder order) {
    return showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (_) => CreateOrderScreen(tenantId: tenantId, existingOrder: order),
    );
  }

  bool get isEditing => existingOrder != null;

  @override
  State<CreateOrderScreen> createState() => _CreateOrderScreenState();
}

class _CreateOrderScreenState extends State<CreateOrderScreen> {
  final _orderService = OrderService();
  final _chatService = ChatService();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _cityController = TextEditingController();
  final _addressController = TextEditingController();
  final _notesController = TextEditingController();
  PaymentMethod _paymentMethod = PaymentMethod.cod;

  final List<_DraftLine> _lines = [];
  bool _saving = false;
  bool _sendWhatsApp = true;
  int _whatsAppDelayMinutes = 30;

  static const _delayOptions = [0, 1, 5, 15, 30, 60];

  double get _total => _lines.fold<double>(0, (sum, l) => sum + l.lineTotal);

  @override
  void initState() {
    super.initState();
    final order = widget.existingOrder;
    if (order != null) {
      _nameController.text = order.customerName;
      _phoneController.text = order.customerPhone;
      for (final item in order.items) {
        _lines.add(_DraftLine(name: item.name, qty: item.qty, unitPrice: item.price));
      }
      _cityController.text = order.city ?? '';
      _addressController.text = order.address ?? '';
      _notesController.text = order.notes ?? '';
      _paymentMethod = order.paymentMethod;
    } else {
      if (widget.initialPhone != null && widget.initialPhone!.trim().isNotEmpty) {
        _phoneController.text = widget.initialPhone!.trim();
      }
      if (widget.initialName != null && widget.initialName!.trim().isNotEmpty) {
        _nameController.text = widget.initialName!.trim();
      }
      OrderNotifyService().loadConfig(widget.tenantId).then((config) {
        if (!mounted) return;
        setState(() => _sendWhatsApp = config.enabled && config.sendOnCreate);
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _cityController.dispose();
    _addressController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final phone = _phoneController.text.trim();
    final name = _nameController.text.trim();

    if (name.isEmpty) {
      _showError('Name is required');
      return;
    }
    if (phone.isEmpty) {
      _showError('Phone is required');
      return;
    }
    if (_lines.isEmpty) {
      _showError('Add at least one product');
      return;
    }
    for (final line in _lines) {
      if (line.name.trim().isEmpty) {
        _showError('Each item needs a name');
        return;
      }
      if (line.qty <= 0) {
        _showError('Qty must be at least 1');
        return;
      }
      if (line.unitPrice <= 0) {
        _showError('Each item needs a price');
        return;
      }
    }

    final items = _lines
        .map((l) => OrderItem(name: l.name.trim(), qty: l.qty, price: l.unitPrice))
        .toList();

    if (!widget.isEditing) {
      final billing = await SubscriptionService().fetchBilling(widget.tenantId);
      if (!billing.writeAllowed) {
        _showError(SubscriptionService.readOnlyMessage);
        return;
      }
    }

    setState(() => _saving = true);
    try {
      if (widget.isEditing) {
        await _orderService.updateOrder(
          tenantId: widget.tenantId,
          orderId: widget.existingOrder!.id,
          customerPhone: phone,
          customerName: name,
          items: items,
          city: _cityController.text.trim(),
          address: _addressController.text.trim(),
          notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
          paymentMethod: _paymentMethod,
        );
        if (mounted) Navigator.pop(context, true);
        return;
      }

      await _orderService.createOrder(
        tenantId: widget.tenantId,
        customerPhone: OrderNotifyService.normalizePhone(phone),
        customerName: name,
        items: items,
        city: _cityController.text.trim(),
        address: _addressController.text.trim(),
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        paymentMethod: _paymentMethod,
        scheduleWhatsAppConfirm: _sendWhatsApp,
        whatsAppDelayMinutes: _whatsAppDelayMinutes,
      );

      if (!mounted) return;
      Navigator.pop(
        context,
        CreateOrderResult(whatsAppScheduled: _sendWhatsApp, delayMinutes: _whatsAppDelayMinutes),
      );
    } catch (e) {
      _showError('$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _delayLabel(int minutes) {
    if (minutes <= 0) return 'Now';
    if (minutes < 60) return '$minutes min';
    if (minutes == 60) return '1 hour';
    final hours = minutes / 60;
    return hours == hours.roundToDouble() ? '${hours.toInt()} hours' : '$minutes min';
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
  }

  void _selectContact(ChatContact contact) {
    _nameController.text = contact.name;
    _phoneController.text = contact.phone;
    Navigator.pop(context);
  }

  Future<void> _pickContact() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceSolid,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: SizedBox(
            height: 360,
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Select from chats',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                ),
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _chatService.watchContacts(widget.tenantId),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator(color: AppColors.primary));
                      }
                      final contacts = snapshot.data!.docs.map(ChatContact.fromDoc).toList();
                      if (contacts.isEmpty) {
                        return const Center(child: Text('No contacts yet'));
                      }
                      return ListView.builder(
                        itemCount: contacts.length,
                        itemBuilder: (context, index) {
                          final c = contacts[index];
                          return ListTile(
                            title: Text(c.name),
                            subtitle: Text(c.phone),
                            onTap: () => _selectContact(c),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickFromCatalog() async {
    final product = await CatalogScreen.pick(context, widget.tenantId);
    if (product == null || !mounted) return;
    setState(() {
      _lines.add(_DraftLine(name: product.name, qty: 1, unitPrice: product.price));
    });
  }

  Future<void> _addCustomLine() async {
    final nameCtrl = TextEditingController();
    final priceCtrl = TextEditingController(text: '0');
    final qtyCtrl = TextEditingController(text: '1');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Custom item'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
            TextField(
              controller: qtyCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Qty'),
            ),
            TextField(
              controller: priceCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Unit price (PKR)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final name = nameCtrl.text.trim();
    final qty = int.tryParse(qtyCtrl.text.trim()) ?? 0;
    final price = double.tryParse(priceCtrl.text.trim()) ?? 0;
    if (name.isEmpty || qty <= 0 || price <= 0) {
      _showError('Name, qty and price required');
      return;
    }
    setState(() => _lines.add(_DraftLine(name: name, qty: qty, unitPrice: price)));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surfaceSolid,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.88),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.isEditing ? 'Edit order' : 'New order',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: Text(
                      'Cancel',
                      style: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.9)),
                    ),
                  ),
                ],
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _pickContact,
                icon: const Icon(Icons.contacts_outlined, size: 16),
                label: const Text('From chats', style: TextStyle(fontSize: 12.5)),
                style: TextButton.styleFrom(foregroundColor: AppColors.primary),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _FieldLabel('Name'),
                    _FormField(controller: _nameController, hint: 'Customer name'),
                    const SizedBox(height: 12),
                    const _FieldLabel('Phone'),
                    _FormField(
                      controller: _phoneController,
                      hint: '923001234567',
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Expanded(child: _FieldLabel('Items')),
                        TextButton.icon(
                          onPressed: _pickFromCatalog,
                          icon: const Icon(Icons.inventory_2_outlined, size: 16),
                          label: const Text('Catalog', style: TextStyle(fontSize: 12.5)),
                          style: TextButton.styleFrom(foregroundColor: AppColors.primary),
                        ),
                        TextButton.icon(
                          onPressed: _addCustomLine,
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Custom', style: TextStyle(fontSize: 12.5)),
                          style: TextButton.styleFrom(foregroundColor: AppColors.primary),
                        ),
                      ],
                    ),
                    if (_lines.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.surfaceBorder),
                        ),
                        child: const Text(
                          'Add products from catalog or custom item',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                        ),
                      )
                    else
                      ...List.generate(_lines.length, (index) {
                        final line = _lines[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                            decoration: BoxDecoration(
                              color: AppColors.background,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.surfaceBorder),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        line.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.textPrimary,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'PKR ${line.unitPrice.toStringAsFixed(0)} × ${line.qty} = PKR ${line.lineTotal.toStringAsFixed(0)}',
                                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () {
                                    setState(() {
                                      if (line.qty > 1) line.qty -= 1;
                                    });
                                  },
                                  icon: const Icon(Icons.remove_circle_outline, size: 20),
                                ),
                                Text('${line.qty}', style: const TextStyle(fontWeight: FontWeight.w700)),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => setState(() => line.qty += 1),
                                  icon: const Icon(Icons.add_circle_outline, size: 20),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => setState(() => _lines.removeAt(index)),
                                  icon: const Icon(Icons.delete_outline, color: AppColors.error, size: 20),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    if (_lines.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'Total: PKR ${_total.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    const _FieldLabel('City'),
                    _FormField(controller: _cityController, hint: 'Karachi'),
                    const SizedBox(height: 12),
                    const _FieldLabel('Address'),
                    _FormField(
                      controller: _addressController,
                      hint: 'Full delivery address',
                      maxLines: 3,
                    ),
                    const SizedBox(height: 12),
                    const _FieldLabel('Payment method'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final m in PaymentMethod.values)
                          ChoiceChip(
                            label: Text(m.label),
                            selected: _paymentMethod == m,
                            onSelected: (_) => setState(() => _paymentMethod = m),
                            selectedColor: AppColors.primary.withValues(alpha: 0.18),
                            labelStyle: TextStyle(
                              color: _paymentMethod == m ? AppColors.primary : AppColors.textSecondary,
                              fontWeight: _paymentMethod == m ? FontWeight.w700 : FontWeight.w500,
                              fontSize: 12.5,
                            ),
                            side: BorderSide(
                              color: _paymentMethod == m ? AppColors.primary : AppColors.surfaceBorder,
                            ),
                          ),
                      ],
                    ),
                    if (_paymentMethod != PaymentMethod.cod)
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text(
                          'JazzCash/EasyPaisa numbers Settings → Parcel payment se aayenge. Paid mark karne ke baad courier COD 0 hoga.',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5, height: 1.3),
                        ),
                      ),
                    const SizedBox(height: 12),
                    const _FieldLabel('Notes (optional)'),
                    _FormField(
                      controller: _notesController,
                      hint: 'Call before delivery / landmark',
                      maxLines: 2,
                    ),
                    if (!widget.isEditing) ...[
                      const SizedBox(height: 8),
                      StreamBuilder<OrderNotifyConfig>(
                        stream: OrderNotifyService().watchConfig(widget.tenantId),
                        builder: (context, snap) {
                          final config = snap.data ?? OrderNotifyConfig.defaults();
                          if (!config.enabled) {
                            return const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text(
                                'WhatsApp order messages are off. Turn them on from Orders → WhatsApp templates.',
                                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                              ),
                            );
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                value: _sendWhatsApp,
                                onChanged: (v) => setState(() => _sendWhatsApp = v ?? true),
                                controlAffinity: ListTileControlAffinity.leading,
                                title: const Text(
                                  'Send WhatsApp confirm',
                                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                ),
                                subtitle: const Text(
                                  'Details + Confirm / Cancel buttons',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                              if (_sendWhatsApp) ...[
                                const Padding(
                                  padding: EdgeInsets.only(left: 12, bottom: 8),
                                  child: Text(
                                    'Send after',
                                    style: TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(left: 8),
                                  child: Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      for (final minutes in _delayOptions)
                                        ChoiceChip(
                                          label: Text(_delayLabel(minutes)),
                                          selected: _whatsAppDelayMinutes == minutes,
                                          onSelected: (_) => setState(() => _whatsAppDelayMinutes = minutes),
                                          selectedColor: AppColors.primary.withValues(alpha: 0.18),
                                          labelStyle: TextStyle(
                                            color: _whatsAppDelayMinutes == minutes
                                                ? AppColors.primary
                                                : AppColors.textSecondary,
                                            fontWeight: _whatsAppDelayMinutes == minutes
                                                ? FontWeight.w700
                                                : FontWeight.w500,
                                            fontSize: 12.5,
                                          ),
                                          side: BorderSide(
                                            color: _whatsAppDelayMinutes == minutes
                                                ? AppColors.primary
                                                : AppColors.surfaceBorder,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF22C55E),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(
                          widget.isEditing ? 'Save changes' : 'Create order',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;

  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _FormField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboardType;
  final int maxLines;

  const _FormField({
    required this.controller,
    required this.hint,
    this.keyboardType,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14.5),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.75), fontSize: 14),
        filled: true,
        fillColor: AppColors.background,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.surfaceBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.surfaceBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.2),
        ),
      ),
    );
  }
}
