// by claude
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:history_manager/history_manager.dart';

List<String> _referenceOrder(Map<String, List<int>> reference) {
  return reference.keys.toList()
    ..sort((a, b) {
      final listensA = reference[a]!;
      final listensB = reference[b]!;
      final byCount = listensB.length.compareTo(listensA.length);
      if (byCount != 0) return byCount;
      final byNewest = listensA.reduce(max).compareTo(listensB.reduce(max));
      if (byNewest != 0) return byNewest;
      return a.hashCode.compareTo(b.hashCode);
    });
}

void _expectMatchesReference(ListensSortedMap<String> map, Map<String, List<int>> reference) {
  final keys = map.keysSortedByValue.toList();
  expect(keys, _referenceOrder(reference));
  expect(map.length, reference.length);
  expect(map.entriesSortedByValue.map((e) => e.key).toList(), keys);
  expect(map.entriesSortedByValueCount.map((e) => e.value).toList(), keys.map((k) => reference[k]!.length).toList());
  for (final e in reference.entries) {
    final sortedListens = List.of(e.value)..sort();
    expect(map[e.key], sortedListens, reason: 'listens of ${e.key}');
  }
}

void main() {
  test('assignAll orders by the newest listen even when the lists come unsorted', () {
    final map = ListensSortedMap<String>();
    map.assignAll({
      'A': [600, 100],
      'B': [300, 200],
      'C': [500, 400],
    });

    expect(map.keysSortedByValue.toList(), ['B', 'C', 'A']);
    expect(map['A'], [100, 600]);
    expect(map['B'], [200, 300]);
    expect(map['C'], [400, 500]);
  });

  test('adding an older listen keeps the list ascending', () {
    final map = ListensSortedMap<String>();
    map.addElement('a', 500);
    map.addElement('a', 100);
    map.addElement('a', 300);
    map.addElement('a', 300);
    map.addElement('b', 400);
    map.addElement('b', 450);
    map.addElement('b', 420);
    map.addElement('b', 50);

    expect(map['a'], [100, 300, 300, 500]);
    expect(map['b'], [50, 400, 420, 450]);
    expect(map.keysSortedByValue.toList(), ['b', 'a']);
  });

  test('removing the last listen of a key drops the key', () {
    final map = ListensSortedMap<String>();
    map.addElement('gone', 100);
    map.addElement('gone', 200);
    map.addElement('kept', 150);

    map.removeElement('gone', 200);
    map.removeElement('gone', 100);

    expect(map['gone'], isNull);
    expect(map.length, 1);
    expect(map.keysSortedByValue.toList(), ['kept']);
    expect(map.toCountOnly(), {'kept': 1});
    expect(map.entriesSortedByValueCount.where((e) => e.value == 0), isEmpty);
  });

  test('removing a listen that is not there changes nothing', () {
    final map = ListensSortedMap<String>();
    map.addElement('a', 100);
    map.addElement('a', 300);
    map.addElement('b', 200);

    map.removeElement('a', 200);
    map.removeElement('missing', 100);

    expect(map['a'], [100, 300]);
    expect(map.keysSortedByValue.toList(), ['a', 'b']);
  });

  test('random adds and removes after a load always match a full sort, one entry per key', () {
    final random = Random(1280);
    for (int round = 0; round < 20; round++) {
      final initial = <String, List<int>>{};
      final reference = <String, List<int>>{};
      for (int i = 0; i < 80; i++) {
        final key = 'k${random.nextInt(200)}';
        final listen = random.nextInt(5000);
        initial.putIfAbsent(key, () => <int>[]).add(listen);
        reference.putIfAbsent(key, () => <int>[]).add(listen);
      }
      final map = ListensSortedMap<String>();
      map.assignAll(initial);
      _expectMatchesReference(map, reference);

      for (int step = 0; step < 300; step++) {
        final key = 'k${random.nextInt(200)}';
        final listens = reference[key];
        if (listens != null && random.nextBool()) {
          final listen = random.nextInt(4) == 0 ? random.nextInt(5000) : listens[random.nextInt(listens.length)];
          map.removeElement(key, listen);
          listens.remove(listen);
          if (listens.isEmpty) reference.remove(key);
        } else {
          final listen = random.nextInt(5000);
          map.addElement(key, listen);
          reference.putIfAbsent(key, () => <int>[]).add(listen);
        }
        _expectMatchesReference(map, reference);
      }
    }
  });
}
