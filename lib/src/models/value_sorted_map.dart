import 'dart:collection';

class ListensSortedMap<K> {
  Map<K, int> toCountOnly() => _map.map((key, entry) => MapEntry(key, entry.value.length));

  Iterable<K> get keysSortedByValue => _entries.map((element) => element.key);
  Iterable<MapEntry<K, List<int>>> get entriesSortedByValue => _entries;
  Iterable<MapEntry<K, int>> get entriesSortedByValueCount => _entries.map((e) => MapEntry(e.key, e.value.length));
  Iterable<List<int>> get values => _entries.map((e) => e.value);
  int get length => _map.length;
  List<int>? operator [](K key) => _map[key]?.value;

  final _map = <K, MapEntry<K, List<int>>>{};
  final _entries = SplayTreeSet<MapEntry<K, List<int>>>(
    (a, b) {
      int compare = b.value.length.compareTo(a.value.length);
      if (compare != 0) return compare;

      final lastListenB = b.value.last;
      final lastListenA = a.value.last;
      compare = lastListenA.compareTo(lastListenB); // the first one to reach that listen count thats why
      if (compare != 0) return compare;

      compare = a.key.hashCode.compareTo(b.key.hashCode); // tie-breaker
      return compare;
    },
  );

  void addElement(K key, int element) {
    final entry = _map[key];
    if (entry == null) {
      final newEntry = MapEntry(key, [element]);
      _insert(newEntry);
      return;
    }
    final list = entry.value;
    _entries.remove(entry); // -- remove before changing the list, its position depends on it
    if (element >= list.last) {
      list.add(element);
    } else {
      final index = _lowerBound(list, element);
      list.insert(index, element);
    }
    _entries.add(entry);
  }

  void removeElement(K key, int element) {
    final entry = _map[key];
    if (entry == null) return;
    final list = entry.value;
    final index = _lowerBound(list, element);
    if (index == list.length || list[index] != element) return;
    _entries.remove(entry);
    list.removeAt(index);
    if (list.isEmpty) {
      _map.remove(key);
    } else {
      _entries.add(entry);
    }
  }

  void clear() {
    _map.clear();
    _entries.clear();
  }

  void assignAll(Map<K, List<int>> map) => assignAllEntries(map.entries);

  void assignAllEntries(Iterable<MapEntry<K, List<int>>> entries) {
    clear();

    for (final e in entries) {
      e.value.sort();
      _insert(e);
    }
  }

  void remove(K key) {
    final entry = _map.remove(key);
    if (entry != null) _entries.remove(entry);
  }

  void _insert(MapEntry<K, List<int>> entry) {
    _map[entry.key] = entry;
    _entries.add(entry);
  }

  static int _lowerBound(List<int> sortedList, int value) {
    int low = 0;
    int high = sortedList.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (sortedList[mid] < value) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  @override
  String toString() => _entries.toString();
}
