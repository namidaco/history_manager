/// ```dart
/// (itemsToScroll * Dimensions.itemHeight) + (daysToScroll * headerHeight)
/// ```
class HistoryScrollInfo {
  final int indexOfSmallList;
  final int dayToHighLight;
  final int itemsToScroll;
  final int daysToScroll;

  HistoryScrollInfo({
    required this.indexOfSmallList,
    required this.dayToHighLight,
    required this.itemsToScroll,
    required this.daysToScroll,
  });

  double toScrollOffset(double itemHeight, double headerHeight) {
    return (itemsToScroll * itemHeight) + (daysToScroll * headerHeight);
  }
}
