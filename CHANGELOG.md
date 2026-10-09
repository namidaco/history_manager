## 1.8.0

- Most played lists keep one entry per item with the right first and last listen, listens are inserted in order and items left without listens are removed
- Removing every source deletes the day files
- Time ranges are exact to the millisecond, `DateRange.wholeDays` for whole day picks
- Duplicated listens are found across time bucket edges, a day stays sorted when a duplicate replaces a listen
- An empty day list dedupes and sorts no days, only null means every day
- Removals and replacements wait for a running import instead of being overwritten by it
- Listens with unknown dates no longer count as the oldest day
- `ListensSortedMap.sortAllInternalLists` is removed, `assignAll` sorts on its own
