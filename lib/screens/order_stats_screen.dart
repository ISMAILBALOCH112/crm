import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/order_service.dart';
import '../services/order_stats_service.dart';
import '../services/tenant_service.dart';
import '../theme/app_theme.dart';
import '../widgets/stats_date_range_picker.dart';

class OrderStatsScreen extends StatelessWidget {
  const OrderStatsScreen({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const OrderStatsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0B1A),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: TenantService().watchUserProfile(),
        builder: (context, userSnap) {
          final tenantId = userSnap.data?.data()?['tenantId'] as String?;
          if (tenantId == null) return const SizedBox.shrink();

          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: TenantService().watchTenant(tenantId),
            builder: (context, tenantSnap) {
              final businessName = tenantSnap.data?.data()?['businessName'] as String? ?? 'Your Business';

              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: OrderService().watchOrders(tenantId),
                builder: (context, ordersSnap) {
                  if (!ordersSnap.hasData) {
                    return const Center(child: CircularProgressIndicator(color: Colors.white54));
                  }

                  final orders = ordersSnap.data!.docs.map(CrmOrder.fromDoc).toList();
                  return _StatsBody(tenantId: tenantId, businessName: businessName, orders: orders);
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _StatsBody extends StatefulWidget {
  final String tenantId;
  final String businessName;
  final List<CrmOrder> orders;

  const _StatsBody({required this.tenantId, required this.businessName, required this.orders});

  @override
  State<_StatsBody> createState() => _StatsBodyState();
}

class _StatsBodyState extends State<_StatsBody> {
  StatsPeriod _period = StatsPeriod.today;
  OrderStatsFilter _filter = OrderStatsFilter.today();
  DateTimeRange? _customRange;

  OrderStats get _stats => OrderStatsService().compute(widget.orders, _filter);

  String _money(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return v.toStringAsFixed(0);
  }

  void _setPeriod(StatsPeriod period) {
    setState(() {
      _period = period;
      _filter = switch (period) {
        StatsPeriod.today => OrderStatsFilter.today(),
        StatsPeriod.week => OrderStatsFilter.week(),
        StatsPeriod.month => OrderStatsFilter.month(),
        StatsPeriod.custom => _customRange != null
            ? OrderStatsFilter.custom(_customRange!.start, _customRange!.end)
            : OrderStatsFilter.today(),
      };
    });
  }

  Future<void> _pickCustomRange() async {
    final picked = await StatsDateRangePicker.show(
      context,
      initialRange: _customRange,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _customRange = picked;
      _period = StatsPeriod.custom;
      _filter = OrderStatsFilter.custom(picked.start, picked.end);
    });
  }

  @override
  Widget build(BuildContext context) {
    final stats = _stats;
    final topInset = MediaQuery.paddingOf(context).top;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(8, topInset + 4, 16, 0),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white70, size: 20),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF6B8AFF), Color(0xFF8B5CF6)]),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bar_chart_rounded, color: Colors.white, size: 16),
                      SizedBox(width: 4),
                      Text(
                        'Order Analytics',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 11.5,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _PeriodChip(
                    label: 'Today',
                    selected: _period == StatsPeriod.today,
                    onTap: () => _setPeriod(StatsPeriod.today),
                  ),
                  const SizedBox(width: 8),
                  _PeriodChip(
                    label: 'Weekly',
                    selected: _period == StatsPeriod.week,
                    onTap: () => _setPeriod(StatsPeriod.week),
                  ),
                  const SizedBox(width: 8),
                  _PeriodChip(
                    label: 'Monthly',
                    selected: _period == StatsPeriod.month,
                    onTap: () => _setPeriod(StatsPeriod.month),
                  ),
                  const SizedBox(width: 8),
                  _PeriodChip(
                    label: _period == StatsPeriod.custom ? _filter.label : 'Custom',
                    selected: _period == StatsPeriod.custom,
                    onTap: _pickCustomRange,
                    icon: Icons.calendar_month_rounded,
                  ),
                ],
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: _HeroCard(
              businessName: widget.businessName,
              revenue: stats.deliveredRevenueAllTime,
              deliveredCount: stats.deliveredCountAllTime,
              formatMoney: _money,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Performance',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.92),
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.05,
            ),
            delegate: SliverChildListDelegate([
              _VipStatCard(
                title: 'Orders',
                value: '${stats.orderCount}',
                subtitle: stats.periodLabel,
                icon: Icons.receipt_long_rounded,
                gradient: const [Color(0xFF6B8AFF), Color(0xFF4468E8)],
              ),
              _VipStatCard(
                title: 'Revenue',
                value: _money(stats.revenue),
                subtitle: 'PKR',
                icon: Icons.payments_outlined,
                gradient: const [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
              ),
              _VipStatCard(
                title: 'Pending',
                value: '${stats.pendingCount}',
                subtitle: 'Awaiting',
                icon: Icons.hourglass_top_rounded,
                gradient: const [Color(0xFFFFB37B), Color(0xFFFF7FA6)],
              ),
              _VipStatCard(
                title: 'Delivered',
                value: '${stats.deliveredCount}',
                subtitle: 'Completed',
                icon: Icons.check_circle_outline_rounded,
                gradient: const [Color(0xFF34D399), Color(0xFF059669)],
              ),
            ]),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Text(
              'Order pipeline',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.92),
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _PipelineCard(stats: stats),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Text(
              'Staff performance',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.92),
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: TenantService().watchMembers(widget.tenantId),
          builder: (context, memberSnap) {
            final names = <String, String>{};
            for (final doc in memberSnap.data?.docs ?? []) {
              final n = (doc.data()['name'] as String?)?.trim() ?? '';
              names[doc.id] = n.isEmpty ? 'Staff' : n;
            }
            final staff = OrderStatsService().staffPerformance(widget.orders, _filter, names);
            if (staff.isEmpty) {
              return SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  child: Text(
                    'No staff orders in this period yet.',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 13),
                  ),
                ),
              );
            }
            return SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final row = staff[index];
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: const Color(0xFF6B8AFF).withValues(alpha: 0.25),
                            child: Text(
                              row.name.isNotEmpty ? row.name[0].toUpperCase() : '?',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(row.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                                Text(
                                  '${row.orderCount} orders · ${row.deliveredCount} delivered',
                                  style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            _money(row.revenue),
                            style: const TextStyle(color: Color(0xFF34D399), fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  );
                },
                childCount: staff.length,
              ),
            );
          },
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            child: _TotalBanner(
              deliveredCount: stats.deliveredCountAllTime,
              deliveredRevenue: stats.deliveredRevenueAllTime,
              formatMoney: _money,
            ),
          ),
        ),
      ],
    );
  }
}

class _PeriodChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  const _PeriodChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(colors: [Color(0xFF6B8AFF), Color(0xFF8B5CF6)])
              : null,
          color: selected ? null : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? Colors.transparent : Colors.white.withValues(alpha: 0.15)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: selected ? Colors.white : Colors.white60),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white70,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  final String businessName;
  final double revenue;
  final int deliveredCount;
  final String Function(double) formatMoney;

  const _HeroCard({
    required this.businessName,
    required this.revenue,
    required this.deliveredCount,
    required this.formatMoney,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A1530), Color(0xFF2D1B69), Color(0xFF5B7FFF)],
          stops: [0.0, 0.55, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.45),
            blurRadius: 32,
            offset: const Offset(0, 14),
          ),
        ],
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            businessName,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'All-time delivered income',
            style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          ShaderMask(
            shaderCallback: (b) => const LinearGradient(
              colors: [Color(0xFFFFE082), Color(0xFFFFD54F), Color(0xFFFFAB40)],
            ).createShader(b),
            child: Text(
              'PKR ${formatMoney(revenue)}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.w900,
                letterSpacing: -1,
                height: 1.05,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _HeroChip(icon: Icons.local_shipping_outlined, label: '$deliveredCount delivered'),
              _HeroChip(icon: Icons.sync_rounded, label: 'Live data'),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _HeroChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white70, size: 14),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _VipStatCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final List<Color> gradient;

  const _VipStatCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: gradient),
        boxShadow: [
          BoxShadow(
            color: gradient.last.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: Colors.white.withValues(alpha: 0.9), size: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.95),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PipelineCard extends StatelessWidget {
  final OrderStats stats;

  const _PipelineCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final total = stats.orderCount > 0 ? stats.orderCount : 1;
    final rows = [
      _PipelineRow('New', stats.pendingCount, const Color(0xFF5B7FFF)),
      _PipelineRow('Confirmed', stats.confirmedCount, const Color(0xFF22C55E)),
      _PipelineRow('Shipped', stats.shippedCount, const Color(0xFF8B5CF6)),
      _PipelineRow('Delivered', stats.deliveredCount, const Color(0xFF059669)),
      _PipelineRow('Returned', stats.returnedCount, const Color(0xFFF59E0B)),
      _PipelineRow('Cancelled', stats.cancelledCount, const Color(0xFFEF4444)),
    ];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          for (final row in rows) ...[
            _PipelineBar(row: row, total: total),
            if (row != rows.last) const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }
}

class _PipelineRow {
  final String label;
  final int count;
  final Color color;

  const _PipelineRow(this.label, this.count, this.color);
}

class _PipelineBar extends StatelessWidget {
  final _PipelineRow row;
  final int total;

  const _PipelineBar({required this.row, required this.total});

  @override
  Widget build(BuildContext context) {
    final fraction = (row.count / total).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(row.label, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13, fontWeight: FontWeight.w600)),
            const Spacer(),
            Text('${row.count}', style: TextStyle(color: row.color, fontWeight: FontWeight.w800, fontSize: 14)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: fraction == 0 ? 0.02 : fraction,
            minHeight: 8,
            backgroundColor: Colors.white.withValues(alpha: 0.08),
            color: row.color,
          ),
        ),
      ],
    );
  }
}

class _TotalBanner extends StatelessWidget {
  final int deliveredCount;
  final double deliveredRevenue;
  final String Function(double) formatMoney;

  const _TotalBanner({
    required this.deliveredCount,
    required this.deliveredRevenue,
    required this.formatMoney,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.accent.withValues(alpha: 0.25),
            AppColors.primary.withValues(alpha: 0.2),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Delivered parcels (all time)', style: TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 4),
                Text(
                  '$deliveredCount parcels · PKR ${formatMoney(deliveredRevenue)}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ],
            ),
          ),
          Icon(Icons.insights_rounded, color: AppColors.accent.withValues(alpha: 0.9), size: 32),
        ],
      ),
    );
  }
}
