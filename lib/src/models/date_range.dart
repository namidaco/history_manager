import 'package:dart_extensions/dart_extensions.dart';

/// [oldest] and [newest] are both included.
class DateRange {
  final DateTime oldest;
  final DateTime newest;

  const DateRange({
    required this.oldest,
    required this.newest,
  });

  factory DateRange.wholeDays({required DateTime oldest, required DateTime newest}) {
    final oldestDayStart = DateTime(oldest.year, oldest.month, oldest.day);
    final dayAfterNewest = DateTime(newest.year, newest.month, newest.day + 1);
    final newestDayEnd = dayAfterNewest.subtract(_kMillisecond);
    return DateRange(
      oldest: oldestDayStart,
      newest: newestDayEnd,
    );
  }

  factory DateRange.ofDuration({required DateTime oldest, required Duration duration}) {
    final newest = oldest.add(duration - _kMillisecond);
    return DateRange(
      oldest: oldest,
      newest: newest,
    );
  }

  static const _kMillisecond = Duration(milliseconds: 1);

  Duration toDurationSafe() {
    if (newest.isAfter(oldest)) return toDuration();

    // -- same day
    return const Duration(days: 1);
  }

  Duration toDuration() => newest.difference(oldest) + _kMillisecond;

  /// rounded, so a day with a dst change still counts as one.
  int toDaysSafe() {
    final duration = toDurationSafe();
    final days = (duration.inHours / Duration.hoursPerDay).round();
    return days.withMinimum(1);
  }

  factory DateRange.fromJson(Map<String, dynamic> map) {
    return DateRange(
      oldest: DateTime.fromMicrosecondsSinceEpoch(map["oldest"] as int),
      newest: DateTime.fromMicrosecondsSinceEpoch(map["newest"] as int),
    );
  }
  factory DateRange.dummy() {
    return DateRange(
      oldest: DateTime(0),
      newest: DateTime(0),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "oldest": oldest.microsecondsSinceEpoch,
      "newest": newest.microsecondsSinceEpoch,
    };
  }

  @override
  bool operator ==(other) {
    if (other is DateRange) {
      return oldest == other.oldest && newest == other.newest;
    }
    return false;
  }

  @override
  int get hashCode => "$oldest$newest".hashCode;
}
