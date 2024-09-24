# Simple & Efficient history tracker dart mixin.

> - items are stored & accessed as days chunks
> - days are sorted decendingly as days since 1970 (newer at first)
> - for each list, items are added to the first index, i.e. newest item would be the first.


- see [history_controller.dart](https://github.com/namidaco/namida/blob/main/lib/controller/history_controller.dart) & [playlist_tracks_subpage.dart#L34](https://github.com/namidaco/namida/blob/2ef6cd749499332565fd46bb95bb84c571b676f9/lib/ui/pages/subpages/playlist_tracks_subpage.dart#L34) in namida to understand how to efficiently access, display & modify history.

### Example class
```dart
// ignore_for_file: non_constant_identifier_names

import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:history_manager/history_manager.dart';
import 'package:dart_extensions/dart_extensions.dart';

class HistoryController with HistoryManager<TrackWithDate, Track> {
  static HistoryController get instance => _instance;
  static final HistoryController _instance = HistoryController._internal();
  HistoryController._internal();

  @override
  double daysToSectionExtent(List<int> days) {
    final trackTileExtent = Dimensions.inst.trackTileItemExtent;
    const dayHeaderExtent = kHistoryDayHeaderHeightWithPadding;
    double total = 0;
    days.loop((day) => total += dayToSectionExtent(day, trackTileExtent, dayHeaderExtent));
    return total;
  }

  @override
  Future<HistoryPrepareInfo<TrackWithDate, Track>> prepareAllHistoryFilesFunction(String directoryPath) async {
    return await compute(_readHistoryFilesCompute, directoryPath);
  }

  static Future<HistoryPrepareInfo<TrackWithDate, Track>> _readHistoryFilesCompute(String path) async {
    final map = SplayTreeMap<int, List<TrackWithDate>>((date1, date2) => date2.compareTo(date1));
    final tempMapTopItems = <Track, List<int>>{};
    int totalCount = 0;
    final files = Directory(path).listSync();
    final filesL = files.length;
    for (int i = 0; i < filesL; i++) {
      var f = files[i];
      if (f is File) {
        try {
          final response = f.readAsJsonSync();
          final dayOfTrack = int.parse(f.path.getFilenameWOExt);
          final listTracks = <TrackWithDate>[];
          (response as List?)?.loop((e) {
            var twd = TrackWithDate.fromJson(e);
            listTracks.add(twd);
            tempMapTopItems.addForce(twd.track, twd.dateTimeAdded.millisecondsSinceEpoch);
          });
          map[dayOfTrack] = listTracks;
          totalCount += listTracks.length;
        } catch (_) {}
      }
    }

    // -- Sorting dates
    for (final entry in tempMapTopItems.values) {
      entry.sort();
    }

    final sortedEntries = tempMapTopItems.entries.toList()
      ..sort((a, b) {
        final compare = b.value.length.compareTo(a.value.length);
        if (compare == 0) {
          final lastListenB = b.value.lastOrNull ?? 0;
          final lastListenA = a.value.lastOrNull ?? 0;
          return lastListenB.compareTo(lastListenA);
        }
        return compare;
      });
    final topItems = Map.fromEntries(sortedEntries);

    return HistoryPrepareInfo(
      historyMap: map,
      topItems: topItems,
      totalItemsCount: totalCount,
    );
  }

  @override
  String get HISTORY_DIRECTORY => AppDirs.HISTORY_PLAYLIST;

  @override
  Map<String, dynamic> itemToJson(TrackWithDate item) => item.toJson();

  @override
  Track mainItemToSubItem(TrackWithDate item) => item.track;

  @override
  MostPlayedTimeRange get currentMostPlayedTimeRange => settings.mostPlayedTimeRange.value;

  @override
  DateRange get mostPlayedCustomDateRange => settings.mostPlayedCustomDateRange.value;

  @override
  bool get mostPlayedCustomIsStartOfDay => settings.mostPlayedCustomisStartOfDay.value;
}

```


### Example Usage
```dart
// initialize in main
await HistoryController.inst.prepareHistoryFile();

final itemToAdd = TrackWithDate(
  date: DateTime.now(),
  track: Track('my_track'),
);
await HistoryController.instance.addTracksToHistory([itemToAdd]);
```


### License
Project is licensed under [GPL3](LICENSE)