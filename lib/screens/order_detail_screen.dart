import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../services/chat_service.dart';
import '../../services/invoice_branding.dart';
import '../../services/invoice_service.dart';
import '../../services/order_notify_service.dart';
import '../../services/order_service.dart';
import '../../services/tenant_service.dart';
import '../../theme/app_theme.dart';
import 'parcel_payment_settings_screen.dart';
import 'tabs/chat_conversation_screen.dart';

class OrderDetailScreen extends StatelessWidget {
  final String tenantId;
  final String orderId;

  const OrderDetailScreen({super.key, required this.tenantId, required this.orderId});

  @override
  Widget build(BuildContext context) {
    final orderService = OrderService();
    final chatService = ChatService();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: StreamBuilder(
          stream: orderService.watchOrder(tenantId, orderId),
          builder: (context, snapshot) {
          final order = snapshot.hasData && snapshot.data!.exists
              ? CrmOrder.fromSnapshot(snapshot.data!)
              : null;
            return Text(
              order?.displayId ?? 'Order',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            );
          },
        ),
      ),
      body: StreamBuilder(
        stream: orderService.watchOrder(tenantId, orderId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primary));
          }
          if (!snapshot.data!.exists) {
            return const Center(child: Text('Order not found'));
          }

          final order = CrmOrder.fromSnapshot(snapshot.data!);

          return StreamBuilder(
            stream: TenantService().watchTenant(tenantId),
            builder: (context, tenantSnap) {
              final businessName = tenantSnap.data?.data()?['businessName'] as String?;
              final branding = InvoiceBranding.fromTenant(tenantSnap.data?.data());
              return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _StatusCard(
                status: order.status,
                onStatusChanged: (status) async {
                  await orderService.updateStatus(
                    tenantId: tenantId,
                    orderId: orderId,
                    status: status,
                  );
                  try {
                    final sent = await OrderNotifyService().notify(
                      tenantId: tenantId,
                      order: order.copyWith(status: status),
                      isCreate: false,
                    );
                    if (sent && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('WhatsApp sent: ${status.label}')),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Status updated, WhatsApp failed: $e'),
                          backgroundColor: AppColors.error,
                        ),
                      );
                    }
                  }
                },
              ),
              const SizedBox(height: 16),
              _PaymentCard(
                order: order,
                tenantId: tenantId,
                onPaymentChanged: (status, paidAmount) async {
                  await orderService.updatePayment(
                    tenantId: tenantId,
                    orderId: orderId,
                    paymentStatus: status,
                    totalAmount: order.totalAmount,
                    paidAmount: paidAmount,
                  );
                },
                onPaymentMethodChanged: (method) async {
                  await orderService.updatePaymentMethod(
                    tenantId: tenantId,
                    orderId: orderId,
                    paymentMethod: method,
                  );
                },
              ),
              const SizedBox(height: 16),
              _InvoiceButtons(
                tenantId: tenantId,
                order: order,
                businessName: businessName,
                branding: branding,
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: 'Customer',
                children: [
                  _InfoRow(label: 'Name', value: order.customerName),
                  _InfoRow(label: 'Phone', value: order.customerPhone),
                  if (order.city != null && order.city!.isNotEmpty)
                    _InfoRow(label: 'City', value: order.city!),
                  if (order.address != null && order.address!.isNotEmpty)
                    _InfoRow(label: 'Address', value: order.address!),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await chatService.ensureContact(
                          tenantId: tenantId,
                          phone: order.customerPhone,
                          name: order.customerName,
                        );
                        if (!context.mounted) return;
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ChatConversationScreen(
                              tenantId: tenantId,
                              phone: order.customerPhone,
                              contactName: order.customerName,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.chat_bubble_outline, size: 18),
                      label: const Text('Open chat'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: 'Items',
                children: [
                  for (final item in order.items) ...[
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.name,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Text(
                          '${item.qty} × Rs ${item.price.toStringAsFixed(0)}',
                          style: const TextStyle(color: AppColors.textSecondary),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Rs ${item.lineTotal.toStringAsFixed(0)}',
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    if (item != order.items.last) const Divider(height: 20, color: AppColors.surfaceBorder),
                  ],
                  const Divider(height: 24, color: AppColors.surfaceBorder),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Total',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      Text(
                        'Rs ${order.totalAmount.toStringAsFixed(0)}',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (order.notes != null && order.notes!.trim().isNotEmpty) ...[
                const SizedBox(height: 16),
                _SectionCard(
                  title: 'Notes',
                  children: [
                    Text(order.notes!, style: const TextStyle(color: AppColors.textPrimary, height: 1.4)),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              _SectionCard(
                title: 'Details',
                children: [
                  if (order.createdAt != null)
                    _InfoRow(
                      label: 'Created',
                      value: DateFormat('d MMM yyyy, h:mm a').format(order.createdAt!),
                    ),
                  if (order.updatedAt != null)
                    _InfoRow(
                      label: 'Updated',
                      value: DateFormat('d MMM yyyy, h:mm a').format(order.updatedAt!),
                    ),
                ],
              ),
            ],
              );
            },
          );
        },
      ),
    );
  }
}

class _InvoiceButtons extends StatefulWidget {
  final String tenantId;
  final CrmOrder order;
  final String? businessName;
  final InvoiceBranding branding;

  const _InvoiceButtons({
    required this.tenantId,
    required this.order,
    this.businessName,
    this.branding = const InvoiceBranding(),
  });

  @override
  State<_InvoiceButtons> createState() => _InvoiceButtonsState();
}

class _InvoiceButtonsState extends State<_InvoiceButtons> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _busy
                ? null
                : () => _run(
                      () => InvoiceService().share(
                        widget.order,
                        businessName: widget.businessName,
                        branding: widget.branding,
                      ),
                      'Invoice ready to share',
                    ),
            icon: const Icon(Icons.share_outlined, size: 18),
            label: const Text('Share PDF'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accentViolet,
              side: const BorderSide(color: AppColors.accentViolet),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton.icon(
            onPressed: _busy
                ? null
                : () => _run(
                      () => InvoiceService().sendWhatsApp(
                        tenantId: widget.tenantId,
                        order: widget.order,
                        businessName: widget.businessName,
                        branding: widget.branding,
                      ),
                      'Invoice sent on WhatsApp',
                    ),
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.send_outlined, size: 18),
            label: const Text('WhatsApp'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    );
  }
}

class _PaymentCard extends StatefulWidget {
  final CrmOrder order;
  final String tenantId;
  final Future<void> Function(PaymentStatus status, double? paidAmount) onPaymentChanged;
  final Future<void> Function(PaymentMethod method) onPaymentMethodChanged;

  const _PaymentCard({
    required this.order,
    required this.tenantId,
    required this.onPaymentChanged,
    required this.onPaymentMethodChanged,
  });

  @override
  State<_PaymentCard> createState() => _PaymentCardState();
}

class _PaymentCardState extends State<_PaymentCard> {
  late final TextEditingController _paidController;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _paidController = TextEditingController(
      text: widget.order.paidAmount > 0 ? widget.order.paidAmount.toStringAsFixed(0) : '',
    );
  }

  @override
  void didUpdateWidget(covariant _PaymentCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.order.paidAmount != widget.order.paidAmount ||
        oldWidget.order.paymentStatus != widget.order.paymentStatus) {
      final text = widget.order.paidAmount > 0 ? widget.order.paidAmount.toStringAsFixed(0) : '';
      if (_paidController.text != text) {
        _paidController.text = text;
      }
    }
  }

  @override
  void dispose() {
    _paidController.dispose();
    super.dispose();
  }

  Future<void> _apply(PaymentStatus status, {double? paidAmount}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onPaymentChanged(status, paidAmount);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _savePartial() async {
    final raw = _paidController.text.trim();
    final paid = double.tryParse(raw) ?? 0;
    await _apply(PaymentStatus.partial, paidAmount: paid);
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final status = order.paymentStatus;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppDecorations.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Payment',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: PaymentMethod.values.map((m) {
              final selected = order.paymentMethod == m;
              return ChoiceChip(
                label: Text(m.label),
                selected: selected,
                onSelected: selected || _busy
                    ? null
                    : (_) async {
                        setState(() => _busy = true);
                        try {
                          await widget.onPaymentMethodChanged(m);
                        } finally {
                          if (mounted) setState(() => _busy = false);
                        }
                      },
                selectedColor: AppColors.primary.withValues(alpha: 0.15),
                labelStyle: TextStyle(
                  color: selected ? AppColors.primary : AppColors.textSecondary,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 12.5,
                ),
                side: BorderSide(color: selected ? AppColors.primary : AppColors.surfaceBorder),
              );
            }).toList(),
          ),
          if (order.paymentMethod == PaymentMethod.jazzcash ||
              order.paymentMethod == PaymentMethod.easypaisa) ...[
            const SizedBox(height: 10),
            StreamBuilder<ParcelPaymentConfig>(
              stream: ParcelPaymentService().watch(widget.tenantId),
              builder: (context, snap) {
                final cfg = snap.data ?? const ParcelPaymentConfig();
                final isJazz = order.paymentMethod == PaymentMethod.jazzcash;
                final number = isJazz ? cfg.jazzcashNumber : cfg.easypaisaNumber;
                final name = isJazz ? cfg.jazzcashAccountName : cfg.easypaisaAccountName;
                if (number.isEmpty) {
                  return Text(
                    'Settings → Parcel payment mein ${order.paymentMethod.label} number add karein.',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5),
                  );
                }
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFBBF7D0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${order.paymentMethod.label} receive',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      SelectableText(
                        number,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, letterSpacing: 0.3),
                      ),
                      if (name.isNotEmpty)
                        Text(name, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: number));
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Number copied')),
                              );
                            }
                          },
                          icon: const Icon(Icons.copy, size: 16),
                          label: const Text('Copy'),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: PaymentStatus.values.map((s) {
              final selected = s == status;
              return ChoiceChip(
                label: Text(s.label),
                selected: selected,
                onSelected: selected || _busy
                    ? null
                    : (_) {
                        if (s == PaymentStatus.partial) {
                          _apply(PaymentStatus.partial, paidAmount: order.paidAmount > 0 ? order.paidAmount : order.totalAmount / 2);
                        } else {
                          _apply(s);
                        }
                      },
                selectedColor: _paymentColor(s).withValues(alpha: 0.15),
                labelStyle: TextStyle(
                  color: selected ? _paymentColor(s) : AppColors.textSecondary,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
                side: BorderSide(color: selected ? _paymentColor(s) : AppColors.surfaceBorder),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Paid: Rs ${order.paidAmount.toStringAsFixed(0)}',
                  style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                'Due: Rs ${order.balanceDue.toStringAsFixed(0)}',
                style: TextStyle(
                  color: order.balanceDue > 0 ? AppColors.error : const Color(0xFF059669),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (status == PaymentStatus.partial) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _paidController,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Amount paid',
                      prefixText: 'Rs ',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: _busy ? null : _savePartial,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Color _paymentColor(PaymentStatus status) {
    return switch (status) {
      PaymentStatus.unpaid => AppColors.error,
      PaymentStatus.partial => const Color(0xFFF59E0B),
      PaymentStatus.paid => const Color(0xFF059669),
    };
  }
}

class _StatusCard extends StatelessWidget {
  final OrderStatus status;
  final ValueChanged<OrderStatus> onStatusChanged;

  const _StatusCard({required this.status, required this.onStatusChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppDecorations.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Status',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: OrderStatus.values.map((s) {
              final selected = s == status;
              return ChoiceChip(
                label: Text(s.label),
                selected: selected,
                onSelected: selected ? null : (_) => onStatusChanged(s),
                selectedColor: AppColors.primary.withValues(alpha: 0.15),
                labelStyle: TextStyle(
                  color: selected ? AppColors.primary : AppColors.textSecondary,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
                side: BorderSide(color: selected ? AppColors.primary : AppColors.surfaceBorder),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SectionCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: AppDecorations.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
