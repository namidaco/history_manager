import 'package:history_manager/history_manager.dart';

mixin ItemWithDate {
  int get dateAddedMS;
  TrackSource? get sourceNull;

  TrackSource get source => sourceNull ?? TrackSource.local;
}
