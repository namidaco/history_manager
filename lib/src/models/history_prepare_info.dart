import 'dart:collection';

import 'package:history_manager/src/models/value_sorted_map.dart';

class HistoryPrepareInfo<T, E> {
  final SplayTreeMap<int, List<T>> historyMap;
  final ListensSortedMap<E> topItems;
  final int totalItemsCount;

  const HistoryPrepareInfo({
    required this.historyMap,
    required this.topItems,
    required this.totalItemsCount,
  });
}
