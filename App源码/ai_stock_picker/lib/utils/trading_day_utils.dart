/// A股交易日工具类
///
/// 统一管理A股节假日和交易日判断逻辑，供全App共享。
/// 规则：排除周末 + 排除A股法定节假日。
/// 各组件（首页收益统计、横屏、交易日记录、投资日历）均应使用此类。

class TradingDayUtils {
  TradingDayUtils._();

  /// 2026年A股节假日（不含周末，周末由weekday判断）
  static const Set<String> kHolidayDates = {
    // 2026年元旦
    '2026-01-01',
    // 2026年春节（2月16日除夕~2月22日初六）
    '2026-02-16', '2026-02-17', '2026-02-18', '2026-02-19',
    '2026-02-20', '2026-02-21', '2026-02-22',
    // 2026年清明节（4月4日~4月6日）
    '2026-04-04', '2026-04-05', '2026-04-06',
    // 2026年劳动节（5月1日~5月5日）
    '2026-05-01', '2026-05-02', '2026-05-03', '2026-05-04', '2026-05-05',
    // 2026年端午节（6月19日~6月21日）
    '2026-06-19', '2026-06-20', '2026-06-21',
    // 2026年中秋节（9月25日~9月27日）
    '2026-09-25', '2026-09-26', '2026-09-27',
    // 2026年国庆节+中秋（10月1日~10月7日）
    '2026-10-01', '2026-10-02', '2026-10-03', '2026-10-04',
    '2026-10-05', '2026-10-06', '2026-10-07',
  };

  /// 将 DateTime 格式化为 yyyy-MM-dd 字符串
  static String formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// 判断某日期是否为证券交易日
  /// 规则：排除周末（周六、周日）+ 排除A股法定节假日
  static bool isSecuritiesTradingDay(DateTime date) {
    // 1. 排除周末
    if (date.weekday == DateTime.saturday || date.weekday == DateTime.sunday) {
      return false;
    }
    // 2. 排除A股节假日
    if (kHolidayDates.contains(formatDate(date))) {
      return false;
    }
    return true;
  }

  /// 判断日期字符串（yyyy-MM-dd）是否为非交易日
  static bool isNonTradingDayStr(String dateStr) {
    final parts = dateStr.split('-');
    if (parts.length != 3) return false;
    final date = DateTime(
      int.tryParse(parts[0]) ?? 2000,
      int.tryParse(parts[1]) ?? 1,
      int.tryParse(parts[2]) ?? 1,
    );
    return !isSecuritiesTradingDay(date);
  }

  /// 获取指定日期的下一个交易日
  /// 自动跳过周末和节假日
  static DateTime getNextTradingDay(DateTime date) {
    var next = date.add(const Duration(days: 1));
    while (!isSecuritiesTradingDay(next)) {
      next = next.add(const Duration(days: 1));
    }
    return next;
  }

  /// 获取指定日期的上一个交易日
  /// 自动跳过周末和节假日
  static DateTime getPreviousTradingDay(DateTime date) {
    var prev = date.subtract(const Duration(days: 1));
    while (!isSecuritiesTradingDay(prev)) {
      prev = prev.subtract(const Duration(days: 1));
    }
    return prev;
  }

  /// 日期字符串减1个交易日：'2026-06-10' → '2026-06-09'
  /// 自动跳过周末和A股节假日
  static String previousTradingDayStr(String dateStr) {
    final d = DateTime.parse(dateStr);
    return formatDate(getPreviousTradingDay(d));
  }

  /// 日期字符串加1个交易日：'2026-06-09' → '2026-06-10'
  /// 自动跳过周末和A股节假日
  static String nextTradingDayStr(String dateStr) {
    final d = DateTime.parse(dateStr);
    return formatDate(getNextTradingDay(d));
  }

  /// 判断某条交易日记录的涨跌幅是否应显示为 0.00%
  ///
  /// 规则：
  /// - 如果记录日期是今天，且今天是交易日，且当前在交易时段（09:30~15:05）→ 显示实时数据（返回 false）
  /// - 否则，如果当前时间还未到该记录日期的【下一个交易日的 09:30】→ 数据未确认，显示 0.00%（返回 true）
  /// - 否则 → 数据已结算确认，显示真实涨跌幅（返回 false）
  ///
  /// 示例：6月18日（周四）是最后一个交易日，6月19-21日是端午节假期，
  /// 下一个交易日是6月22日（周一）。在6月22日09:30之前，6月18日的数据应显示 0.00%。
  static bool shouldRecordShowZero(String recordDateStr) {
    final now = DateTime.now();
    final todayStr = formatDate(now);

    // 情况1：今天是交易日，记录是今天的，且在交易时段内 → 显示实时数据
    if (recordDateStr == todayStr && isSecuritiesTradingDay(now)) {
      final timeInMinutes = now.hour * 60 + now.minute;
      final isTradingHours = timeInMinutes >= (9 * 60 + 30) && timeInMinutes < (15 * 60 + 5);
      if (isTradingHours) return false;
    }

    // 情况2：当前时间还没到该记录的下一个交易日的 09:30 → 数据未确认 → 0.00%
    final parts = recordDateStr.split('-');
    if (parts.length != 3) return false;
    final recordDate = DateTime(
      int.tryParse(parts[0]) ?? 2000,
      int.tryParse(parts[1]) ?? 1,
      int.tryParse(parts[2]) ?? 1,
    );
    final nextTD = getNextTradingDay(recordDate);
    final confirmTime = DateTime(nextTD.year, nextTD.month, nextTD.day, 9, 30);
    return now.isBefore(confirmTime);
  }

  /// 计算两个日期之间的证券交易日天数（排除周末+节假日）
  static int countTradingDays(DateTime from, DateTime to) {
    int count = 0;
    var current = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);
    while (!current.isAfter(end)) {
      if (isSecuritiesTradingDay(current)) {
        count++;
      }
      current = current.add(const Duration(days: 1));
    }
    return count;
  }
}
