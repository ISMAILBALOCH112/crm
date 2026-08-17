import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_theme.dart';

/// Full month-grid calendar for picking a start/end date range.
class StatsDateRangePicker {
  StatsDateRangePicker._();

  static Future<DateTimeRange?> show(
    BuildContext context, {
    DateTimeRange? initialRange,
  }) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return showModalBottomSheet<DateTimeRange>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _CalendarSheet(
        firstDate: DateTime(now.year - 2),
        lastDate: today,
        initialStart: initialRange?.start,
        initialEnd: initialRange?.end,
      ),
    );
  }
}

class _CalendarSheet extends StatefulWidget {
  final DateTime firstDate;
  final DateTime lastDate;
  final DateTime? initialStart;
  final DateTime? initialEnd;

  const _CalendarSheet({
    required this.firstDate,
    required this.lastDate,
    this.initialStart,
    this.initialEnd,
  });

  @override
  State<_CalendarSheet> createState() => _CalendarSheetState();
}

class _CalendarSheetState extends State<_CalendarSheet> {
  late DateTime _focusedMonth;
  DateTime? _start;
  DateTime? _end;

  @override
  void initState() {
    super.initState();
    _start = widget.initialStart != null ? _dayOnly(widget.initialStart!) : null;
    _end = widget.initialEnd != null ? _dayOnly(widget.initialEnd!) : null;
    _focusedMonth = DateTime(
      (_end ?? _start ?? widget.lastDate).year,
      (_end ?? _start ?? widget.lastDate).month,
    );
  }

  DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _inRange(DateTime day) {
    if (_start == null || _end == null) return false;
    final s = _start!.isBefore(_end!) ? _start! : _end!;
    final e = _start!.isBefore(_end!) ? _end! : _start!;
    return !day.isBefore(s) && !day.isAfter(e);
  }

  void _onDayTap(DateTime day) {
    if (day.isBefore(widget.firstDate) || day.isAfter(widget.lastDate)) return;

    setState(() {
      if (_start == null || (_start != null && _end != null)) {
        _start = day;
        _end = null;
      } else {
        if (day.isBefore(_start!)) {
          _end = _start;
          _start = day;
        } else {
          _end = day;
        }
      }
    });
  }

  void _prevMonth() {
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1);
    });
  }

  void _nextMonth() {
    final next = DateTime(_focusedMonth.year, _focusedMonth.month + 1);
    if (DateTime(next.year, next.month, 1).isAfter(widget.lastDate)) return;
    setState(() => _focusedMonth = next);
  }

  List<DateTime?> _buildGrid() {
    final firstOfMonth = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final daysInMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0).day;
    // Monday = 1 … Sunday = 7
    final leading = firstOfMonth.weekday - 1;

    final cells = <DateTime?>[];
    for (var i = 0; i < leading; i++) {
      cells.add(null);
    }
    for (var d = 1; d <= daysInMonth; d++) {
      cells.add(DateTime(_focusedMonth.year, _focusedMonth.month, d));
    }
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    return cells;
  }

  @override
  Widget build(BuildContext context) {
    final monthLabel = DateFormat('MMMM yyyy').format(_focusedMonth);
    final canNext = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 1)
        .isBefore(DateTime(widget.lastDate.year, widget.lastDate.month + 1, 1));
    final canPrev = DateTime(_focusedMonth.year, _focusedMonth.month, 1)
        .isAfter(DateTime(widget.firstDate.year, widget.firstDate.month, 1));

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1A1530),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Select date range',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _rangeLabel(),
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 13),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    IconButton(
                      onPressed: canPrev ? _prevMonth : null,
                      icon: Icon(Icons.chevron_left_rounded, color: canPrev ? Colors.white : Colors.white24),
                    ),
                    Expanded(
                      child: Text(
                        monthLabel,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: canNext ? _nextMonth : null,
                      icon: Icon(Icons.chevron_right_rounded, color: canNext ? Colors.white : Colors.white24),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
                      .map(
                        (w) => Expanded(
                          child: Center(
                            child: Text(
                              w,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.45),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 8),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisSpacing: 4,
                    crossAxisSpacing: 4,
                    childAspectRatio: 1.1,
                  ),
                  itemCount: _buildGrid().length,
                  itemBuilder: (context, index) {
                    final day = _buildGrid()[index];
                    if (day == null) return const SizedBox.shrink();

                    final disabled = day.isBefore(widget.firstDate) || day.isAfter(widget.lastDate);
                    final isStart = _start != null && _isSameDay(day, _start!);
                    final isEnd = _end != null && _isSameDay(day, _end!);
                    final inRange = _inRange(day);
                    final isToday = _isSameDay(day, widget.lastDate);

                    return GestureDetector(
                      onTap: disabled ? null : () => _onDayTap(day),
                      child: Container(
                        decoration: BoxDecoration(
                          color: isStart || isEnd
                              ? AppColors.primary
                              : inRange
                                  ? AppColors.primary.withValues(alpha: 0.25)
                                  : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          border: isToday && !isStart && !isEnd
                              ? Border.all(color: AppColors.accent.withValues(alpha: 0.8))
                              : null,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '${day.day}',
                          style: TextStyle(
                            color: disabled
                                ? Colors.white24
                                : isStart || isEnd
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.9),
                            fontWeight: isStart || isEnd || isToday ? FontWeight.w800 : FontWeight.w500,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _start != null && _end != null
                            ? () => Navigator.pop(context, DateTimeRange(start: _start!, end: _end!))
                            : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.3),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text('Apply', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _rangeLabel() {
    if (_start == null) return 'Tap start date, then end date';
    if (_end == null) return 'Start: ${DateFormat('d MMM yyyy').format(_start!)} — pick end date';
    final s = _start!.isBefore(_end!) ? _start! : _end!;
    final e = _start!.isBefore(_end!) ? _end! : _start!;
    return '${DateFormat('d MMM').format(s)} – ${DateFormat('d MMM yyyy').format(e)}';
  }
}
