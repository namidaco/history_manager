// ignore_for_file: non_constant_identifier_names, avoid_rx_value_getter_outside_obx

import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:dart_extensions/dart_extensions.dart';
import 'package:nampack/reactive/reactive.dart';

import 'package:history_manager/src/models/history_prepare_info.dart';
import 'package:history_manager/src/models/history_scroll_info.dart';
import 'package:history_manager/src/models/value_sorted_map.dart';

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

  Rx<MostPlayedTimeRange> get currentMostPlayedTimeRange;
  Rx<DateRange> get mostPlayedCustomDateRange;
  Rx<bool> get mostPlayedCustomIsStartOfDay;

  double daysToSectionExtent(List<int> days);

  double dayToSectionExtent(int day, double itemExtent, double headerExtent) {
    final tracksCount = historyMap.value[day]?.length ?? 0;
    return headerExtent + (tracksCount * itemExtent);
  }

  static int dayToMilliseconds(int day) => day * 24 * 60 * 60 * 1000;

  List<int> getHistoryYears() {
    final newestDaySinceEpoch = historyMap.value.keys.firstOrNull;
    final oldestDaySinceEpoch = historyMap.value.keys.lastOrNull;
    final newestYear = newestDaySinceEpoch == null ? 0 : DateTime.fromMillisecondsSinceEpoch(dayToMilliseconds(newestDaySinceEpoch)).year;
    final oldestYear = oldestDaySinceEpoch == null ? 0 : DateTime.fromMillisecondsSinceEpoch(dayToMilliseconds(oldestDaySinceEpoch)).year;

    final years = <int>[];
    final diff = (newestYear - oldestYear).abs();
    for (int i = 0; i <= diff; i++) {
      years.add(newestYear - i);
    }
    years.remove(0);
    return years;
  }

  // ============================================

  final totalHistoryItemsCount = (-1).obs;
  final modifiedDays = Rxn<void>();
  final latestUpdatedMostPlayedItem = Rxn<E>();
  void Function()? onTopItemsMapModified;

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

  /// History tracks mapped by `days since 1970`.
  ///
  /// Sorted by newest date, i.e. newest list would be the first.
  ///
  /// For each List, the tracks are added to the first index, i.e. newest track would be the first.
  final Rx<SplayTreeMap<int, List<T>>> historyMap = SplayTreeMap<int, List<T>>((date1, date2) => date2.compareTo(date1)).obs;

  final topTracksMapListens = ListensSortedMap<E>().obs;
  final topTracksMapListensTemp = ListensSortedMap<E>().obs;
  Iterable<E> get currentMostPlayedTracks => currentTopTracksMapListens.keysSortedByValue;
  ListensSortedMap<E> get currentTopTracksMapListens {
    final isAll = currentMostPlayedTimeRange.value == MostPlayedTimeRange.allTime;
    return isAll ? topTracksMapListens.value : topTracksMapListensTemp.value;
  }

  Rx<ListensSortedMap<E>> currentTopTracksMapListensReactive(MostPlayedTimeRange currentTimeRange) {
    final isAll = currentTimeRange == MostPlayedTimeRange.allTime;
    return isAll ? topTracksMapListens : topTracksMapListensTemp;
  }

  late final ScrollController scrollController = ScrollController();
  late final highlightedItem = Rxn<HistoryScrollInfo>();

  int? currentScrollPositionToDay(double itemExtent, double headerExtent, {double topPadding = 0.0}) {
    double? offsetPre = scrollController.positions.lastOrNull?.pixels;
    if (offsetPre == null || offsetPre <= 0) {
      final newestDay = historyMap.value.keys.firstOrNull;
      return newestDay;
    }
    offsetPre -= topPadding;
    double offsetToCover = 0;
    int? currentDay;
    for (final e in historyMap.value.entries) {
      currentDay = e.key;
      offsetToCover += headerExtent;
      if (offsetToCover >= offsetPre) break;
      final tracksCount = e.value.length;
      offsetToCover += tracksCount * itemExtent;
      if (offsetToCover >= offsetPre) break;
    }
    return currentDay;
  }

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
    final indexOfSmallList = itemSmallList.indexWhere((element) => element.dateAddedMS == listenMS);
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
  List<int> addTracksToHistoryOnly(List<T> tracks, {bool preventDuplicate = false}) {
    final daysToSave = <int>[];
    final map = historyMap.value;
    bool addedNewDay = false;
    int totalAdded = 0;
    tracks.loop((twd) {
      final day = twd.dateAddedMS.toDaysSince1970();
      final tracks = map[day];
      if (tracks != null) {
        if (preventDuplicate && tracks.contains(twd)) {
          // dont add
        } else {
          daysToSave.add(day);
          tracks.insert(0, twd);
          totalAdded++;
        }
      } else {
        daysToSave.add(day);
        map[day] = <T>[twd];
        addedNewDay = true;
        totalAdded++;
      }
    });

    if (totalAdded > 0) totalHistoryItemsCount.value += totalAdded;
    if (addedNewDay) modifiedDays.refresh();
    return daysToSave;
  }

  int removeDuplicatedItemsAllowMultiSourceDuplicates([List<int> inDays = const []]) {
    final map = historyMap.value;
    int totalRemoved = 0;

    if (inDays.isNotEmpty) {
      for (int i = 0; i < inDays.length; i++) {
        final day = inDays[i];
        final trs = map[day];
        if (trs != null) {
          totalRemoved += trs.removeDuplicates();
        }
      }
    } else {
      map.forEach((key, value) {
        totalRemoved += value.removeDuplicates();
      });
    }

    if (totalRemoved > 0) totalHistoryItemsCount.value -= totalRemoved;
    historyMap.refresh();
    return totalRemoved;
  }

  int removeDuplicatedItems([List<int> inDays = const []]) {
    final map = historyMap.value;
    int totalRemoved = 0;

    if (inDays.isNotEmpty) {
      for (int i = 0; i < inDays.length; i++) {
        final day = inDays[i];
        final trs = map[day];
        if (trs != null) {
          totalRemoved += _removeDuplicatesFromList(trs);
        }
      }
    } else {
      map.forEach((key, value) {
        totalRemoved += _removeDuplicatesFromList(value);
      });
    }

    if (totalRemoved > 0) totalHistoryItemsCount.value -= totalRemoved;
    historyMap.refresh();
    return totalRemoved;
  }

  // this whole mess is to prevent duplicates caused by namida reporting listens to official yt.
  // after importing yt takeouts, there will be listen duplicates with time difference (namida listen date vs yt listen date)
  int _removeDuplicatesFromList(List<T> tracks) {
    if (tracks.isEmpty) return 0;

    const millisecondsToIgnore = 280 * 1000;
    final lengthBefore = tracks.length;
    final alrExistingMap = <int, List<(T, int)>>{};
    final indicesToRemove = <int>[];
    bool shouldRemove(T tr, int i, int dateNormalized) {
      final alrExistingOnes = alrExistingMap[dateNormalized];
      if (alrExistingOnes != null &&
          alrExistingOnes.any(
            (existingInfo) {
              final existing = existingInfo.$1;
              if (existing == tr) return true;

              final existingSub = mainItemToSubItem(existing);
              final trSub = mainItemToSubItem(tr);
              if (existingSub == trSub) {
                if (existing.sourceNull == tr.sourceNull) {
                  return false;
                }
                if (existing.sourceNull == null && tr.sourceNull != null) {
                  tracks[existingInfo.$2] = tr; // replace the earlier track..
                  return true; // .. and remove current
                } else if (existing.sourceNull != null) {
                  return true;
                }
                return false;
              }
              return false;
            },
          )) {
        return true;
      }
      return false;
    }

    for (var i = 0; i < tracks.length; i++) {
      final tr = tracks[i];
      final dateNormalized = tr.dateAddedMS ~/ millisecondsToIgnore;
      if (shouldRemove(tr, i, dateNormalized)) {
        indicesToRemove.add(i);
      } else {
        alrExistingMap[dateNormalized] ??= [];
        alrExistingMap[dateNormalized]!.add((tr, i));
      }
    }
    indicesToRemove.reverseLoop((item) => tracks.removeAt(item));
    final lengthAfter = tracks.length;
    return lengthBefore - lengthAfter;
  }

  /// Sorts each [historyMap]'s value by newest.
  ///
  /// Providing [daysToSort] will sort these entries only.
  void sortHistoryTracks([List<int>? daysToSort]) {
    void sortTheseTracks(List<T> tracks) => tracks.sortByReverse((e) => e.dateAddedMS);

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
      final day = twd.dateAddedMS.toDaysSince1970();
      final didRemove = map[day]?.remove(twd) ?? false;
      if (didRemove) {
        daysToSave.add(day);
        var subitem = mainItemToSubItem(twd);
        topTracksMapListens.value.removeElement(subitem, twd.dateAddedMS);
        latestUpdatedMostPlayedItem.value = subitem;
        totalRemoved++;
      }
    });

    if (totalRemoved > 0) {
      totalHistoryItemsCount.value -= totalRemoved;
      historyMap.refresh();
      topTracksMapListens.refresh();
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
    if (tracksWithDate != null) {
      tracksWithDate.loop((twd) {
        var subitem = mainItemToSubItem(twd);
        topTracksMapListens.value.addElement(subitem, twd.dateAddedMS);
        latestUpdatedMostPlayedItem.value = subitem;
      });
    } else {
      final Map<E, List<int>> tempMap = <E, List<int>>{};

      for (final t in historyTracks) {
        tempMap.addForce(mainItemToSubItem(t), t.dateAddedMS);
      }

      topTracksMapListens.value.assignAll(tempMap);
      topTracksMapListens.value.sortAllInternalLists();

      onTopItemsMapModified?.call();
    }

    topTracksMapListens.refresh();
    updateTempMostPlayedPlaylist();
  }

  void updateTempMostPlayedPlaylist({
    DateRange? customDateRange,
    MostPlayedTimeRange? mptr,
    bool? isStartOfDay,
  }) {
    mptr ??= currentMostPlayedTimeRange.value;
    customDateRange ??= mostPlayedCustomDateRange.value;
    isStartOfDay ??= mostPlayedCustomIsStartOfDay.value;

    if (mptr == MostPlayedTimeRange.allTime) {
      topTracksMapListensTemp.value.clear();
    } else {
      final sortedEntries = getMostListensInTimeRange(
        mptr: mptr,
        isStartOfDay: isStartOfDay,
        customDate: customDateRange,
        mainItemToSubItem: mainItemToSubItem,
      );
      topTracksMapListensTemp.value = sortedEntries;
    }

    topTracksMapListens.refresh();
    topTracksMapListensTemp.refresh();
  }

  ListensSortedMap<E2> getMostListensInTimeRange<E2>({
    required MostPlayedTimeRange mptr,
    required bool isStartOfDay,
    DateRange? customDate,
    required E2 Function(T item) mainItemToSubItem,
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

    final tempMap = <E2, List<int>>{};

    betweenDates.loop((t) {
      tempMap.addForce(mainItemToSubItem(t), t.dateAddedMS);
    });

    final topItems = ListensSortedMap<E2>();
    topItems.assignAll(tempMap);
    topItems.sortAllInternalLists();
    return topItems;
  }

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
    onTopItemsMapModified?.call();
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
