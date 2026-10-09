// by claude
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:dart_extensions/dart_extensions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:history_manager/history_manager.dart';
import 'package:nampack/reactive/reactive.dart';

class _TestHistory with HistoryManager<_Listen, String> {
  final String _directoryPath;
  _TestHistory(Directory dir) : _directoryPath = '${dir.path}${Platform.pathSeparator}';

  @override
  // ignore: non_constant_identifier_names
  String get HISTORY_DIRECTORY => _directoryPath;

  @override
  final currentMostPlayedTimeRange = MostPlayedTimeRange.allTime.obs;

  @override
  final mostPlayedCustomDateRange = DateRange.dummy().obs;

  @override
  final mostPlayedCustomIsStartOfDay = true.obs;

  @override
  String mainItemToSubItem(_Listen item) => item.id;

  @override
  Map<String, dynamic> itemToJson(_Listen item) => item.toJson();

  @override
  double daysToSectionExtent(List<int> days) => 0.0;

  @override
  Future<HistoryPrepareInfo<_Listen, String>> prepareAllHistoryFilesFunction(String directoryPath) async {
    final map = SplayTreeMap<int, List<_Listen>>((date1, date2) => date2.compareTo(date1));
    final tempMapTopItems = <String, List<int>>{};
    int totalCount = 0;
    for (final f in Directory(directoryPath).listSync()) {
      if (f is! File) continue;
      final listens = _readListensFile(f);
      for (final l in listens) {
        tempMapTopItems.addForce(l.id, l.dateAddedMS);
      }
      map[_dayOfFile(f)] = listens;
      totalCount += listens.length;
    }
    final topItems = ListensSortedMap<String>();
    topItems.assignAll(tempMapTopItems);
    return HistoryPrepareInfo(historyMap: map, topItems: topItems, totalItemsCount: totalCount);
  }
}

class _Listen with ItemWithDate {
  static int dateReads = 0;

  final String id;
  final int _dateAddedMS;
  @override
  final TrackSource? sourceNull;

  const _Listen(this.id, this._dateAddedMS, [this.sourceNull]);

  @override
  int get dateAddedMS {
    dateReads++;
    return _dateAddedMS;
  }

  factory _Listen.fromJson(Map<String, dynamic> json) {
    final sourceName = json['source'] as String?;
    final source = sourceName == null ? null : TrackSource.values.byName(sourceName);
    return _Listen(json['id'] as String, json['date'] as int, source);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': dateAddedMS,
        if (sourceNull != null) 'source': sourceNull!.name,
      };

  @override
  bool operator ==(Object other) => other is _Listen && other.id == id && other.dateAddedMS == dateAddedMS && other.sourceNull == sourceNull;

  @override
  int get hashCode => Object.hash(id, dateAddedMS, sourceNull);

  @override
  String toString() {
    final date = DateTime.fromMillisecondsSinceEpoch(dateAddedMS);
    return '$id@$date ${sourceNull?.name ?? ''}';
  }
}

int _ms(int year, int month, int day, [int hour = 0, int minute = 0, int second = 0]) => DateTime(year, month, day, hour, minute, second).millisecondsSinceEpoch;

int _dayOf(int year, int month, int day) => DateTime(year, month, day).toDaysSince1970();

File _dayFile(Directory dir, int day) => File('${dir.path}${Platform.pathSeparator}$day.json');

int _dayOfFile(File file) {
  final filename = file.uri.pathSegments.last;
  return int.parse(filename.split('.').first);
}

List<_Listen> _readListensFile(File file) {
  final json = jsonDecode(file.readAsStringSync()) as List;
  return json.map((e) => _Listen.fromJson(e as Map<String, dynamic>)).toList();
}

List<_Listen> _readDay(Directory dir, int day) => _readListensFile(_dayFile(dir, day));

Set<int> _dayFiles(Directory dir) => dir.listSync().whereType<File>().map(_dayOfFile).toSet();

void _writeListens(Directory dir, List<_Listen> listens) {
  final byDay = <int, List<_Listen>>{};
  for (final l in listens) {
    byDay.addForce(l.dateAddedMS.toDaysSince1970(), l);
  }
  for (final e in byDay.entries) {
    final dayListens = e.value..sort((a, b) => b.dateAddedMS.compareTo(a.dateAddedMS));
    final json = jsonEncode(dayListens.map((l) => l.toJson()).toList());
    _dayFile(dir, e.key).writeAsStringSync(json);
  }
}

Future<_TestHistory> _loadedHistory(Directory dir) async {
  final history = _TestHistory(dir);
  await history.prepareHistoryFile();
  return history;
}

SplayTreeMap<int, List<_Listen>> _copyOfHistory(SplayTreeMap<int, List<_Listen>> map) {
  final copy = SplayTreeMap<int, List<_Listen>>((date1, date2) => date2.compareTo(date1));
  for (final e in map.entries) {
    copy[e.key] = List.of(e.value);
  }
  return copy;
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('history_manager_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('load and idle gating', () {
    test('a listen added before the load is applied after it and saved', () async {
      final loaded = _Listen('a', _ms(2026, 3, 15, 9));
      _writeListens(dir, [loaded]);
      final history = _TestHistory(dir);
      final added = _Listen('b', _ms(2026, 3, 15, 11));

      final pendingAdd = history.addTracksToHistory([added]);
      await history.prepareHistoryFile();
      await pendingAdd;

      final day = _dayOf(2026, 3, 15);
      expect(history.historyMap.value[day], [added, loaded]);
      expect(_readDay(dir, day), [added, loaded]);
      expect(history.totalHistoryItemsCount.value, 2);
      expect(history.topTracksMapListens.value['b'], [added.dateAddedMS]);
    });

    test('a listen added while idle waits, then lands once idle ends, and later listens do not wait', () async {
      final history = await _loadedHistory(dir);
      await history.setIdleStatus(true);

      final waiting = _Listen('a', _ms(2026, 3, 15, 9));
      final pendingAdd = history.addTracksToHistory([waiting]);
      await pumpEventQueue();
      expect(history.historyTracks, isEmpty);

      await history.setIdleStatus(false);
      await pumpEventQueue();
      expect(history.historyTracks, [waiting]);
      await pendingAdd;
      expect(_readDay(dir, _dayOf(2026, 3, 15)), [waiting]);

      final later = _Listen('b', _ms(2026, 3, 15, 10));
      final laterAdd = history.addTracksToHistory([later]);
      expect(history.historyTracks, contains(later));
      await laterAdd;
    });

    test('preparing the history again does not complete the load twice', () async {
      _writeListens(dir, [_Listen('a', _ms(2026, 3, 15, 9))]);
      final history = await _loadedHistory(dir);

      await history.prepareHistoryFile();

      expect(history.isHistoryLoaded, isTrue);
      expect(history.totalHistoryItemsCount.value, 1);
    });

    test('going idle twice then ending idle once releases every waiting listen', () async {
      final history = await _loadedHistory(dir);
      final first = _Listen('a', _ms(2026, 3, 15, 9));
      final second = _Listen('b', _ms(2026, 3, 15, 10));

      await history.setIdleStatus(true);
      final firstAdd = history.addTracksToHistory([first]);
      await history.setIdleStatus(true);
      final secondAdd = history.addTracksToHistory([second]);
      await history.setIdleStatus(false);
      await pumpEventQueue();

      expect(history.historyTracks, unorderedEquals([first, second]));
      await Future.wait([firstAdd, secondAdd]);
    });

    group('writers wait for idle and apply to the history that replaced the map', () {
      final kept = _Listen('kept', _ms(2026, 3, 15, 8));
      final target = _Listen('target', _ms(2026, 3, 15, 9), TrackSource.lastfm);
      final imported = _Listen('imported', _ms(2026, 3, 15, 10), TrackSource.youtube);
      final day = _dayOf(2026, 3, 15);

      Future<_TestHistory> runWhileImporting(Future<void> Function(_TestHistory history) writer) async {
        _writeListens(dir, [kept, target]);
        final history = await _loadedHistory(dir);
        await history.setIdleStatus(true);
        final importedHistory = _copyOfHistory(history.historyMap.value);
        importedHistory[day]!.insert(0, imported);

        final pendingWrite = writer(history);
        await pumpEventQueue();
        history.historyMap.value = importedHistory;
        history.totalHistoryItemsCount.value += 1;
        await history.setIdleStatus(false);
        await pendingWrite;
        return history;
      }

      test('removeTracksFromHistory', () async {
        final history = await runWhileImporting((history) => history.removeTracksFromHistory([target]));

        expect(history.historyMap.value[day], [imported, kept]);
        expect(_readDay(dir, day), [imported, kept]);
        expect(history.totalHistoryItemsCount.value, 2);
      });

      test('removeSourcesTracksFromHistory', () async {
        final history = await runWhileImporting((history) => history.removeSourcesTracksFromHistory([TrackSource.lastfm]));

        expect(history.historyMap.value[day], [imported, kept]);
        expect(_readDay(dir, day), [imported, kept]);
      });

      test('replaceTheseTracksInHistory', () async {
        final replacement = _Listen('replacement', target.dateAddedMS, TrackSource.lastfm);
        final history = await runWhileImporting((history) => history.replaceTheseTracksInHistory((e) => e == target, (old) => replacement));

        expect(history.historyMap.value[day], [imported, replacement, kept]);
        expect(_readDay(dir, day), [imported, replacement, kept]);
      });
    });
  });

  group('removeSourcesTracksFromHistory', () {
    test('removing every source with no dates deletes the day files', () async {
      _writeListens(dir, [
        _Listen('a', _ms(2026, 3, 14, 9)),
        _Listen('b', _ms(2026, 3, 15, 9), TrackSource.lastfm),
        _Listen('c', _ms(2026, 3, 15, 10), TrackSource.youtube),
      ]);
      final history = await _loadedHistory(dir);

      final removed = await history.removeSourcesTracksFromHistory([...TrackSource.values]);

      expect(removed, 3);
      expect(history.historyMap.value, isEmpty);
      expect(history.totalHistoryItemsCount.value, 0);
      expect(history.topTracksMapListens.value.length, 0);
      expect(_dayFiles(dir), isEmpty);
      final reloaded = await _loadedHistory(dir);
      expect(reloaded.historyMap.value, isEmpty);
    });

    test('removing one source between dates only removes its listens inside the inclusive day bounds', () async {
      final lastfmBefore = _Listen('a', _ms(2026, 3, 1, 12), TrackSource.lastfm);
      final lastfmFirstDay = _Listen('b', _ms(2026, 3, 2, 9), TrackSource.lastfm);
      final localFirstDay = _Listen('c', _ms(2026, 3, 2, 10));
      final lastfmLastDay = _Listen('d', _ms(2026, 3, 3, 23), TrackSource.lastfm);
      final localAfter = _Listen('e', _ms(2026, 3, 4, 9));
      _writeListens(dir, [lastfmBefore, lastfmFirstDay, localFirstDay, lastfmLastDay, localAfter]);
      final history = await _loadedHistory(dir);

      final removed = await history.removeSourcesTracksFromHistory(
        [TrackSource.lastfm],
        oldestDate: DateTime(2026, 3, 2, 15),
        newestDate: DateTime(2026, 3, 3),
      );

      expect(removed, 2);
      expect(history.historyTracks.toList(), [localAfter, localFirstDay, lastfmBefore]);
      expect(history.totalHistoryItemsCount.value, 3);
      expect(_dayFiles(dir), {_dayOf(2026, 3, 1), _dayOf(2026, 3, 2), _dayOf(2026, 3, 4)});
      expect(_readDay(dir, _dayOf(2026, 3, 2)), [localFirstDay]);
      expect(history.topTracksMapListens.value['b'], isNull);
      expect(history.topTracksMapListens.value['d'], isNull);
    });
  });

  test('adding older listens keeps the day newest first, in memory and on disk', () async {
    final noon = _Listen('a', _ms(2026, 3, 15, 12));
    final morning = _Listen('b', _ms(2026, 3, 15, 8));
    _writeListens(dir, [noon, morning]);
    final history = await _loadedHistory(dir);
    final ten = _Listen('c', _ms(2026, 3, 15, 10));
    final seven = _Listen('d', _ms(2026, 3, 15, 7));
    final afternoon = _Listen('e', _ms(2026, 3, 15, 13));

    await history.addTracksToHistory([ten, seven, afternoon]);

    final day = _dayOf(2026, 3, 15);
    final expected = [afternoon, noon, ten, morning, seven];
    expect(history.historyMap.value[day], expected);
    expect(_readDay(dir, day), expected);
    expect(history.totalHistoryItemsCount.value, 5);
  });

  test('removing a listen updates the time range most played', () async {
    final nowMS = DateTime.now().millisecondsSinceEpoch;
    final removed = _Listen('removed', nowMS - const Duration(hours: 2).inMilliseconds);
    final kept = _Listen('kept', nowMS - const Duration(hours: 1).inMilliseconds);
    _writeListens(dir, [removed, kept]);
    final history = _TestHistory(dir);
    history.currentMostPlayedTimeRange.value = MostPlayedTimeRange.week;
    history.mostPlayedCustomIsStartOfDay.value = false;
    await history.prepareHistoryFile();
    expect(history.topTracksMapListensTemp.value.keysSortedByValue.toSet(), {'removed', 'kept'});

    await history.removeTracksFromHistory([removed]);

    expect(history.topTracksMapListensTemp.value.keysSortedByValue.toList(), ['kept']);
    expect(history.topTracksMapListens.value['removed'], isNull);
  });

  group('removeDuplicatedItems', () {
    final bucketBoundaryMS = (_ms(2026, 3, 15, 12) ~/ 280000 + 1) * 280000;
    final day = bucketBoundaryMS.toDaysSince1970();

    Future<_TestHistory> historyWith(List<_Listen> listens) async {
      final history = await _loadedHistory(dir);
      history.addTracksToHistoryOnly(listens);
      return history;
    }

    test('a local listen and its import straddling a bucket boundary collapse into one', () async {
      final history = await historyWith([
        _Listen('a', bucketBoundaryMS - 15000),
        _Listen('a', bucketBoundaryMS + 15000, TrackSource.youtube),
      ]);

      final removed = history.removeDuplicatedItems([day]);

      expect(removed, 1);
      expect(history.historyMap.value[day], hasLength(1));
      expect(history.totalHistoryItemsCount.value, 1);
    });

    test('listens of different sources further apart than the window stay', () async {
      final history = await historyWith([
        _Listen('a', bucketBoundaryMS - 150000),
        _Listen('a', bucketBoundaryMS + 150000, TrackSource.youtube),
      ]);

      expect(history.removeDuplicatedItems([day]), 0);
      expect(history.historyMap.value[day], hasLength(2));
    });

    test('two local listens of the same item stay', () async {
      final history = await historyWith([
        _Listen('a', bucketBoundaryMS - 50000),
        _Listen('a', bucketBoundaryMS + 50000),
      ]);

      expect(history.removeDuplicatedItems([day]), 0);
      expect(history.historyMap.value[day], hasLength(2));
    });

    test('an exact duplicate is removed', () async {
      final listen = _Listen('a', bucketBoundaryMS + 1000, TrackSource.lastfm);
      final history = await historyWith([listen, listen]);

      expect(history.removeDuplicatedItems([day]), 1);
      expect(history.historyMap.value[day], [listen]);
      expect(history.totalHistoryItemsCount.value, 1);
    });

    test('an empty day list removes nothing, no list checks every day', () async {
      final history = await historyWith([
        _Listen('a', bucketBoundaryMS - 15000),
        _Listen('a', bucketBoundaryMS + 15000, TrackSource.youtube),
      ]);

      expect(history.removeDuplicatedItems([]), 0);
      expect(history.historyMap.value[day], hasLength(2));
      expect(history.removeDuplicatedItems(), 1);
      expect(history.historyMap.value[day], hasLength(1));
    });

    test('a day listed once per added listen is deduped and sorted once', () async {
      final history = await historyWith([
        _Listen('a', bucketBoundaryMS - 3600000),
        _Listen('b', bucketBoundaryMS + 3600000),
      ]);
      int dateReadsOf(void Function() run) {
        _Listen.dateReads = 0;
        run();
        return _Listen.dateReads;
      }

      final dayPerListen = List.filled(50, day);
      expect(dateReadsOf(() => history.removeDuplicatedItems(dayPerListen)), dateReadsOf(() => history.removeDuplicatedItems([day])));
      expect(dateReadsOf(() => history.sortHistoryTracks(dayPerListen)), dateReadsOf(() => history.sortHistoryTracks([day])));
    });

    test('a duplicate replacing an earlier listen keeps the day sorted, so ranges still find every listen', () async {
      final localA = _Listen('a', _ms(2026, 3, 15, 10, 4));
      final b = _Listen('b', _ms(2026, 3, 15, 10, 2));
      final importedA = _Listen('a', _ms(2026, 3, 15, 10, 1), TrackSource.youtube);
      _writeListens(dir, [localA, b, importedA]);
      final history = await _loadedHistory(dir);

      final removed = await history.removeSourcesTracksFromHistory([], removeMultiSourceDuplicates: true);

      final listensDay = _dayOf(2026, 3, 15);
      expect(removed, 1);
      expect(history.historyMap.value[listensDay], [b, importedA]);
      expect(_readDay(dir, listensDay), [b, importedA]);
      expect(history.generateTracksFromHistoryDates(DateTime(2026, 3, 15, 10, 2), DateTime(2026, 3, 15, 23)), [b]);
    });
  });

  group('time ranges', () {
    final timeNow = DateTime(2026, 3, 15, 10);

    test('resolveOldDate gives the start of each range in day and clock modes', () async {
      final oldest = _Listen('old', _ms(2025, 6, 1, 18));
      _writeListens(dir, [oldest, _Listen('new', _ms(2026, 3, 15, 9))]);
      final history = await _loadedHistory(dir);
      final customDate = DateRange(oldest: DateTime(2026, 2, 1), newest: DateTime(2026, 2, 10));

      expect(history.resolveOldDate(MostPlayedTimeRange.day, timeNow, true, null), DateTime(2026, 3, 15));
      expect(history.resolveOldDate(MostPlayedTimeRange.day, timeNow, false, null), DateTime(2026, 3, 14, 10));
      expect(history.resolveOldDate(MostPlayedTimeRange.week, timeNow, true, null), DateTime(2026, 3, 9));
      expect(history.resolveOldDate(MostPlayedTimeRange.allTime, timeNow, true, null), DateTime.fromMillisecondsSinceEpoch(oldest.dateAddedMS));
      expect(history.resolveOldDate(MostPlayedTimeRange.custom, timeNow, false, customDate), customDate.oldest);

      final january = DateTime(2026, 1, 20, 10);
      expect(history.resolveOldDate(MostPlayedTimeRange.month3, january, true, null), DateTime(2025, 11));
      expect(history.resolveOldDate(MostPlayedTimeRange.month6, january, true, null), DateTime(2025, 8));
    });

    test('a clock based day starts 24 hours before now', () async {
      _writeListens(dir, [
        _Listen('tooOld', _ms(2026, 3, 14, 0, 0, 1)),
        _Listen('yesterday', _ms(2026, 3, 14, 11)),
        _Listen('today', _ms(2026, 3, 15, 9)),
        _Listen('today', _ms(2026, 3, 15, 9, 30)),
      ]);
      final history = await _loadedHistory(dir);

      final top = history.getMostListensInTimeRange(
        mptr: MostPlayedTimeRange.day,
        isStartOfDay: false,
        mainItemToSubItem: history.mainItemToSubItem,
        timeNow: timeNow,
      );

      expect(top.keysSortedByValue.toList(), ['today', 'yesterday']);
      expect(top['today'], [_ms(2026, 3, 15, 9), _ms(2026, 3, 15, 9, 30)]);
    });

    test('a start of day range covers today only', () async {
      _writeListens(dir, [
        _Listen('yesterday', _ms(2026, 3, 14, 23)),
        _Listen('today', _ms(2026, 3, 15, 0, 5)),
      ]);
      final history = await _loadedHistory(dir);

      final top = history.getMostListensInTimeRange(
        mptr: MostPlayedTimeRange.day,
        isStartOfDay: true,
        mainItemToSubItem: history.mainItemToSubItem,
        timeNow: timeNow,
      );

      expect(top.keysSortedByValue.toList(), ['today']);
    });

    ListensSortedMap<String> topIn(_TestHistory history, DateRange range) => history.getMostListensInTimeRange(
          mptr: MostPlayedTimeRange.custom,
          isStartOfDay: true,
          customDate: range,
          mainItemToSubItem: history.mainItemToSubItem,
          timeNow: timeNow,
        );

    test('a custom range counts only the listens between its two instants', () async {
      final oldest = DateTime(2026, 3, 1, 15);
      final newest = DateTime(2026, 3, 5, 9, 30);
      final oldestMS = oldest.millisecondsSinceEpoch;
      final newestMS = newest.millisecondsSinceEpoch;
      _writeListens(dir, [
        _Listen('morningOfOldest', _ms(2026, 3, 1, 8)),
        _Listen('beforeOldest', oldestMS - 1),
        _Listen('atOldest', oldestMS),
        _Listen('eveningOfOldest', _ms(2026, 3, 1, 22)),
        _Listen('middleDay', _ms(2026, 3, 3, 12)),
        _Listen('earlyOfNewest', _ms(2026, 3, 5, 1)),
        _Listen('atNewest', newestMS),
        _Listen('afterNewest', newestMS + 1),
        _Listen('nightOfNewest', _ms(2026, 3, 5, 23)),
      ]);
      final history = await _loadedHistory(dir);

      const inRange = {'atOldest', 'eveningOfOldest', 'middleDay', 'earlyOfNewest', 'atNewest'};
      final top = topIn(history, DateRange(oldest: oldest, newest: newest));
      expect(top.keysSortedByValue.toSet(), inRange);
      final generated = history.generateTracksFromHistoryDates(oldest, newest);
      expect(generated.map((e) => e.id).toSet(), inRange);
    });

    test('a range inside one day is cut at both instants, a reversed one has nothing', () async {
      final listens = [8, 9, 10, 11, 12, 13].map((hour) => _Listen('h$hour', _ms(2026, 3, 15, hour))).toList();
      _writeListens(dir, listens);
      final history = await _loadedHistory(dir);
      final from = DateTime(2026, 3, 15, 9, 30);
      final to = DateTime(2026, 3, 15, 12);

      expect(topIn(history, DateRange(oldest: from, newest: to)).keysSortedByValue.toSet(), {'h10', 'h11', 'h12'});
      expect(history.generateTracksFromHistoryDates(from, to).map((e) => e.id).toList(), ['h12', 'h11', 'h10']);
      expect(topIn(history, DateRange(oldest: to, newest: from)).length, 0);
      expect(history.generateTracksFromHistoryDates(to, from), isEmpty);
    });

    test('picked days cover the first and the last day fully, a single day too', () async {
      _writeListens(dir, [
        _Listen('before', _ms(2026, 2, 28, 23, 59, 59) + 999),
        _Listen('firstDay', _ms(2026, 3, 1)),
        _Listen('lastDay', _ms(2026, 3, 5, 23, 59, 59) + 999),
        _Listen('after', _ms(2026, 3, 6)),
      ]);
      final history = await _loadedHistory(dir);

      final days = DateRange.wholeDays(oldest: DateTime(2026, 3, 1, 18), newest: DateTime(2026, 3, 5));
      expect(topIn(history, days).keysSortedByValue.toSet(), {'firstDay', 'lastDay'});
      expect(days.toDuration(), DateTime(2026, 3, 6).difference(DateTime(2026, 3, 1)));

      final singleDay = DateRange.wholeDays(oldest: DateTime(2026, 3, 5), newest: DateTime(2026, 3, 5));
      expect(topIn(history, singleDay).keysSortedByValue.toList(), ['lastDay']);
      expect(singleDay.toDuration(), DateTime(2026, 3, 6).difference(DateTime(2026, 3, 5)));
    });

    test('back to back ranges of one duration never share a listen', () async {
      const step = Duration(days: 1);
      final firstStart = DateTime(2026, 3, 1);
      final secondStart = firstStart.add(step);
      final secondStartMS = secondStart.millisecondsSinceEpoch;
      _writeListens(dir, [
        _Listen('endOfFirst', secondStartMS - 1),
        _Listen('startOfSecond', secondStartMS),
      ]);
      final history = await _loadedHistory(dir);

      final first = DateRange.ofDuration(oldest: firstStart, duration: step);
      final second = DateRange.ofDuration(oldest: secondStart, duration: step);
      expect(topIn(history, first).keysSortedByValue.toList(), ['endOfFirst']);
      expect(topIn(history, second).keysSortedByValue.toList(), ['startOfSecond']);
      expect(first.toDuration(), step);
    });

    test('a range of one instant still lasts a day, and day counts are whole days', () {
      final instant = DateTime(2026, 3, 15);
      final sameInstant = DateRange(oldest: instant, newest: instant);
      expect(sameInstant.toDurationSafe(), const Duration(days: 1));
      expect(sameInstant.toDaysSafe(), 1);

      final hourShortOfAWeek = DateRange.ofDuration(oldest: instant, duration: const Duration(days: 7, hours: -1));
      expect(hourShortOfAWeek.toDaysSafe(), 7);
      final march = DateRange.wholeDays(oldest: DateTime(2026, 3, 1), newest: DateTime(2026, 3, 31));
      expect(march.toDaysSafe(), 31);
    });

    test('history years include every year between the oldest and newest listens', () async {
      final history = _TestHistory(dir);
      await history.prepareHistoryFile();
      expect(history.getHistoryYears(), isEmpty);

      _writeListens(dir, [
        _Listen('a', _ms(2024, 12, 31, 23)),
        _Listen('b', _ms(2026, 1, 1, 0, 30)),
      ]);
      await history.prepareHistoryFile();
      expect(history.getHistoryYears(), [2026, 2025, 2024]);
    });

    test('a history with only unknown dates has no years, and the list can still be edited', () async {
      _writeListens(dir, const [_Listen('a', 0), _Listen('b', 5000)]);
      final history = await _loadedHistory(dir);

      final years = history.getHistoryYears();
      expect(years, isEmpty);
      expect(() => years.remove(1970), returnsNormally);
    });

    test('days since 1970 map back to the local midnight of the same day', () {
      for (final date in [DateTime(2026, 1, 1, 0, 30), DateTime(2026, 3, 29, 12), DateTime(2026, 4, 24, 23, 59), DateTime(2026, 10, 25, 1), DateTime(2026, 12, 31, 23, 30)]) {
        final day = date.millisecondsSinceEpoch.toDaysSince1970();
        expect(HistoryManager.daysSince1970ToDate(day), DateTime(date.year, date.month, date.day));
      }
    });
  });
}
