// ignore_for_file: non_constant_identifier_names

import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:dart_extensions/dart_extensions.dart';
import 'package:flutter/material.dart';

import 'package:get/get.dart';
import 'package:history_manager/src/models/history_scroll_info.dart';

import 'enums.dart';
import 'models/date_range.dart';
import 'models/item_with_date.dart';

/// Main Item gets stored inside main map, while Sub Item is used with most played maps.
///
/// History is saved in chunks by days.
mixin HistoryManager<T extends ItemWithDate, E> {
  E mainItemToSubItem(T item);
  Future<Map<int, List<T>>> prepareAllHistoryFilesFunction(
      String directoryPath);

  Map<String, dynamic> itemToJson(T item);

  /// Used for calculating total items extends.
  double get DAY_HEADER_HEIGHT_WITH_PADDING;

  String get HISTORY_DIRECTORY;

  double get trackTileItemExtent;

  MostPlayedTimeRange get currentMostPlayedTimeRange;
  DateRange get mostPlayedCustomDateRange;
  bool get mostPlayedCustomIsStartOfDay;

  // ============================================

  RxList<double> allItemsExtentsHistory = <double>[].obs;

  int get historyTracksLength =>
      historyMap.value.entries.fold(0, (sum, obj) => sum + obj.value.length);

  Iterable<T> get historyTracks sync* {
    for (final trs in historyMap.value.values) {
      yield* trs;
    }
  }

  T? get oldestTrack => historyMap.value[historyDays.lastOrNull]?.lastOrNull;
  T? get newestTrack => historyMap.value[historyDays.firstOrNull]?.firstOrNull;
  Iterable<int> get historyDays => historyMap.value.keys;

  /// History tracks mapped by [daysSinceEpoch].
  ///
  /// Sorted by newest date, i.e. newest list would be the first.
  ///
  /// For each List, the tracks are added to the first index, i.e. newest track would be the first.
  final Rx<SplayTreeMap<int, List<T>>> historyMap =
      SplayTreeMap<int, List<T>>((date1, date2) => date2.compareTo(date1)).obs;

  final RxMap<E, List<int>> topTracksMapListens = <E, List<int>>{}.obs;
  final RxMap<E, List<int>> topTracksMapListensTemp = <E, List<int>>{}.obs;
  Iterable<E> get currentMostPlayedTracks => currentTopTracksMapListens.keys;
  RxMap<E, List<int>> get currentTopTracksMapListens {
    final isAll = currentMostPlayedTimeRange == MostPlayedTimeRange.allTime;
    return isAll ? topTracksMapListens : topTracksMapListensTemp;
  }

  DateRange? get latestDateRange => _latestDateRange.value;
  final _latestDateRange = Rxn<DateRange>();

  final ScrollController scrollController = ScrollController();
  final Rxn<int> indexToHighlight = Rxn<int>();
  final Rxn<int> dayOfHighLight = Rxn<int>();

  HistoryScrollInfo getListenScrollPosition({
    required final int listenMS,
    final int extraItemsOffset = 2,
  }) {
    final daysKeys = historyDays.toList();
    daysKeys.removeWhere((element) => element <= listenMS.toDaysSince1970());
    final daysToScroll = daysKeys.length + 1;
    int itemsToScroll = 0;
    daysKeys.loop((e, index) {
      itemsToScroll += historyMap.value[e]?.length ?? 0;
    });
    final itemSmallList = historyMap.value[listenMS.toDaysSince1970()]!;
    final indexOfSmallList = itemSmallList.indexWhere(
        (element) => element.dateTimeAdded.millisecondsSinceEpoch == listenMS);
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
    if (_isLoadingHistory) {
      // after history full load, [addTracksToHistory] will be called to add tracks inside [_tracksToAddAfterHistoryLoad].
      _tracksToAddAfterHistoryLoad.addAll(tracks);
      return;
    }
    final daysToSave = addTracksToHistoryOnly(tracks);
    updateMostPlayedPlaylist(tracks);
    await saveHistoryToStorage(daysToSave);
  }

  /// adds [tracks] to [historyMap] and returns [daysToSave], to be used by [saveHistoryToStorage].
  ///
  /// By using this instead of [addTracksToHistory], you gurantee that you WILL call [updateMostPlayedPlaylist], [sortHistoryTracks] and [saveHistoryToStorage].
  /// Use this ONLY when adding large number of tracks at once, such as adding from youtube or lastfm history.
  List<int> addTracksToHistoryOnly(List<T> tracks) {
    final daysToSave = <int>[];
    tracks.loop((e, i) {
      final trackday = e.dateTimeAdded.toDaysSince1970();
      daysToSave.add(trackday);
      historyMap.value.insertForce(0, trackday, e);
    });
    calculateAllItemsExtentsInHistory();

    return daysToSave;
  }

  /// Sorts each [historyMap]'s value by newest.
  ///
  /// Providing [daysToSort] will sort these entries only.
  void sortHistoryTracks([List<int>? daysToSort]) {
    void sortTheseTracks(List<T> tracks) =>
        tracks.sortByReverse((e) => e.dateTimeAdded.millisecondsSinceEpoch);

    if (daysToSort != null) {
      for (int i = 0; i < daysToSort.length; i++) {
        final day = daysToSort[i];
        final trs = historyMap.value[day];
        if (trs != null) {
          sortTheseTracks(trs);
        }
      }
    }
    historyMap.value.forEach((key, value) {
      sortTheseTracks(value);
    });
  }

  Future<void> removeTracksFromHistory(List<T> tracksWithDates) async {
    final dayAndTracksToDeleteMap = <int, List<T>>{};
    tracksWithDates.loop((twd, index) {
      dayAndTracksToDeleteMap.addForce(
          twd.dateTimeAdded.toDaysSince1970(), twd);
    });
    final days = dayAndTracksToDeleteMap.keys.toList();
    days.loop((d, index) {
      final tracksInMap = historyMap.value[d] ?? [];
      final tracksToDelete = dayAndTracksToDeleteMap[d] ?? [];
      tracksToDelete.loop((ttd, index) {
        tracksInMap.remove(ttd);
        topTracksMapListens[mainItemToSubItem(ttd)]
            ?.remove(ttd.dateTimeAdded.millisecondsSinceEpoch);
      });
    });

    await saveHistoryToStorage(days);
    calculateAllItemsExtentsInHistory();
  }

  Future<void> replaceTheseTracksInHistory(
    bool Function(T e) test,
    T Function(T old) newElement,
  ) async {
    final daysToSave = <int>[];
    historyMap.value.entries.toList().loop((entry, index) {
      final day = entry.key;
      final trs = entry.value;
      trs.replaceWhere(
        test,
        newElement,
        onMatch: () => daysToSave.add(day),
      );
    });
    await saveHistoryToStorage(daysToSave);
    updateMostPlayedPlaylist();
  }

  /// Most Played Playlist, relies totally on History Playlist.
  /// Sending [track && dateTimeAdded] just adds it to the map and sort, it won't perform a re-lookup from history.
  void updateMostPlayedPlaylist([List<T>? tracksWithDate]) {
    void sortAndUpdateMap(Map<E, List<int>> unsortedMap,
        {Map<E, List<int>>? mapToUpdate}) {
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
      final fmap = mapToUpdate ?? unsortedMap;
      fmap
        ..clear()
        ..addEntries(sortedEntries);
      updateTempMostPlayedPlaylist();
    }

    if (tracksWithDate != null) {
      tracksWithDate.loop((twd, index) {
        topTracksMapListens.addForce(
            mainItemToSubItem(twd), twd.dateTimeAdded.millisecondsSinceEpoch);
      });

      sortAndUpdateMap(topTracksMapListens);
    } else {
      final Map<E, List<int>> tempMap = <E, List<int>>{};

      for (final t in historyTracks) {
        tempMap.addForce(
            mainItemToSubItem(t), t.dateTimeAdded.millisecondsSinceEpoch);
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

    _latestDateRange.value = customDateRange;

    final sortedEntries = getMostListensInTimeRange(
      mptr: mptr,
      isStartOfDay: isStartOfDay,
      customDate: customDateRange,
    );

    topTracksMapListensTemp
      ..clear()
      ..addEntries(sortedEntries);
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
            MostPlayedTimeRange.day:
                DateTime(timeNow.year, timeNow.month, timeNow.day),
            MostPlayedTimeRange.day3:
                DateTime(timeNow.year, timeNow.month, timeNow.day - 2),
            MostPlayedTimeRange.week:
                DateTime(timeNow.year, timeNow.month, timeNow.day - 6),
            MostPlayedTimeRange.month: DateTime(timeNow.year, timeNow.month),
            MostPlayedTimeRange.month3:
                DateTime(timeNow.year, timeNow.month - 2),
            MostPlayedTimeRange.month6:
                DateTime(timeNow.year, timeNow.month - 5),
            MostPlayedTimeRange.year: DateTime(timeNow.year),
            MostPlayedTimeRange.custom: customDate?.oldest,
          }
        : {
            MostPlayedTimeRange.allTime: null,
            MostPlayedTimeRange.day: DateTime.now(),
            MostPlayedTimeRange.day3: timeNow.subtract(const Duration(days: 3)),
            MostPlayedTimeRange.week: timeNow.subtract(const Duration(days: 7)),
            MostPlayedTimeRange.month:
                timeNow.subtract(const Duration(days: 30)),
            MostPlayedTimeRange.month3:
                timeNow.subtract(const Duration(days: 30 * 3)),
            MostPlayedTimeRange.month6:
                timeNow.subtract(const Duration(days: 30 * 6)),
            MostPlayedTimeRange.year:
                timeNow.subtract(const Duration(days: 365)),
            MostPlayedTimeRange.custom: customDate?.oldest,
          };

    final map = {
      for (final e in MostPlayedTimeRange.values) e: varMapOldestDate[e]
    };

    final newDate =
        mptr == MostPlayedTimeRange.custom ? customDate?.newest : timeNow;
    final oldDate = map[mptr];

    final betweenDates = generateTracksFromHistoryDates(
      oldDate,
      newDate,
      removeDuplicates: false,
    );

    final Map<E, List<int>> tempMap = <E, List<int>>{};

    betweenDates.loop((t, index) {
      tempMap.addForce(
          mainItemToSubItem(t), t.dateTimeAdded.millisecondsSinceEpoch);
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
  List<T> generateTracksFromHistoryDates(
      DateTime? oldestDate, DateTime? newestDate,
      {bool removeDuplicates = true}) {
    if (oldestDate == null || newestDate == null) return [];

    final tracksAvailable = <T>[];
    final entries = historyMap.value.entries.toList();

    final oldestDay = oldestDate.toDaysSince1970();
    final newestDay = newestDate.toDaysSince1970();

    entries.loop((entry, index) {
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
    Future<void> saveThisDay(int key, List<T> tracks) async {
      await File('$HISTORY_DIRECTORY$key.json')
          .writeAsJson(tracks.map((e) => itemToJson(e)).toList());
    }

    Future<void> deleteThisDay(int key) async {
      historyMap.value.remove(key);
      await File('$HISTORY_DIRECTORY$key.json').delete();
    }

    if (daysToSave != null) {
      daysToSave.removeDuplicates();
      for (int i = 0; i < daysToSave.length; i++) {
        final day = daysToSave[i];
        final trs = historyMap.value[day];
        if (trs == null) {
          printy('couldn\'t find [dayToSave] inside [historyMap]',
              isError: true);
          await deleteThisDay(day);
          continue;
        }
        if (trs.isEmpty) {
          await deleteThisDay(day);
        } else {
          await saveThisDay(day, trs);
        }
      }
    } else {
      historyMap.value.forEach((key, value) async {
        await saveThisDay(key, value);
      });
    }
    historyMap.refresh();
  }

  Future<void> prepareHistoryFile() async {
    final map = await prepareAllHistoryFilesFunction(HISTORY_DIRECTORY);
    historyMap.value
      ..clear()
      ..addAll(map);

    historyMap.refresh();
    _isLoadingHistory = false;
    // Adding tracks that were rejected by [addToHistory] since history wasn't fully loaded.
    if (_tracksToAddAfterHistoryLoad.isNotEmpty) {
      await addTracksToHistory(_tracksToAddAfterHistoryLoad);
      _tracksToAddAfterHistoryLoad.clear();
    }
    calculateAllItemsExtentsInHistory();
    updateMostPlayedPlaylist();
    _historyAndMostPlayedLoad.complete(true);
  }

  void calculateAllItemsExtentsInHistory() {
    final tie = trackTileItemExtent;
    final header = DAY_HEADER_HEIGHT_WITH_PADDING;
    allItemsExtentsHistory
      ..clear()
      ..addAll(historyMap.value.entries.map(
        (e) => header + (e.value.length * tie),
      ));
  }

  /// Used to add tracks that were rejected by [addToHistory] after full loading of history.
  ///
  /// This is an extremely rare case, would happen only if history loading took more than 20s. (min seconds to count a listen)
  final List<T> _tracksToAddAfterHistoryLoad = <T>[];
  bool _isLoadingHistory = true;
  bool get isLoadingHistory => _isLoadingHistory;

  final _historyAndMostPlayedLoad = Completer<bool>();
  Future<bool> get waitForHistoryAndMostPlayedLoad =>
      _historyAndMostPlayedLoad.future;
}
