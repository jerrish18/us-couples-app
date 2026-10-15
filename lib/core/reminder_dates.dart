DateTime nextAnnualDate(DateTime original, DateTime now) {
  DateTime occurrence(int year) {
    final max = DateTime(year, original.month + 1, 0).day;
    return DateTime(
      year,
      original.month,
      original.day > max ? max : original.day,
      9,
    );
  }

  final candidate = occurrence(now.year);
  return candidate.isBefore(DateTime(now.year, now.month, now.day))
      ? occurrence(now.year + 1)
      : candidate;
}

int stableNotificationId(String key) {
  var hash = 2166136261;
  for (final code in key.codeUnits) {
    hash = ((hash ^ code) * 16777619) & 0xffffffff;
  }
  return hash & 0x7fffffff;
}

int daysTogether(DateTime since, DateTime now) => DateTime.utc(
  now.year,
  now.month,
  now.day,
).difference(DateTime.utc(since.year, since.month, since.day)).inDays;
