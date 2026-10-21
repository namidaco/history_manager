// by claude
part of 'history_manager_mixin.dart';

/// moves listens saved under another day back to their own day.
/// older versions keyed days 1h off during DST, putting listens up to 1 AM in the previous day.
/// each check costs a timezone lookup, so it runs once, see [HistoryManager.didRepairHistoryDays].
class HistoryDaysRepair<T extends ItemWithDate> {
  final _sussyDays = <int>[];

  /// [dayItems] must be sorted newest first.
  void checkDay(int day, List<T> dayItems) {
    if (day <= 0 || dayItems.isEmpty) return; // -- listens without a date
    final newestItemDay = dayItems.first.dateAddedMS.toDaysSince1970();
    final oldestItemDay = dayItems.last.dateAddedMS.toDaysSince1970();
    if (newestItemDay != day || oldestItemDay != day) _sussyDays.add(day);
  }

  /// writes the changed days into [directoryPath], returns the dropped duplicates.
  List<T> repair(Map<int, List<T>> historyMap, String directoryPath, Map<String, dynamic> Function(T item) itemToJson) {
    if (_sussyDays.isEmpty) return const [];

    final changedDays = <int>{};
    final droppedDuplicates = <T>[];
    void moveToItsDay(T item) {
      final movedToDay = _moveToItsDay(historyMap, item);
      if (movedToDay == null) {
        droppedDuplicates.add(item);
      } else {
        changedDays.add(movedToDay);
      }
    }

    for (final day in _sussyDays) {
      final dayItems = historyMap[day];
      if (dayItems == null) continue;
      final startIndex = _startIndexOfDay(day, dayItems);
      final endIndex = _endIndexOfDay(day, dayItems, startIndex);
      for (int i = 0; i < startIndex; i++) {
        moveToItsDay(dayItems[i]);
      }
      for (int i = endIndex; i < dayItems.length; i++) {
        moveToItsDay(dayItems[i]);
      }
      dayItems.removeRange(endIndex, dayItems.length);
      dayItems.removeRange(0, startIndex);
      changedDays.add(day);
    }

    for (final day in changedDays) {
      final dayFile = File('$directoryPath$day.json');
      final dayItems = historyMap[day];
      if (dayItems == null || dayItems.isEmpty) {
        historyMap.remove(day);
        dayFile.deleteIfExistsSync();
      } else {
        final dayItemsJson = dayItems.map(itemToJson).toList();
        dayFile.writeAsJsonSync(dayItemsJson);
      }
    }
    return droppedDuplicates;
  }

  /// returns the day [item] went into, null when that day already has it.
  int? _moveToItsDay(Map<int, List<T>> historyMap, T item) {
    final dateMS = item.dateAddedMS;
    final day = dateMS.toDaysSince1970();
    final dayItems = historyMap[day];
    if (dayItems == null) {
      historyMap[day] = <T>[item];
      return day;
    }
    final index = HistoryManager._firstIndexAtOrBefore(dayItems, dateMS);
    if (HistoryManager._containsAtDate(dayItems, index, item)) return null;
    dayItems.insert(index, item);
    return day;
  }

  static int _startIndexOfDay(int day, List<ItemWithDate> dayItems) {
    for (int i = 0; i < dayItems.length; i++) {
      final itemDay = dayItems[i].dateAddedMS.toDaysSince1970();
      if (itemDay == day) return i;
    }
    return dayItems.length;
  }

  static int _endIndexOfDay(int day, List<ItemWithDate> dayItems, int startIndex) {
    for (int i = dayItems.length - 1; i >= startIndex; i--) {
      final itemDay = dayItems[i].dateAddedMS.toDaysSince1970();
      if (itemDay == day) return i + 1;
    }
    return startIndex;
  }
}
