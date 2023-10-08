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
}
