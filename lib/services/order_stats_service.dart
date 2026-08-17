import '../services/order_service.dart';

enum StatsPeriod { today, week, month, custom }

class OrderStatsFilter {
  final StatsPeriod period;
  final DateTime rangeStart;
  final DateTime rangeEndExclusive;
  final String label;

  const OrderStatsFilter({
    required this.period,
    required this.rangeStart,
    required this.rangeEndExclusive,
    required this.label,
  });

  static OrderStatsFilter today() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    return OrderStatsFilter(
      period: StatsPeriod.today,
      rangeStart: start,
      rangeEndExclusive: start.add(const Duration(days: 1)),
      label: 'Today',
    );
  }

  static OrderStatsFilter week() {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final start = todayStart.subtract(Duration(days: now.weekday - 1));
    return OrderStatsFilter(
      period: StatsPeriod.week,
      rangeStart: start,
      rangeEndExclusive: todayStart.add(const Duration(days: 1)),
      label: 'This week',
    );
  }

  static OrderStatsFilter month() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    final todayStart = DateTime(now.year, now.month, now.day);
    return OrderStatsFilter(
      period: StatsPeriod.month,
      rangeStart: start,
      rangeEndExclusive: todayStart.add(const Duration(days: 1)),
      label: 'This month',
    );
  }

  static OrderStatsFilter custom(DateTime start, DateTime end) {
    final rangeStart = DateTime(start.year, start.month, start.day);
    final rangeEnd = DateTime(end.year, end.month, end.day);
    return OrderStatsFilter(
      period: StatsPeriod.custom,
      rangeStart: rangeStart,
      rangeEndExclusive: rangeEnd.add(const Duration(days: 1)),
      label: '${start.day}/${start.month} – ${end.day}/${end.month}',
    );
  }
}

class OrderStats {
  final int orderCount;
  final double revenue;
  final int pendingCount;
  final int confirmedCount;
  final int shippedCount;
  final int deliveredCount;
  final int returnedCount;
  final int cancelledCount;
  final int totalAllTime;
  final double revenueAllTime;
  final int deliveredCountAllTime;
  final double deliveredRevenueAllTime;
  final String periodLabel;

  const OrderStats({
    required this.orderCount,
    required this.revenue,
    required this.pendingCount,
    required this.confirmedCount,
    required this.shippedCount,
    required this.deliveredCount,
    required this.returnedCount,
    required this.cancelledCount,
    required this.totalAllTime,
    required this.revenueAllTime,
    required this.deliveredCountAllTime,
    required this.deliveredRevenueAllTime,
    required this.periodLabel,
  });

  static OrderStats fromOrders(List<CrmOrder> allOrders, OrderStatsFilter filter) {
    final inPeriod = allOrders.where((o) {
      final created = o.createdAt?.toLocal();
      if (created == null) return false;
      return !created.isBefore(filter.rangeStart) && created.isBefore(filter.rangeEndExclusive);
    }).toList();

    int pending = 0, confirmed = 0, shipped = 0, delivered = 0, returned = 0, cancelled = 0;
    double revenue = 0;

    for (final o in inPeriod) {
      if (o.status == OrderStatus.cancelled || o.status == OrderStatus.returned) {
        if (o.status == OrderStatus.cancelled) {
          cancelled++;
        } else {
          returned++;
        }
      } else {
        revenue += o.totalAmount;
        switch (o.status) {
          case OrderStatus.pending:
            pending++;
          case OrderStatus.confirmed:
            confirmed++;
          case OrderStatus.shipped:
            shipped++;
          case OrderStatus.delivered:
            delivered++;
          case OrderStatus.cancelled:
          case OrderStatus.returned:
            break;
        }
      }
    }

    final activeAllTime = allOrders.where(
      (o) => o.status != OrderStatus.cancelled && o.status != OrderStatus.returned,
    );
    final revenueAllTime = activeAllTime.fold<double>(0, (s, o) => s + o.totalAmount);

    final deliveredAllTime = allOrders.where((o) => o.status == OrderStatus.delivered);
    final deliveredRevenueAllTime =
        deliveredAllTime.fold<double>(0, (s, o) => s + o.totalAmount);

    return OrderStats(
      orderCount: inPeriod.length,
      revenue: revenue,
      pendingCount: pending,
      confirmedCount: confirmed,
      shippedCount: shipped,
      deliveredCount: delivered,
      returnedCount: returned,
      cancelledCount: cancelled,
      totalAllTime: allOrders.length,
      revenueAllTime: revenueAllTime,
      deliveredCountAllTime: deliveredAllTime.length,
      deliveredRevenueAllTime: deliveredRevenueAllTime,
      periodLabel: filter.label,
    );
  }
}

class StaffOrderStats {
  final String uid;
  final String name;
  final int orderCount;
  final double revenue;
  final int deliveredCount;

  const StaffOrderStats({
    required this.uid,
    required this.name,
    required this.orderCount,
    required this.revenue,
    required this.deliveredCount,
  });
}

class OrderStatsService {
  OrderStats compute(List<CrmOrder> orders, OrderStatsFilter filter) {
    return OrderStats.fromOrders(orders, filter);
  }

  List<StaffOrderStats> staffPerformance(
    List<CrmOrder> orders,
    OrderStatsFilter filter,
    Map<String, String> memberNames,
  ) {
    final inPeriod = orders.where((o) {
      final created = o.createdAt?.toLocal();
      if (created == null) return false;
      return !created.isBefore(filter.rangeStart) && created.isBefore(filter.rangeEndExclusive);
    });

    final map = <String, StaffOrderStats>{};
    for (final o in inPeriod) {
      final uid = (o.createdBy ?? '').trim();
      if (uid.isEmpty) continue;
      final prev = map[uid];
      final name = memberNames[uid]?.trim().isNotEmpty == true ? memberNames[uid]! : 'Staff';
      final addRevenue =
          (o.status != OrderStatus.cancelled && o.status != OrderStatus.returned) ? o.totalAmount : 0.0;
      final addDelivered = o.status == OrderStatus.delivered ? 1 : 0;
      map[uid] = StaffOrderStats(
        uid: uid,
        name: name,
        orderCount: (prev?.orderCount ?? 0) + 1,
        revenue: (prev?.revenue ?? 0) + addRevenue,
        deliveredCount: (prev?.deliveredCount ?? 0) + addDelivered,
      );
    }

    final list = map.values.toList()
      ..sort((a, b) {
        final byOrders = b.orderCount.compareTo(a.orderCount);
        if (byOrders != 0) return byOrders;
        return b.revenue.compareTo(a.revenue);
      });
    return list;
  }
}
