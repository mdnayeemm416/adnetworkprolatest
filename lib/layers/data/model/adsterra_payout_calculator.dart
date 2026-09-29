import 'package:adnetwork/layers/data/model/adsterra_models.dart';

class PayoutEstimate {
  final double nextPayoutAmount;
  final String nextPayoutLabel;
  final String nextPayoutDate;

  final double pendingPayoutAmount;
  final String pendingPayoutLabel;
  final String pendingPayoutDate;

  const PayoutEstimate({
    required this.nextPayoutAmount,
    required this.nextPayoutLabel,
    required this.nextPayoutDate,
    required this.pendingPayoutAmount,
    required this.pendingPayoutLabel,
    required this.pendingPayoutDate,
  });
}

class AdsterraPayoutCalculator {
  static PayoutEstimate calculate({
    required List<AdsterraStatItem> currentMonthItems,
    required List<AdsterraStatItem> prevMonthItems,
    required DateTime now,
  }) {
    // Split previous month by half
    double prevFirstHalf = _sumRevenue(prevMonthItems, (d) => d.day <= 15);
    double prevSecondHalf = _sumRevenue(prevMonthItems, (d) => d.day > 15);

    // Split current month by half
    double curFirstHalf = _sumRevenue(currentMonthItems, (d) => d.day <= 15);
    double curSecondHalf = _sumRevenue(currentMonthItems, (d) => d.day > 15);

    final nextMonth = DateTime(now.year, now.month + 1, 1);
    final thisMonth3rd = DateTime(now.year, now.month, 3);
    final thisMonth16th = DateTime(now.year, now.month, 16);
    final nextMonth3rd = DateTime(nextMonth.year, nextMonth.month, 3);
    final nextMonth16th = DateTime(nextMonth.year, nextMonth.month, 16);

    final int day = now.day;

    double nextAmount;
    String nextLabel;
    String nextDate;

    double pendingAmount;
    String pendingLabel;
    String pendingDate;

    if (day <= 2) {
      nextAmount = prevFirstHalf;
      nextLabel = 'Prev month 1–15 revenue';
      nextDate = _fmt(thisMonth3rd);

      pendingAmount = prevSecondHalf;
      pendingLabel = 'Prev month 16–end revenue';
      pendingDate = _fmt(thisMonth16th);
    } else if (day <= 15) {
      nextAmount = prevSecondHalf;
      nextLabel = 'Prev month 16–end revenue';
      nextDate = _fmt(thisMonth16th);

      pendingAmount = curFirstHalf;
      pendingLabel = 'This month 1–${now.day} revenue';
      pendingDate = _fmt(nextMonth3rd);
    } else {
      nextAmount = curFirstHalf;
      nextLabel = 'This month 1–15 revenue';
      nextDate = _fmt(nextMonth3rd);

      pendingAmount = curSecondHalf;
      pendingLabel = 'This month 16–${now.day} revenue';
      pendingDate = _fmt(nextMonth16th);
    }

    return PayoutEstimate(
      nextPayoutAmount: nextAmount,
      nextPayoutLabel: nextLabel,
      nextPayoutDate: nextDate,
      pendingPayoutAmount: pendingAmount,
      pendingPayoutLabel: pendingLabel,
      pendingPayoutDate: pendingDate,
    );
  }

  static double _sumRevenue(
    List<AdsterraStatItem> items,
    bool Function(DateTime) predicate,
  ) {
    double total = 0.0;
    for (final item in items) {
      if (item.date == null) continue;
      try {
        final d = DateTime.parse(item.date!);
        if (predicate(d)) total += item.revenue;
      } catch (_) {}
    }
    return total;
  }

  static String _fmt(DateTime d) {
    const months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '~${months[d.month]} ${d.day}, ${d.year}';
  }
}
