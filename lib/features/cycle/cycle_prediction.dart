DateTime cycleDay(DateTime date) =>
    DateTime.utc(date.year, date.month, date.day);

class CycleEstimate {
  const CycleEstimate(this.nextStart, this.length, this.samples);
  final DateTime nextStart;
  final int length, samples;
}

CycleEstimate? estimateCycle(List<DateTime> starts, {int fallback = 28}) {
  final days = starts.map(cycleDay).toSet().toList()..sort();
  if (days.isEmpty) return null;
  final intervals = <int>[];
  for (var i = 1; i < days.length; i++) {
    final d = days[i].difference(days[i - 1]).inDays;
    if (d >= 15 && d <= 90) intervals.add(d);
  }
  final recent = intervals.reversed.take(6).toList();
  final length = recent.isEmpty
      ? fallback.clamp(15, 90)
      : (recent.reduce((a, b) => a + b) / recent.length).round();
  return CycleEstimate(
    days.last.add(Duration(days: length)),
    length,
    recent.length,
  );
}

bool cycleContains(DateTime day, DateTime start, DateTime end) =>
    !cycleDay(day).isBefore(cycleDay(start)) &&
    !cycleDay(day).isAfter(cycleDay(end));
