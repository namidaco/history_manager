import 'dart:collection';

class HistoryPrepareInfo<T, E> {
  final SplayTreeMap<int, List<T>> historyMap;
  final Map<E, List<int>> topItems;
  final int totalItemsCount;

  const HistoryPrepareInfo({
    required this.historyMap,
    required this.topItems,
    required this.totalItemsCount,
  });
}
