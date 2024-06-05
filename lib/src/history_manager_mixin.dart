// ignore_for_file: non_constant_identifier_names, avoid_rx_value_getter_outside_obx

import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:dart_extensions/dart_extensions.dart';
import 'package:flutter/material.dart';
import 'package:history_manager/src/models/history_prepare_info.dart';
import 'package:history_manager/src/models/history_scroll_info.dart';
import 'package:nampack/reactive/reactive.dart';

import 'enums.dart';
import 'models/date_range.dart';
import 'models/item_with_date.dart';

/// Main Item gets stored inside main map, while Sub Item is used with most played maps.
///
/// History is saved in chunks by days.
mixin HistoryManager<T extends ItemWithDate, E> {
  E mainItemToSubItem(T item);

  /// Return history map along with sorted entries, See [updateMostPlayedPlaylist] for sorting.
  Future<HistoryPrepareInfo<T, E>> prepareAllHistoryFilesFunction(String directoryPath);

  Map<String, dynamic> itemToJson(T item);

  String get HISTORY_DIRECTORY;

  MostPlayedTimeRange get currentMostPlayedTimeRange;
  DateRange get mostPlayedCustomDateRange;
  bool get mostPlayedCustomIsStartOfDay;

  double daysToSectionExtent(List<int> days);

  double dayToSectionExtent(int day, double itemExtent, double headerExtent) {
    final tracksCount = historyMap.value[day]?.length ?? 0;
    return headerExtent + (tracksCount * itemExtent);
  }

  // ============================================

  final totalHistoryItemsCount = (-1).obs;
  final modifiedDays = Rxn<void>();

  Iterable<T> get historyTracks sync* {
    final map = historyMap.value;
    for (final trs in map.values) {
      yield* trs;
    }
  }

  Iterable<T> get historyTracksR sync* {
    final map = historyMap.valueR;
    for (final trs in map.values) {
      yield* trs;
    }
  }

  T? get oldestTrack => historyMap.value.values.lastOrNull?.lastOrNull;
  T? get newestTrack => historyMap.value.values.firstOrNull?.firstOrNull;
  Iterable<int> get historyDays => historyMap.value.keys;

  T? get oldestTrackR => historyMap.valueR.values.lastOrNull?.lastOrNull;
  T? get newestTrackR => historyMap.valueR.values.firstOrNull?.firstOrNull;
  Iterable<int> get historyDaysR => historyMap.valueR.keys;

  /// History tracks mapped by `days since epoch`.
  ///
  /// Sorted by newest date, i.e. newest list would be the first.
  ///
  /// For each List, the tracks are added to the first index, i.e. newest track would be the first.
  final Rx<SplayTreeMap<int, List<T>>> historyMap = SplayTreeMap<int, List<T>>((date1, date2) => date2.compareTo(date1)).obs;

  final RxMap<E, List<int>> topTracksMapListens = <E, List<int>>{}.obs;
  final RxMap<E, List<int>> topTracksMapListensTemp = <E, List<int>>{}.obs;
  Iterable<E> get currentMostPlayedTracks => currentTopTracksMapListens.keys;
  RxMap<E, List<int>> get currentTopTracksMapListens {
    final isAll = currentMostPlayedTimeRange == MostPlayedTimeRange.allTime;
    return isAll ? topTracksMapListens : topTracksMapListensTemp;
  }

  late final ScrollController scrollController = ScrollController();
  late final Rxn<int> indexToHighlight = Rxn<int>();
  late final Rxn<int> dayOfHighLight = Rxn<int>();

  HistoryScrollInfo getListenScrollPosition({
    required final int listenMS,
    final int extraItemsOffset = 2,
  }) {
    final daysKeys = historyDays.toList();
    daysKeys.removeWhere((element) => element <= listenMS.toDaysSince1970());
    final daysToScroll = daysKeys.length + 1;
    int itemsToScroll = 0;
    daysKeys.loop((e) {
      itemsToScroll += historyMap.value[e]?.length ?? 0;
    });
    final itemSmallList = historyMap.value[listenMS.toDaysSince1970()]!;
    final indexOfSmallList = itemSmallList.indexWhere((element) => element.dateTimeAdded.millisecondsSinceEpoch == listenMS);
    itemsToScroll += indexOfSmallList;
    itemsToScroll -= extraItemsOffset;

    return HistoryScrollInfo(
      indexOfSmallList: indexOfSmallList,
      dayToHighLight: listenMS.toDaysSince1970(),
      itemsToScroll: itemsToScroll,
      daysToScroll: daysToScroll,
    );
  }

  Future<void> addTracksToHistory(List<T> tracks) async {
    if (isLoadingHistory || _isIdle) {
      // after history full load, [addTracksToHistory] will be called to add tracks inside [_tracksToAddAfterHistoryLoad].
      _tracksToAddAfterHistoryLoad.addAll(tracks);
      return;
    }
    final daysToSave = addTracksToHistoryOnly(tracks);
    updateMostPlayedPlaylist(tracks);
    historyMap.refresh();
    await saveHistoryToStorage(daysToSave);
  }

  /// adds [tracks] to [historyMap] and returns [daysToSave], to be used by [saveHistoryToStorage].
  ///
  /// By using this instead of [addTracksToHistory], you gurantee that you WILL call:
  /// [updateMostPlayedPlaylist], [sortHistoryTracks], [saveHistoryToStorage].
  /// Use this ONLY when continuously adding large number of tracks in a short span, such as adding from youtube or lastfm history.
  List<int> addTracksToHistoryOnly(List<T> tracks) {
    final daysToSave = <int>[];
    final map = historyMap.value;
    bool addedNewDay = false;
    int totalAdded = 0;
    tracks.loop((twd) {
      final day = twd.dateTimeAdded.toDaysSince1970();
      daysToSave.add(day);
      if (map.containsKey(day)) {
        map[day]!.insert(0, twd);
      } else {
        map[day] = <T>[twd];
        addedNewDay = true;
      }
      totalAdded++;
    });

    if (totalAdded > 0) totalHistoryItemsCount.value += totalAdded;
    if (addedNewDay) modifiedDays.refresh();
    return daysToSave;
  }

  void removeDuplicatedItems([List<int> inDays = const []]) {
    final map = historyMap.value;
    int totalRemoved = 0;

    if (inDays.isNotEmpty) {
      for (int i = 0; i < inDays.length; i++) {
        final day = inDays[i];
        final trs = map[day];
        if (trs != null) {
          totalRemoved -= trs.removeDuplicates();
        }
      }
    } else {
      map.forEach((key, value) {
        totalRemoved -= value.removeDuplicates();
      });
    }

    if (totalRemoved > 0) totalHistoryItemsCount.value -= totalRemoved;
    historyMap.refresh();
  }

  /// Sorts each [historyMap]'s value by newest.
  ///
  /// Providing [daysToSort] will sort these entries only.
  void sortHistoryTracks([List<int>? daysToSort]) {
    void sortTheseTracks(List<T> tracks) => tracks.sortByReverse((e) => e.dateTimeAdded.millisecondsSinceEpoch);

    final map = historyMap.value;

    if (daysToSort != null) {
      for (int i = 0; i < daysToSort.length; i++) {
        final day = daysToSort[i];
        final trs = map[day];
        if (trs != null) {
          sortTheseTracks(trs);
        }
      }
    } else {
      map.forEach((key, value) {
        sortTheseTracks(value);
      });
    }
    historyMap.refresh();
  }

  Future<void> removeTracksFromHistory(List<T> tracksWithDates) async {
    final daysToSave = <int>[];
    final map = historyMap.value;
    int totalRemoved = 0;

    tracksWithDates.loop((twd) {
      final day = twd.dateTimeAdded.toDaysSince1970();
      final didRemove = map[day]?.remove(twd) ?? false;
      if (didRemove) {
        daysToSave.add(day);
        topTracksMapListens[mainItemToSubItem(twd)]?.remove(twd.dateTimeAdded.millisecondsSinceEpoch);
        totalRemoved++;
      }
    });

    if (totalRemoved > 0) {
      totalHistoryItemsCount.value -= totalRemoved;
      historyMap.refresh();
      await saveHistoryToStorage(daysToSave);
    }
  }

  Future<void> replaceTheseTracksInHistory(
    bool Function(T e) test,
    T Function(T old) newElement,
  ) async {
    final daysToSave = <int>[];
    historyMap.value.entries.toList().loop((entry) {
      final day = entry.key;
      final trs = entry.value;
      trs.replaceWhere(
        test,
        newElement,
        onMatch: () => daysToSave.add(day),
      );
    });
    historyMap.refresh();
    updateMostPlayedPlaylist();
    await saveHistoryToStorage(daysToSave);
  }

  /// Most Played Playlist, relies totally on History Playlist.
  /// Sending [track && dateTimeAdded] just adds it to the map and sort, it won't perform a re-lookup from history.
  void updateMostPlayedPlaylist([List<T>? tracksWithDate]) {
    void sortAndUpdateMap(Map<E, List<int>> unsortedMap, {RxMap<E, List<int>>? mapToUpdate}) {
      final sortedEntries = unsortedMap.entries.toList()
        ..sort((a, b) {
          final compare = b.value.length.compareTo(a.value.length);
          if (compare == 0) {
            final lastListenB = b.value.lastOrNull ?? 0;
            final lastListenA = a.value.lastOrNull ?? 0;
            return lastListenB.compareTo(lastListenA);
          }
          return compare;
        });
      if (mapToUpdate != null) {
        mapToUpdate.assignAllEntries(sortedEntries);
      } else {
        unsortedMap.assignAllEntries(sortedEntries);
      }

      updateTempMostPlayedPlaylist();
    }

    if (tracksWithDate != null) {
      tracksWithDate.loop((twd) {
        topTracksMapListens.addForce(mainItemToSubItem(twd), twd.dateTimeAdded.millisecondsSinceEpoch);
      });

      sortAndUpdateMap(topTracksMapListens.value);
    } else {
      final Map<E, List<int>> tempMap = <E, List<int>>{};

      for (final t in historyTracks) {
        tempMap.addForce(mainItemToSubItem(t), t.dateTimeAdded.millisecondsSinceEpoch);
      }

      /// Sorting dates
      for (final entry in tempMap.values) {
        entry.sort();
      }

      sortAndUpdateMap(tempMap, mapToUpdate: topTracksMapListens);
    }
  }

  void updateTempMostPlayedPlaylist({
    DateRange? customDateRange,
    MostPlayedTimeRange? mptr,
    bool? isStartOfDay,
  }) {
    mptr ??= currentMostPlayedTimeRange;
    customDateRange ??= mostPlayedCustomDateRange;
    isStartOfDay ??= mostPlayedCustomIsStartOfDay;

    if (mptr == MostPlayedTimeRange.allTime) {
      topTracksMapListensTemp.clear();
      return;
    }

    final sortedEntries = getMostListensInTimeRange(
      mptr: mptr,
      isStartOfDay: isStartOfDay,
      customDate: customDateRange,
    );

    topTracksMapListensTemp.assignAllEntries(sortedEntries);
  }

  List<MapEntry<E, List<int>>> getMostListensInTimeRange({
    required MostPlayedTimeRange mptr,
    required bool isStartOfDay,
    DateRange? customDate,
  }) {
    final timeNow = DateTime.now();

    final varMapOldestDate = isStartOfDay
        ? {
            MostPlayedTimeRange.allTime: null,
            MostPlayedTimeRange.day: DateTime(timeNow.year, timeNow.month, timeNow.day),
            MostPlayedTimeRange.day3: DateTime(timeNow.year, timeNow.month, timeNow.day - 2),
            MostPlayedTimeRange.week: DateTime(timeNow.year, timeNow.month, timeNow.day - 6),
            MostPlayedTimeRange.month: DateTime(timeNow.year, timeNow.month),
            MostPlayedTimeRange.month3: DateTime(timeNow.year, timeNow.month - 2),
            MostPlayedTimeRange.month6: DateTime(timeNow.year, timeNow.month - 5),
            MostPlayedTimeRange.year: DateTime(timeNow.year),
            MostPlayedTimeRange.custom: customDate?.oldest,
          }
        : {
            MostPlayedTimeRange.allTime: null,
            MostPlayedTimeRange.day: DateTime.now(),
            MostPlayedTimeRange.day3: timeNow.subtract(const Duration(days: 3)),
            MostPlayedTimeRange.week: timeNow.subtract(const Duration(days: 7)),
            MostPlayedTimeRange.month: timeNow.subtract(const Duration(days: 30)),
            MostPlayedTimeRange.month3: timeNow.subtract(const Duration(days: 30 * 3)),
            MostPlayedTimeRange.month6: timeNow.subtract(const Duration(days: 30 * 6)),
            MostPlayedTimeRange.year: timeNow.subtract(const Duration(days: 365)),
            MostPlayedTimeRange.custom: customDate?.oldest,
          };

    final map = {for (final e in MostPlayedTimeRange.values) e: varMapOldestDate[e]};

    final newDate = mptr == MostPlayedTimeRange.custom ? customDate?.newest : timeNow;
    final oldDate = map[mptr];

    final betweenDates = generateTracksFromHistoryDates(
      oldDate,
      newDate,
      removeDuplicates: false,
    );

    final Map<E, List<int>> tempMap = <E, List<int>>{};

    betweenDates.loop((t) {
      tempMap.addForce(mainItemToSubItem(t), t.dateTimeAdded.millisecondsSinceEpoch);
    });

    for (final entry in tempMap.values) {
      entry.sort();
    }

    final sortedEntries = tempMap.entries.toList()
      ..sort((a, b) {
        final compare = b.value.length.compareTo(a.value.length);
        if (compare == 0) {
          final lastListenB = b.value.lastOrNull ?? 0;
          final lastListenA = a.value.lastOrNull ?? 0;
          return lastListenB.compareTo(lastListenA);
        }
        return compare;
      });
    return sortedEntries;
  }

  /// if [maxCount == null], it will return all available tracks
  List<T> generateTracksFromHistoryDates(DateTime? oldestDate, DateTime? newestDate, {bool removeDuplicates = true}) {
    if (oldestDate == null || newestDate == null) return [];

    final tracksAvailable = <T>[];
    final entries = historyMap.value.entries.toList();

    final oldestDay = oldestDate.toDaysSince1970();
    final newestDay = newestDate.toDaysSince1970();

    entries.loop((entry) {
      final day = entry.key;
      if (day >= oldestDay && day <= newestDay) {
        tracksAvailable.addAll(entry.value);
      }
    });
    if (removeDuplicates) {
      tracksAvailable.removeDuplicates(mainItemToSubItem);
    }

    return tracksAvailable;
  }

  Future<void> saveHistoryToStorage([List<int>? daysToSave]) async {
    final map = historyMap.value;
    bool removedDay = false;
    Future<void> saveThisDay(int key, List<T> tracks) async {
      await File('$HISTORY_DIRECTORY$key.json').writeAsJson(tracks.map((e) => itemToJson(e)).toList());
    }

    Future<void> deleteThisDay(int key) async {
      map.remove(key);
      removedDay = true;
      await File('$HISTORY_DIRECTORY$key.json').delete();
    }

    if (daysToSave != null) {
      daysToSave.removeDuplicates();
      for (int i = 0; i < daysToSave.length; i++) {
        final day = daysToSave[i];
        final trs = map[day];
        try {
          if (trs == null) {
            printy('couldn\'t find [dayToSave] inside [historyMap]', isError: true);
            await deleteThisDay(day);
            continue;
          }
          if (trs.isEmpty) {
            await deleteThisDay(day);
          } else {
            await saveThisDay(day, trs);
          }
        } catch (_) {
          continue;
        }
      }
    } else {
      map.forEach((key, value) async {
        await saveThisDay(key, value);
      });
    }
    if (removedDay) modifiedDays.refresh();
  }

  Future<void> prepareHistoryFile() async {
    final res = await prepareAllHistoryFilesFunction(HISTORY_DIRECTORY);
    historyMap.value = res.historyMap;
    topTracksMapListens.value = res.topItems;
    totalHistoryItemsCount.value = res.totalItemsCount;
    modifiedDays.refresh();
    updateTempMostPlayedPlaylist();
    // Adding tracks that were rejected by [addToHistory] since history wasn't fully loaded.
    if (_tracksToAddAfterHistoryLoad.isNotEmpty) {
      await addTracksToHistory(_tracksToAddAfterHistoryLoad);
      _tracksToAddAfterHistoryLoad.clear();
    }
    if (!_historyAndMostPlayedLoad.isCompleted) _historyAndMostPlayedLoad.complete(true);
  }

  /// Indicates wether the history should add items to the map normally.
  ///
  /// You should set this to true while modifying a copy of the history,
  /// and then setting it to false to re-add items that were waiting
  Future<void> setIdleStatus(bool idle) async {
    if (idle) {
      _isIdle = true;
    } else {
      _isIdle = false;
      if (_tracksToAddAfterHistoryLoad.isNotEmpty) {
        await addTracksToHistory(_tracksToAddAfterHistoryLoad);
        _tracksToAddAfterHistoryLoad.clear();
      }
    }
  }

  bool _isIdle = false;

  /// Used to add tracks that were rejected by [addToHistory] after full loading of history.
  ///
  /// This is an extremely rare case, would happen only if history loading took more than 20s. (min seconds to count a listen)
  final List<T> _tracksToAddAfterHistoryLoad = <T>[];
  bool get isLoadingHistory => totalHistoryItemsCount.value == -1;
  bool get isLoadingHistoryR => totalHistoryItemsCount.valueR == -1;

  final _historyAndMostPlayedLoad = Completer<bool>();
  Future<bool> get waitForHistoryAndMostPlayedLoad => _historyAndMostPlayedLoad.future;
  bool get isHistoryLoaded => _historyAndMostPlayedLoad.isCompleted;
}
