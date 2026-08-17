import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/courier_service.dart';
import '../../services/invoice_branding.dart';
import '../../services/invoice_service.dart';
import '../../services/order_notify_service.dart';
import '../../services/order_service.dart';
import '../../services/subscription_service.dart';
import '../../services/tenant_service.dart';
import '../../services/tenant_roles.dart';
import '../../theme/app_theme.dart';
import '../create_order_screen.dart';
import '../catalog_screen.dart';
import '../order_detail_screen.dart';
import '../order_notify_settings_screen.dart';

enum _OrderFilter { all, pending, confirmed, shipped, delivered, returned, cancelled, unpaid, partial, paid }

class OrdersTab extends StatefulWidget {
  const OrdersTab({super.key});

  @override
  State<OrdersTab> createState() => _OrdersTabState();
}

class _OrdersTabState extends State<OrdersTab> {
  final _searchController = TextEditingController();
  final _orderService = OrderService();
  _OrderFilter _selectedFilter = _OrderFilter.all;
  final _selectedIds = <String>{};
  bool _syncingAll = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSelect(String orderId, bool? value) {
    setState(() {
      if (value == true) {
        _selectedIds.add(orderId);
      } else {
        _selectedIds.remove(orderId);
      }
    });
  }

  Future<void> _confirmDelete(String tenantId, List<String> ids) async {
    if (ids.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete orders?'),
        content: Text(
          ids.length == 1
              ? 'This order will be permanently deleted.'
              : 'Delete ${ids.length} selected orders?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      await _orderService.deleteOrders(tenantId: tenantId, orderIds: ids);
      if (!mounted) return;
      setState(() => _selectedIds.removeWhere((id) => ids.contains(id)));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted ${ids.length} order(s)'), duration: const Duration(seconds: 2)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e'), backgroundColor: AppColors.error),
      );
    }
  }

  Future<void> _openEditOrder(String tenantId, CrmOrder order) async {
    final updated = await CreateOrderScreen.showEdit(context, tenantId, order);
    if (updated == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Order updated'), duration: Duration(seconds: 2)),
      );
    }
  }

  Future<void> _openCreateOrder(String tenantId) async {
    final billing = await SubscriptionService().fetchBilling(tenantId);
    if (!billing.writeAllowed) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(SubscriptionService.readOnlyMessage)),
      );
      return;
    }
    final result = await CreateOrderScreen.show(context, tenantId);
    if (result == null || !mounted) return;
    if (result.whatsAppScheduled) {
      final delay = result.delayMinutes;
      final when = delay <= 0
          ? 'abhi'
          : delay == 1
              ? '1 min baad'
              : delay == 60
                  ? '1 hour baad'
                  : '$delay min baad';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Order created · WhatsApp Confirm/Cancel $when jayega'),
          duration: const Duration(seconds: 3),
        ),
      );
    } else if (result.whatsAppError.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Order created, but WhatsApp failed: ${result.whatsAppError}'),
          backgroundColor: AppColors.error,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Order created'), duration: Duration(seconds: 2)),
      );
    }
  }

  Future<void> _openOrder(String tenantId, CrmOrder order) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OrderDetailScreen(tenantId: tenantId, orderId: order.id),
      ),
    );
  }

  Future<void> _syncAllCns(String tenantId) async {
    if (_syncingAll) return;
    setState(() => _syncingAll = true);
    try {
      final summary = await CourierService().syncAll(tenantId);
      if (!mounted) return;
      final checked = summary['checked'] ?? 0;
      final updated = summary['updated'] ?? 0;
      final delivered = summary['delivered'] ?? 0;
      final returned = summary['returned'] ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Synced $checked CNs · $updated updated · $delivered delivered · $returned returned'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _syncingAll = false);
    }
  }

  List<CrmOrder> _filterOrders(List<CrmOrder> all) {
    var orders = all;
    final query = _searchController.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      orders = orders.where((o) {
        return o.displayId.toLowerCase().contains(query) ||
            o.customerName.toLowerCase().contains(query) ||
            o.customerPhone.contains(query) ||
            (o.trackingNumber?.contains(query) ?? false);
      }).toList();
    }
    if (_selectedFilter != _OrderFilter.all) {
      orders = orders.where((o) => _matchesFilter(o, _selectedFilter)).toList();
    }
    return orders;
  }

  bool _matchesFilter(CrmOrder o, _OrderFilter filter) {
    return switch (filter) {
      _OrderFilter.all => true,
      _OrderFilter.unpaid => o.paymentStatus == PaymentStatus.unpaid,
      _OrderFilter.partial => o.paymentStatus == PaymentStatus.partial,
      _OrderFilter.paid => o.paymentStatus == PaymentStatus.paid,
      _ => o.status == OrderStatusX.fromString(filter.name),
    };
  }

  int _countFor(List<CrmOrder> all, _OrderFilter filter) {
    if (filter == _OrderFilter.all) return all.length;
    return all.where((o) => _matchesFilter(o, filter)).length;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: TenantService().watchUserProfile(),
      builder: (context, userSnapshot) {
        final tenantId = userSnapshot.data?.data()?['tenantId'] as String?;
        if (tenantId == null) return const SizedBox.shrink();

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: TenantService().watchMembership(tenantId),
          builder: (context, memberSnap) {
            final isAdmin = TenantRoles.isAdmin(memberSnap.data?.data()?['role'] as String?);
            final role = isAdmin ? TenantRoles.admin : TenantRoles.agent;

            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: TenantService().watchTenant(tenantId),
          builder: (context, tenantSnapshot) {
            final businessName = tenantSnapshot.data?.data()?['businessName'] as String?;
            final branding = InvoiceBranding.fromTenant(tenantSnapshot.data?.data());

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ShaderMask(
                                  shaderCallback: (bounds) => AppColors.primaryGradient.createShader(bounds),
                                  child: const Text(
                                    'Orders',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 26,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                                  stream: _orderService.watchOrders(tenantId),
                                  builder: (context, snap) {
                                    final total = snap.data?.docs.length ?? 0;
                                    final label = businessName != null && businessName.isNotEmpty
                                        ? '$total total · $businessName'
                                        : '$total total · track orders per business';
                                    return Text(
                                      label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 12.5,
                                        height: 1.3,
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Catalog',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => CatalogScreen.open(context, tenantId, canManage: isAdmin),
                            icon: const Icon(Icons.inventory_2_outlined, color: AppColors.primary),
                          ),
                          if (TenantRoles.canManageOrderTemplates(role))
                            IconButton(
                              tooltip: 'WhatsApp templates',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => OrderNotifySettingsScreen.open(context, tenantId),
                              icon: const Icon(Icons.sms_outlined, color: AppColors.primary),
                            ),
                          IconButton(
                            tooltip: 'Sync all CNs',
                            visualDensity: VisualDensity.compact,
                            onPressed: _syncingAll ? null : () => _syncAllCns(tenantId),
                            icon: _syncingAll
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                                  )
                                : const Icon(Icons.sync_rounded, color: AppColors.primary),
                          ),
                          FilledButton.icon(
                            onPressed: () => _openCreateOrder(tenantId),
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('New order'),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ],
                      ),
                      if (_selectedIds.isNotEmpty && TenantRoles.canDeleteOrders(role)) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () => _confirmDelete(tenantId, _selectedIds.toList()),
                            icon: const Icon(Icons.delete_outline, size: 18),
                            label: Text('Delete ${_selectedIds.length} selected'),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.error,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.surfaceSolid,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.surfaceBorder),
                      boxShadow: AppColors.cardShadow(AppColors.accent),
                    ),
                    padding: const EdgeInsets.fromLTRB(12, 4, 6, 4),
                    child: Row(
                      children: [
                        const Icon(Icons.search_rounded, color: AppColors.textSecondary, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            onSubmitted: (_) => setState(() {}),
                            decoration: InputDecoration(
                              hintText: 'Search order #, phone, tracking…',
                              hintStyle: TextStyle(
                                color: AppColors.textSecondary.withValues(alpha: 0.85),
                                fontSize: 14,
                              ),
                              border: InputBorder.none,
                              isCollapsed: true,
                              contentPadding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                            style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                          ),
                        ),
                        TextButton(
                          onPressed: () => setState(() {}),
                          child: const Text('Search', style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _orderService.watchOrders(tenantId),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'Could not load orders.\n${snapshot.error}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: AppColors.textSecondary),
                            ),
                          ),
                        );
                      }
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator(color: AppColors.primary));
                      }

                      final allOrders = snapshot.data!.docs.map(CrmOrder.fromDoc).toList();
                      final orders = _filterOrders(allOrders);
                      final hasFilter = _searchController.text.trim().isNotEmpty || _selectedFilter != _OrderFilter.all;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            height: 38,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: _OrderFilter.values.length,
                              separatorBuilder: (_, _) => const SizedBox(width: 8),
                              itemBuilder: (context, index) {
                                final filter = _OrderFilter.values[index];
                                final isSelected = filter == _selectedFilter;
                                final count = _countFor(allOrders, filter);
                                final label = switch (filter) {
                                  _OrderFilter.all => 'All ($count)',
                                  _OrderFilter.pending => 'New ($count)',
                                  _OrderFilter.confirmed => 'Confirmed ($count)',
                                  _OrderFilter.shipped => 'Shipped ($count)',
                                  _OrderFilter.delivered => 'Delivered ($count)',
                                  _OrderFilter.returned => 'Returned ($count)',
                                  _OrderFilter.cancelled => 'Cancelled ($count)',
                                  _OrderFilter.unpaid => 'Unpaid ($count)',
                                  _OrderFilter.partial => 'Partial ($count)',
                                  _OrderFilter.paid => 'Paid ($count)',
                                };
                                return GestureDetector(
                                  onTap: () => setState(() => _selectedFilter = filter),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 180),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                    decoration: BoxDecoration(
                                      gradient: isSelected ? AppColors.primaryGradient : null,
                                      color: isSelected ? null : AppColors.surfaceSolid,
                                      borderRadius: BorderRadius.circular(18),
                                      border: isSelected ? null : Border.all(color: AppColors.surfaceBorder),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      label,
                                      style: TextStyle(
                                        color: isSelected ? Colors.white : AppColors.textSecondary,
                                        fontSize: 12.5,
                                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 10),
                          Expanded(
                            child: orders.isEmpty
                                ? Center(
                                    child: Container(
                                      margin: const EdgeInsets.symmetric(horizontal: 16),
                                      padding: const EdgeInsets.all(24),
                                      decoration: AppDecorations.card(radius: 16),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            hasFilter
                                                ? 'No orders match your search or filter.'
                                                : 'No orders yet. Tap New order to create your first order.',
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              color: AppColors.textSecondary,
                                              fontSize: 14.5,
                                              height: 1.45,
                                            ),
                                          ),
                                          if (!hasFilter) ...[
                                            const SizedBox(height: 16),
                                            FilledButton.icon(
                                              onPressed: () => _openCreateOrder(tenantId),
                                              icon: const Icon(Icons.add),
                                              label: const Text('Create order'),
                                              style: FilledButton.styleFrom(
                                                backgroundColor: AppColors.primary,
                                                foregroundColor: Colors.white,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  )
                                : ListView.builder(
                                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                    itemCount: orders.length,
                                    itemBuilder: (context, index) {
                                      final order = orders[index];
                                      return Padding(
                                        padding: const EdgeInsets.only(bottom: 12),
                                        child: _OrderCard(
                                          tenantId: tenantId,
                                          businessName: businessName,
                                          branding: branding,
                                          order: order,
                                          orderService: _orderService,
                                          selected: _selectedIds.contains(order.id),
                                          canDelete: TenantRoles.canDeleteOrders(role),
                                          onSelected: (v) => _toggleSelect(order.id, v),
                                          onEdit: () => _openEditOrder(tenantId, order),
                                          onDelete: () => _confirmDelete(tenantId, [order.id]),
                                          onTap: () => _openOrder(tenantId, order),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
          },
        );
      },
    );
  }
}

class _OrderCard extends StatefulWidget {
  final String tenantId;
  final String? businessName;
  final InvoiceBranding branding;
  final CrmOrder order;
  final OrderService orderService;
  final bool selected;
  final bool canDelete;
  final ValueChanged<bool?> onSelected;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onTap;

  const _OrderCard({
    required this.tenantId,
    this.businessName,
    this.branding = const InvoiceBranding(),
    required this.order,
    required this.orderService,
    required this.selected,
    this.canDelete = true,
    required this.onSelected,
    required this.onEdit,
    required this.onDelete,
    required this.onTap,
  });

  @override
  State<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<_OrderCard> {
  late final TextEditingController _trackingController;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _trackingController = TextEditingController(text: widget.order.trackingNumber ?? '');
  }

  @override
  void didUpdateWidget(covariant _OrderCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.order.trackingNumber != widget.order.trackingNumber) {
      _trackingController.text = widget.order.trackingNumber ?? '';
    }
  }

  @override
  void dispose() {
    _trackingController.dispose();
    super.dispose();
  }

  Future<void> _bookCn() async {
    final order = widget.order;
    if ((order.city == null || order.city!.trim().isEmpty) ||
        (order.address == null || order.address!.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('City and address are required to book a CN.')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final tracking = await CourierService().bookCn(
        tenantId: widget.tenantId,
        orderId: order.id,
        courier: order.courier ?? 'PostEx',
      );
      if (mounted) {
        _trackingController.text = tracking;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${order.courier ?? 'Courier'} CN booked: $tracking')),
        );
      }
      try {
        await OrderNotifyService().notify(
          tenantId: widget.tenantId,
          order: order.copyWith(
            status: OrderStatus.shipped,
            trackingNumber: tracking,
            courier: order.courier ?? 'PostEx',
          ),
          isCreate: false,
        );
      } catch (_) {}
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

  Future<void> _syncCn() async {
    final order = widget.order;
    setState(() => _busy = true);
    try {
      final result = await CourierService().syncOne(tenantId: widget.tenantId, orderId: order.id);
      if (!mounted) return;
      final status = result['status'] as String? ?? order.status.name;
      final courierStatus = result['courierStatus'] as String?;
      final changed = result['statusChanged'] == true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            changed
                ? 'CN updated: ${status.toUpperCase()}${courierStatus == null || courierStatus.isEmpty ? '' : ' · $courierStatus'}'
                : 'CN status: ${courierStatus ?? status}',
          ),
        ),
      );
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

  Future<void> _setPayment(PaymentStatus status) async {
    setState(() => _busy = true);
    try {
      await widget.orderService.updatePayment(
        tenantId: widget.tenantId,
        orderId: widget.order.id,
        paymentStatus: status,
        totalAmount: widget.order.totalAmount,
        paidAmount: status == PaymentStatus.partial ? widget.order.paidAmount : null,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Payment: ${status.label}'), duration: const Duration(seconds: 2)),
        );
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

  Future<void> _setStatus(OrderStatus status) async {
    setState(() => _busy = true);
    try {
      await widget.orderService.updateStatus(
        tenantId: widget.tenantId,
        orderId: widget.order.id,
        status: status,
      );
      try {
        final sent = await OrderNotifyService().notify(
          tenantId: widget.tenantId,
          order: widget.order.copyWith(status: status),
          isCreate: false,
        );
        if (sent && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('WhatsApp sent: ${status.label}'), duration: const Duration(seconds: 2)),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Status updated, WhatsApp failed: $e'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareInvoice() async {
    setState(() => _busy = true);
    try {
      await InvoiceService().share(
        widget.order,
        businessName: widget.businessName,
        branding: widget.branding,
      );
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

  Future<void> _sendInvoiceWhatsApp() async {
    setState(() => _busy = true);
    try {
      await InvoiceService().sendWhatsApp(
        tenantId: widget.tenantId,
        order: widget.order,
        businessName: widget.businessName,
        branding: widget.branding,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invoice sent on WhatsApp')),
        );
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

  Future<void> _saveTracking() async {
    final value = _trackingController.text.trim();
    if (value.isEmpty) return;
    final order = widget.order;
    final firstCn = order.trackingNumber == null || order.trackingNumber!.trim().isEmpty;
    final shouldShip = firstCn &&
        (order.status == OrderStatus.pending || order.status == OrderStatus.confirmed);
    setState(() => _busy = true);
    try {
      await widget.orderService.updateTracking(
        tenantId: widget.tenantId,
        orderId: order.id,
        trackingNumber: value,
        courier: order.courier ?? 'Manual',
        status: shouldShip ? OrderStatus.shipped : null,
      );
      var message = 'Tracking saved';
      if (firstCn) {
        try {
          final sent = await OrderNotifyService().notify(
            tenantId: widget.tenantId,
            order: order.copyWith(
              status: shouldShip ? OrderStatus.shipped : order.status,
              trackingNumber: value,
            ),
            isCreate: false,
          );
          if (sent) message = 'Tracking saved · WhatsApp shipped message sent';
        } catch (_) {
          message = 'Tracking saved, WhatsApp failed';
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final timeLabel = order.createdAt != null ? DateFormat('h:mm a').format(order.createdAt!) : '';

    return Material(
      color: widget.selected ? AppColors.primary.withValues(alpha: 0.04) : AppColors.surfaceSolid,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: widget.onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: widget.selected ? AppColors.primary.withValues(alpha: 0.45) : AppColors.surfaceBorder,
            ),
            boxShadow: AppColors.cardShadow(AppColors.accent),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2, right: 8),
                    child: widget.canDelete
                        ? Checkbox(
                            value: widget.selected,
                            onChanged: widget.onSelected,
                            activeColor: AppColors.primary,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          )
                        : const SizedBox(width: 8),
                  ),
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          order.displayId,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 14.5,
                          ),
                        ),
                        _StatusBadge(status: order.status),
                        _PaymentBadge(status: order.paymentStatus),
                        if (order.paymentMethod != PaymentMethod.cod)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: const Color(0xFFBFDBFE)),
                            ),
                            child: Text(
                              order.paymentMethod.label,
                              style: const TextStyle(
                                color: Color(0xFF1D4ED8),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'PKR ${order.totalAmount.toStringAsFixed(0)}',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      if (timeLabel.isNotEmpty)
                        Text(timeLabel, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          order.customerName,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          order.customerPhone,
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, color: AppColors.textSecondary, size: 22),
                    padding: EdgeInsets.zero,
                    onSelected: (value) {
                      switch (value) {
                        case 'edit':
                          widget.onEdit();
                        case 'invoice':
                          _shareInvoice();
                        case 'invoice_wa':
                          _sendInvoiceWhatsApp();
                        case 'mark_paid':
                          _setPayment(PaymentStatus.paid);
                        case 'mark_unpaid':
                          _setPayment(PaymentStatus.unpaid);
                        case 'delete':
                          if (widget.canDelete) widget.onDelete();
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'edit', child: Text('Edit order')),
                      const PopupMenuItem(value: 'invoice', child: Text('Share invoice')),
                      const PopupMenuItem(value: 'invoice_wa', child: Text('Send invoice on WhatsApp')),
                      if (order.paymentStatus != PaymentStatus.paid)
                        const PopupMenuItem(value: 'mark_paid', child: Text('Mark paid')),
                      if (order.paymentStatus != PaymentStatus.unpaid)
                        const PopupMenuItem(value: 'mark_unpaid', child: Text('Mark unpaid')),
                      if (widget.canDelete)
                        const PopupMenuItem(value: 'delete', child: Text('Delete order')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Items: ${order.itemsSummary}',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              if (order.notes != null && order.notes!.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  order.notes!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.primary.withValues(alpha: 0.85), fontSize: 12.5),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.surfaceBorder),
                        borderRadius: BorderRadius.circular(10),
                        color: AppColors.background,
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: order.courier ?? 'Manual',
                          isExpanded: true,
                          items: const [
                            DropdownMenuItem(value: 'Manual', child: Text('Manual')),
                            DropdownMenuItem(value: 'PostEx', child: Text('PostEx')),
                            DropdownMenuItem(value: 'Leopard', child: Text('Leopard')),
                            DropdownMenuItem(value: 'TCS', child: Text('TCS')),
                            DropdownMenuItem(value: 'Trax', child: Text('Trax')),
                            DropdownMenuItem(value: 'BlueEx', child: Text('BlueEx')),
                            DropdownMenuItem(value: 'CallCourier', child: Text('Call Courier')),
                            DropdownMenuItem(value: 'M&P', child: Text('M&P')),
                            DropdownMenuItem(value: 'Rider', child: Text('Rider')),
                            DropdownMenuItem(value: 'Daewoo', child: Text('Daewoo FastEx')),
                          ],
                          onChanged: _busy
                              ? null
                              : (v) {
                                  if (v == null) return;
                                  widget.orderService.updateTracking(
                                    tenantId: widget.tenantId,
                                    orderId: order.id,
                                    trackingNumber: _trackingController.text.trim(),
                                    courier: v,
                                  );
                                },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _trackingController,
                      decoration: InputDecoration(
                        hintText: 'Tracking / CN #',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      style: const TextStyle(fontSize: 13),
                      onTapOutside: (_) => FocusScope.of(context).unfocus(),
                    ),
                  ),
                ],
              ),
              if (order.courierStatus != null && order.courierStatus!.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Courier: ${order.courierStatus}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _busy ? null : _saveTracking,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    child: const Text('Save tracking', style: TextStyle(fontSize: 12.5)),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _shareInvoice,
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                    label: const Text('Invoice', style: TextStyle(fontSize: 12.5)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.accentViolet,
                      side: const BorderSide(color: AppColors.accentViolet),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                  if ((order.trackingNumber == null || order.trackingNumber!.trim().isEmpty) &&
                      order.status != OrderStatus.cancelled &&
                      order.status != OrderStatus.returned &&
                      order.courier != null &&
                      order.courier != 'Manual')
                    FilledButton.icon(
                      onPressed: _busy ? null : _bookCn,
                      icon: const Icon(Icons.local_shipping_outlined, size: 16),
                      label: Text('Book ${order.courier}', style: const TextStyle(fontSize: 12.5)),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF0F766E),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ),
                  if (order.canSyncCn)
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _syncCn,
                      icon: const Icon(Icons.sync_rounded, size: 16),
                      label: const Text('Sync CN', style: TextStyle(fontSize: 12.5)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF0F766E),
                        side: const BorderSide(color: Color(0xFF0F766E)),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ),
                  if (order.status == OrderStatus.pending)
                    FilledButton(
                      onPressed: _busy ? null : () => _setStatus(OrderStatus.confirmed),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF22C55E),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      child: const Text('Mark CONFIRMED', style: TextStyle(fontSize: 12.5)),
                    ),
                  if (order.status != OrderStatus.cancelled &&
                      order.status != OrderStatus.delivered &&
                      order.status != OrderStatus.returned)
                    OutlinedButton(
                      onPressed: _busy ? null : () => _setStatus(OrderStatus.cancelled),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: const BorderSide(color: AppColors.error),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      child: const Text('Cancel', style: TextStyle(fontSize: 12.5)),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final OrderStatus status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      OrderStatus.pending => AppColors.primary,
      OrderStatus.confirmed => const Color(0xFF22C55E),
      OrderStatus.shipped => AppColors.accentViolet,
      OrderStatus.delivered => const Color(0xFF059669),
      OrderStatus.returned => const Color(0xFFF59E0B),
      OrderStatus.cancelled => AppColors.error,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        status.badgeLabel,
        style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.3),
      ),
    );
  }
}

class _PaymentBadge extends StatelessWidget {
  final PaymentStatus status;

  const _PaymentBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      PaymentStatus.unpaid => AppColors.error,
      PaymentStatus.partial => const Color(0xFFF59E0B),
      PaymentStatus.paid => const Color(0xFF059669),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        status.badgeLabel,
        style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.3),
      ),
    );
  }
}
