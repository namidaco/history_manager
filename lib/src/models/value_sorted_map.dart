import 'dart:collection';

class ListensSortedMap<K> {
  Iterable<K> get keysSortedByValue => _entries.map((element) => element.key);
  Iterable<MapEntry<K, List<int>>> get entriesSortedByValue => keysSortedByValue.map((e) => MapEntry(e, _map[e] ?? []));
  int get length => _map.length;
  List<int>? operator [](K key) => _map[key];

  final _map = <K, List<int>>{};
  final _entries = SplayTreeSet<MapEntry<K, List<int>>>(
    (a, b) {
      int compare = b.value.length.compareTo(a.value.length);
      if (compare != 0) return compare;

      final lastListenB = b.value.lastOrNull ?? 0;
      final lastListenA = a.value.lastOrNull ?? 0;
      compare = lastListenA.compareTo(lastListenB); // the first one to reach that listen count thats why
      if (compare != 0) return compare;

      compare = a.key.hashCode.compareTo(b.key.hashCode); // tie-breaker
      return compare;
    },
  );

  void addElement(K key, int element) {
    final list = _map[key];
    if (list != null) {
      this.remove(key); // remove first to avoid duplications
      list.add(element);
      this.add(key, list);
    } else {
      final list = [element];
      this.add(key, list);
    }
  }

  void removeElement(K key, int element) {
    final list = _map[key];
    if (list != null) {
      this.remove(key); // remove first to avoid duplications
      list.remove(element);
      this.add(key, list);
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
      final key = e.key;
      final value = e.value;
      _map[key] = value;
      _entries.add(e);
    }
  }

  void sortAllInternalLists() {
    for (final entry in _map.values) {
      entry.sort();
    }
  }

  void add(K key, List<int> value) {
    _map[key] = value;
    _entries.add(MapEntry(key, value));
  }

  void remove(K key) {
    if (_map.containsKey(key)) {
      _entries.remove(MapEntry(key, _map[key]!));
      _map.remove(key);
    }
  }

  @override
  String toString() => _entries.toString();
}
