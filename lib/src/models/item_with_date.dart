import 'package:history_manager/history_manager.dart';

abstract interface class ItemWithDate {
  int get dateAddedMS;
  TrackSource? get sourceNull;

  TrackSource get source => sourceNull ?? TrackSource.local;
}
