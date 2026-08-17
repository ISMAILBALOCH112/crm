import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/courier_service.dart';
import '../services/order_notify_service.dart';
import '../services/order_service.dart';
import '../services/tenant_service.dart';
import '../theme/app_theme.dart';

class OrderNotifySettingsScreen extends StatelessWidget {
  final String tenantId;

  const OrderNotifySettingsScreen({super.key, required this.tenantId});

  static Future<void> open(BuildContext context, String tenantId) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => OrderNotifySettingsScreen(tenantId: tenantId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: TenantService().watchMembership(tenantId),
      builder: (context, memberSnap) {
        final isAdmin = memberSnap.data?.data()?['role'] == 'admin';
        return _Editor(tenantId: tenantId, isAdmin: isAdmin);
      },
    );
  }
}

class _Editor extends StatefulWidget {
  final String tenantId;
  final bool isAdmin;

  const _Editor({required this.tenantId, required this.isAdmin});

  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  final _notify = OrderNotifyService();
  final _courier = CourierService();
  final _controllers = <OrderStatus, TextEditingController>{};
  final _courierFields = <String, TextEditingController>{};
  OrderNotifyConfig? _config;
  bool _hydrated = false;
  bool _saving = false;
  Map<String, bool> _courierConfigured = {};
  String? _savingCourierId;

  @override
  void initState() {
    super.initState();
    for (final courier in kCouriers) {
      for (final field in courier.fields) {
        _courierFields[field.key] = TextEditingController();
      }
    }
    _courier.fetchConfigured(widget.tenantId).then((v) {
      if (mounted) setState(() => _courierConfigured = v);
    });
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final c in _courierFields.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _ensureControllers(OrderNotifyConfig config) {
    for (final status in OrderStatus.values) {
      _controllers.putIfAbsent(
        status,
        () => TextEditingController(text: config.templates[status] ?? ''),
      );
    }
    if (!_hydrated) {
      _config = config;
      for (final status in OrderStatus.values) {
        _controllers[status]!.text = config.templates[status] ?? '';
      }
      _hydrated = true;
    }
  }

  Future<void> _saveCourier(CourierKind courier) async {
    final fields = <String, String>{};
    for (final field in courier.fields) {
      final value = _courierFields[field.key]?.text.trim() ?? '';
      if (value.isNotEmpty) fields[field.key] = value;
    }
    setState(() => _savingCourierId = courier.id);
    try {
      await _courier.saveCredentials(tenantId: widget.tenantId, courierId: courier.id, fields: fields);
      setState(() => _courierConfigured = {..._courierConfigured, courier.id: true});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${courier.label} connected.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _savingCourierId = null);
    }
  }

  Future<void> _save() async {
    if (_config == null || !widget.isAdmin) return;
    setState(() => _saving = true);
    try {
      final templates = {
        for (final status in OrderStatus.values) status: _controllers[status]!.text.trim(),
      };
      await _notify.saveConfig(widget.tenantId, _config!.copyWith(templates: templates));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('WhatsApp templates saved.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text(
          'Order WhatsApp',
          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800),
        ),
      ),
      body: StreamBuilder<OrderNotifyConfig>(
        stream: _notify.watchConfig(widget.tenantId),
        builder: (context, snap) {
          final remote = snap.data ?? OrderNotifyConfig.defaults();
          _ensureControllers(remote);
          final config = _config ?? remote;

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              const Text(
                'New-order WhatsApp waits for the timer you pick on create (default 30 min). It includes full details and Confirm / Cancel buttons. Status-change messages still send immediately.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13.5),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                decoration: AppDecorations.card(radius: 16),
                child: Column(
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Enable WhatsApp order messages', style: TextStyle(fontWeight: FontWeight.w700)),
                      value: config.enabled,
                      activeThumbColor: AppColors.primary,
                      onChanged: widget.isAdmin
                          ? (v) => setState(() => _config = config.copyWith(enabled: v))
                          : null,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('On new order', style: TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: const Text('Timer on create form — default 30 min'),
                      value: config.sendOnCreate,
                      activeThumbColor: AppColors.primary,
                      onChanged: widget.isAdmin
                          ? (v) => setState(() => _config = config.copyWith(sendOnCreate: v))
                          : null,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('On status change', style: TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: const Text('Confirmed, shipped, delivered, cancelled'),
                      value: config.sendOnStatusChange,
                      activeThumbColor: AppColors.primary,
                      onChanged: widget.isAdmin
                          ? (v) => setState(() => _config = config.copyWith(sendOnStatusChange: v))
                          : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: AppDecorations.card(radius: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Couriers', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 4),
                    const Text(
                      'Connect APIs, then Book CN on an order. Select the same courier on the order card.',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
                    ),
                    const SizedBox(height: 8),
                    for (final courier in kCouriers)
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: Text(
                          courier.label,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
                        ),
                        subtitle: Text(
                          _courierConfigured[courier.id] == true ? 'Connected' : 'Not connected',
                          style: TextStyle(
                            color: _courierConfigured[courier.id] == true
                                ? const Color(0xFF059669)
                                : AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        children: [
                          for (final field in courier.fields) ...[
                            TextField(
                              enabled: widget.isAdmin,
                              controller: _courierFields[field.key],
                              obscureText: field.label.toLowerCase().contains('password') ||
                                  field.label.toLowerCase().contains('secret') ||
                                  field.label.toLowerCase().contains('token'),
                              decoration: InputDecoration(
                                labelText: field.optional ? '${field.label} (optional)' : field.label,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                isDense: true,
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          if (widget.isAdmin)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: FilledButton(
                                onPressed: _savingCourierId == courier.id ? null : () => _saveCourier(courier),
                                style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                                child: _savingCourierId == courier.id
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
                                    : Text('Save ${courier.label}'),
                              ),
                            ),
                          const SizedBox(height: 8),
                        ],
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Templates',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 4),
              const Text(
                '{name} {orderCode} {amount} {items} {city} {address} {tracking} {courier}',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
              ),
              const SizedBox(height: 12),
              for (final status in OrderStatus.values) ...[
                Text(
                  status == OrderStatus.pending
                      ? 'Pending — order create greeting (Confirm/Cancel buttons auto)'
                      : status.label,
                  style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 6),
                TextField(
                  enabled: widget.isAdmin,
                  controller: _controllers[status],
                  maxLines: 5,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppColors.surfaceSolid,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.surfaceBorder),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              if (widget.isAdmin)
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Save templates', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  ),
                )
              else
                const Text('Only admins can edit templates.', style: TextStyle(color: AppColors.textSecondary)),
            ],
          );
        },
      ),
    );
  }
}
