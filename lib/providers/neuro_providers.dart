import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../models/neuro_item.dart';
import '../services/hive_storage_service.dart';
import '../services/aggregation_engine.dart';
import '../services/cloud_sync_service.dart';

final storageServiceProvider = Provider<HiveStorageService>((ref) {
  return HiveStorageService();
});

final cloudSyncServiceProvider = Provider<CloudSyncService>((ref) {
  final storage = ref.watch(storageServiceProvider);
  final syncService = CloudSyncService(storage);
  ref.onDispose(() => syncService.dispose());
  return syncService;
});

class NeuroItemsNotifier extends StateNotifier<List<NeuroItem>> {
  final HiveStorageService _storage;
  final CloudSyncService? _cloudSync;
  final _uuid = const Uuid();

  NeuroItemsNotifier(this._storage, [this._cloudSync]) : super([]) {
    _loadItems();
    _cloudSync?.onRemoteDataUpdated = (items, categories) {
      state = items;
    };
  }

  void setItems(List<NeuroItem> items) {
    state = items;
  }

  void _persistAndSync(String actionType, [Map<String, dynamic>? payload]) {
    _storage.saveAllItems(state);
    final user = _storage.getCurrentUser();
    if (user != null && !user.isGuest && _cloudSync != null) {
      _cloudSync.syncAction(
        userId: user.id,
        actionType: actionType,
        payload: payload ?? {'count': state.length},
        currentLocalItems: state,
        currentLocalCategories: _storage.getDailyCategories(),
      );
    }
  }

  void _loadItems() {
    final loaded = _storage.getAllItems();
    if (loaded.isEmpty && !_storage.hasSeeded) {
      _seedDefaultData();
    } else {
      state = loaded;
    }
  }

  void _seedDefaultData() {
    _storage.setSeeded();
    final today = DateTime.now();
    final todayDateOnly = DateTime(today.year, today.month, today.day);

    final visionId1 = _uuid.v4();
    final visionId2 = _uuid.v4();
    final goalId = _uuid.v4();
    final morningFolderId = _uuid.v4();
    final eveningFolderId = _uuid.v4();

    final defaultItems = [
      // Sample Visions (Button 1 Master Planning Folders)
      NeuroItem(
        id: visionId1,
        title: 'Career & Financial Growth',
        description: 'Macro vision container for professional milestones',
        type: NeuroItemType.vision,
        priority: 1,
        startDate: todayDateOnly,
        colorHex: 0xFF38BDF8,
      ),
      NeuroItem(
        id: visionId2,
        title: 'Health & Wellness Vision',
        description: 'Physical & mental health optimization',
        type: NeuroItemType.vision,
        priority: 2,
        startDate: todayDateOnly,
        colorHex: 0xFF34D399,
      ),

      // Goal & Tasks under Health Vision
      NeuroItem(
        id: goalId,
        title: 'Establish Daily Wellness Habits',
        description: 'Building consistent daily focus micro-habits',
        type: NeuroItemType.goal,
        parentId: visionId2,
        rootVisionId: visionId2,
      ),
      NeuroItem(
        id: _uuid.v4(),
        title: 'Drink 500ml Water Upon Waking',
        type: NeuroItemType.task,
        parentId: goalId,
        rootVisionId: visionId2,
        isCompleted: true,
        completedAt: todayDateOnly,
      ),

      // Sample Routine Folders (Button 2 Master Planning Folders)
      NeuroItem(
        id: morningFolderId,
        title: 'Morning Focus & Energy Routine',
        description: 'Kickstart your day with dopamine-boosting micro habits',
        type: NeuroItemType.routineFolder,
        priority: 1,
        startDate: todayDateOnly,
        colorHex: 0xFF38BDF8,
      ),
      NeuroItem(
        id: eveningFolderId,
        title: 'Evening Wind-Down Routine',
        description: 'Calm the mind and prepare for rest',
        type: NeuroItemType.routineFolder,
        priority: 2,
        startDate: todayDateOnly,
        colorHex: 0xFF818CF8,
      ),

      // Routine Tasks inside Morning Folder
      NeuroItem(
        id: _uuid.v4(),
        title: 'Morning Hydration',
        description: '500ml water upon waking',
        type: NeuroItemType.routine,
        parentId: morningFolderId,
        routineCategory: RoutineCategory.habit,
        completionType: RoutineCompletionType.yesNo,
        scheduleType: ScheduleType.everyday,
        isCompleted: true,
        streakCount: 5,
      ),
      NeuroItem(
        id: _uuid.v4(),
        title: 'Pushups / Morning Exercise',
        description: 'Target 20 reps',
        type: NeuroItemType.routine,
        parentId: morningFolderId,
        routineCategory: RoutineCategory.habit,
        completionType: RoutineCompletionType.numeric,
        targetNumericValue: 20,
        currentNumericValue: 15,
        scheduleType: ScheduleType.everyday,
        streakCount: 3,
      ),
      NeuroItem(
        id: _uuid.v4(),
        title: '10-Min Mindful Breathing Meditation',
        description: 'Timer meditation',
        type: NeuroItemType.routine,
        parentId: morningFolderId,
        routineCategory: RoutineCategory.habit,
        completionType: RoutineCompletionType.timer,
        timerDurationSeconds: 600,
        scheduleType: ScheduleType.everyday,
        streakCount: 4,
      ),

      // Routine Tasks inside Evening Folder
      NeuroItem(
        id: _uuid.v4(),
        title: 'Screen-Free Reading (20 Mins)',
        type: NeuroItemType.routine,
        parentId: eveningFolderId,
        routineCategory: RoutineCategory.habit,
        completionType: RoutineCompletionType.timer,
        timerDurationSeconds: 1200,
        scheduleType: ScheduleType.everyday,
        isCompleted: false,
        streakCount: 2,
      ),

      // Sample Daily To-Dos
      NeuroItem(
        id: _uuid.v4(),
        title: 'Organize workspace desk',
        description: 'Clear clutter for optimal focus',
        type: NeuroItemType.task,
        targetDate: todayDateOnly,
        targetTime: '09:00 AM',
        priority: 1,
        isPendingCarryover: true,
        checklist: [
          ChecklistItem(id: _uuid.v4(), title: 'File paper documents', isCompleted: true),
          ChecklistItem(id: _uuid.v4(), title: 'Clean monitor screen', isCompleted: false),
          ChecklistItem(id: _uuid.v4(), title: 'Wipe down desk surface', isCompleted: false),
        ],
      ),
    ];

    state = defaultItems;
    _storage.saveAllItems(defaultItems);
  }

  /// Toggle completion
  void toggleCompletion(String id) {
    toggleCompletionForDate(id, DateTime.now());
  }

  /// Date-scoped completion toggle
  void toggleCompletionForDate(String id, DateTime date) {
    final dateKey = DateFormat('yyyy-MM-dd').format(date);
    state = [
      for (final item in state)
        if (item.id == id)
          () {
            final dates = List<String>.from(item.completedDates);
            final failed = List<String>.from(item.failedDates);
            final unmarked = List<String>.from(item.unmarkedDates)..remove(dateKey);
            final isCurrentlyCompletedOnDate = dates.contains(dateKey);
            if (isCurrentlyCompletedOnDate) {
              dates.remove(dateKey);
            } else {
              dates.add(dateKey);
              failed.remove(dateKey); // Clear failed status when completed
            }
            final nowCompleted = !isCurrentlyCompletedOnDate;
            return item.copyWith(
              completedDates: dates,
              failedDates: failed,
              unmarkedDates: unmarked,
              isCompleted: dates.isNotEmpty,
              completedAt: nowCompleted ? date : (dates.isNotEmpty ? item.completedAt : null),
              clearCompletedAt: dates.isEmpty,
              streakCount: (nowCompleted && item.type == NeuroItemType.routine)
                  ? item.streakCount + 1
                  : item.streakCount,
            );
          }()
        else
          item,
    ];
    _persistAndSync('toggle_completion', {'id': id});
  }

  /// Reset an item to completely unmarked for a specific date (clears completed, failed, numeric progress, and sub-checklist)
  void resetItemForDate(String id, DateTime date) {
    final dateKey = DateFormat('yyyy-MM-dd').format(date);
    state = [
      for (final item in state)
        if (item.id == id)
          () {
            final completed = List<String>.from(item.completedDates)..remove(dateKey);
            final failed = List<String>.from(item.failedDates)..remove(dateKey);
            final unmarked = List<String>.from(item.unmarkedDates);
            if (!unmarked.contains(dateKey)) {
              unmarked.add(dateKey);
            }

            final newDailyValues = Map<String, double>.from(item.dailyNumericValues)..remove(dateKey);
            final newDailyCompletions = Map<String, List<String>>.from(
              item.dailyChecklistCompletions.map((k, v) => MapEntry(k, List<String>.from(v))),
            );
            // Explicitly set empty list for dateKey so that carryover does not re-inherit prior completions
            newDailyCompletions[dateKey] = <String>[];

            return item.copyWith(
              completedDates: completed,
              failedDates: failed,
              unmarkedDates: unmarked,
              dailyNumericValues: newDailyValues,
              dailyChecklistCompletions: newDailyCompletions,
              currentNumericValue: completed.isEmpty ? 0 : item.currentNumericValue,
              isCompleted: completed.isNotEmpty,
              clearCompletedAt: completed.isEmpty,
            );
          }()
        else
          item,
    ];
    _persistAndSync('reset_item', {'id': id, 'date': dateKey});
  }

  /// Update date-scoped numeric progress
  void updateNumericProgress(String id, double val, {DateTime? date}) {
    final targetDate = date ?? DateTime.now();
    final dateKey = DateFormat('yyyy-MM-dd').format(targetDate);
    state = [
      for (final item in state)
        if (item.id == id)
          () {
            final isReached = (item.targetNumericValue != null && item.targetNumericValue! > 0)
                ? val >= item.targetNumericValue!
                : (item.targetNumericValue == 0 ? val == 0 : false);

            final dates = List<String>.from(item.completedDates);
            final unmarked = List<String>.from(item.unmarkedDates)..remove(dateKey);
            if (isReached && !dates.contains(dateKey)) {
              dates.add(dateKey);
            } else if (!isReached && dates.contains(dateKey)) {
              dates.remove(dateKey);
            }

            final newDailyValues = Map<String, double>.from(item.dailyNumericValues);
            newDailyValues[dateKey] = val;

            return item.copyWith(
              dailyNumericValues: newDailyValues,
              currentNumericValue: val,
              completedDates: dates,
              unmarkedDates: unmarked,
              isCompleted: item.type == NeuroItemType.task ? isReached : (dates.isNotEmpty),
              completedAt: isReached ? DateTime.now() : null,
            );
          }()
        else
          item,
    ];
    _persistAndSync('update_numeric', {'id': id, 'val': val});
  }

  /// Toggle sub-checklist item (date-scoped)
  void toggleChecklistItem(String taskId, String itemId, {DateTime? date}) {
    final targetDate = date ?? DateTime.now();
    final dateKey = DateFormat('yyyy-MM-dd').format(targetDate);
    state = [
      for (final item in state)
        if (item.id == taskId) _updateTaskChecklist(item, itemId, dateKey, targetDate) else item,
    ];
    _persistAndSync('toggle_checklist', {'taskId': taskId, 'itemId': itemId});
  }

  NeuroItem _updateTaskChecklist(NeuroItem task, String itemId, String dateKey, DateTime date) {
    final newCompletions = Map<String, List<String>>.from(
      task.dailyChecklistCompletions.map((k, v) => MapEntry(k, List<String>.from(v))),
    );
    final todayCompletedIds = List<String>.from(
      newCompletions[dateKey] ?? task.getChecklistCompletionsForDate(date),
    );

    if (todayCompletedIds.contains(itemId)) {
      todayCompletedIds.remove(itemId);
    } else {
      todayCompletedIds.add(itemId);
    }
    newCompletions[dateKey] = todayCompletedIds;

    final allSubCompleted = task.checklist.isNotEmpty &&
        task.checklist.every((sub) => todayCompletedIds.contains(sub.id));

    final completedDates = List<String>.from(task.completedDates);
    final unmarked = List<String>.from(task.unmarkedDates)..remove(dateKey);
    if (allSubCompleted && !completedDates.contains(dateKey)) {
      completedDates.add(dateKey);
    } else if (!allSubCompleted && completedDates.contains(dateKey)) {
      completedDates.remove(dateKey);
    }

    return task.copyWith(
      dailyChecklistCompletions: newCompletions,
      completedDates: completedDates,
      unmarkedDates: unmarked,
      isCompleted: task.type == NeuroItemType.task ? allSubCompleted : (completedDates.isNotEmpty),
      completedAt: allSubCompleted ? DateTime.now() : null,
    );
  }

  /// Add a new NeuroItem
  void addItem({
    required String title,
    String? description,
    required NeuroItemType type,
    String? parentId,
    String? rootVisionId,
    DateTime? targetDate,
    String? targetTime,
    DateTime? startDate,
    DateTime? endDate,
    bool hasReminder = false,
    DateTime? reminderDateTime,
    int priority = 50,
    bool isPendingCarryover = false,
    bool noVisionXpEnabled = false,
    String? targetFrequency,
    String? category,
    int? colorHex,
    List<ChecklistItem> checklist = const [],
    RoutineCategory routineCategory = RoutineCategory.habit,
    RoutineCompletionType completionType = RoutineCompletionType.yesNo,
    double? targetNumericValue,
    double currentNumericValue = 0,
    int? timerDurationSeconds,
    ScheduleType scheduleType = ScheduleType.everyday,
    List<int> selectedDaysOfWeek = const [],
    List<String> selectedDaysOfMonth = const [],
    List<String> selectedDaysOfYear = const [],
    int repeatIntervalDays = 1,
    bool isFlexibleCarryover = false,
    bool successContributesToProgress = true,
    bool failureContributesToProgress = false,
    String? dailyCategoryId,
  }) {
    final newItem = NeuroItem(
      id: _uuid.v4(),
      title: title,
      description: description,
      type: type,
      parentId: parentId,
      rootVisionId: rootVisionId ?? (type == NeuroItemType.vision ? null : parentId),
      targetDate: targetDate,
      targetTime: targetTime,
      startDate: startDate,
      endDate: endDate,
      hasReminder: hasReminder,
      reminderDateTime: reminderDateTime,
      priority: priority,
      isPendingCarryover: isPendingCarryover,
      noVisionXpEnabled: noVisionXpEnabled,
      targetFrequency: targetFrequency,
      category: category,
      colorHex: colorHex,
      checklist: checklist,
      routineCategory: routineCategory,
      completionType: completionType,
      targetNumericValue: targetNumericValue,
      currentNumericValue: currentNumericValue,
      timerDurationSeconds: timerDurationSeconds,
      scheduleType: scheduleType,
      selectedDaysOfWeek: selectedDaysOfWeek,
      selectedDaysOfMonth: selectedDaysOfMonth,
      selectedDaysOfYear: selectedDaysOfYear,
      repeatIntervalDays: repeatIntervalDays,
      isFlexibleCarryover: isFlexibleCarryover,
      successContributesToProgress: successContributesToProgress,
      failureContributesToProgress: failureContributesToProgress,
      dailyCategoryId: dailyCategoryId,
    );

    state = [...state, newItem];
    _storage.saveItem(newItem);
    _persistAndSync('item_add', {'id': newItem.id});
  }

  /// Update an existing NeuroItem completely (or insert if new item)
  void updateItem(NeuroItem updated) {
    final exists = state.any((item) => item.id == updated.id);
    if (!exists) {
      state = [...state, updated];
    } else {
      state = [
        for (final item in state)
          if (item.id == updated.id) updated else item,
      ];
    }
    _storage.saveItem(updated);
    _persistAndSync('item_update', {'id': updated.id});
  }

  /// Reorder tasks and update priority levels.
  /// Preserves the priority of marked (completed/failed) items that are pushed down to the bottom.
  void reorderTasks(List<NeuroItem> reorderedList, {DateTime? date}) {
    final updatedMap = <String, int>{};
    int activePriorityCounter = 1;

    final hasMarkedItems = date != null
        ? reorderedList.any((item) => item.isCompletedOnDate(date) || item.isFailedOnDate(date))
        : reorderedList.any((item) => item.isCompleted);

    if (hasMarkedItems) {
      for (int i = 0; i < reorderedList.length; i++) {
        final item = reorderedList[i];
        final isDone = date != null
            ? (item.isCompletedOnDate(date) || item.isFailedOnDate(date))
            : item.isCompleted;
        if (!isDone) {
          updatedMap[item.id] = activePriorityCounter;
          activePriorityCounter++;
        }
        // Marked/completed items keep their exact original priority!
      }
    } else {
      for (int i = 0; i < reorderedList.length; i++) {
        updatedMap[reorderedList[i].id] = (i + 1).clamp(1, 100);
      }
    }

    state = [
      for (final item in state)
        if (updatedMap.containsKey(item.id))
          item.copyWith(priority: updatedMap[item.id])
        else
          item,
    ];
    _persistAndSync('reorder_tasks');
  }

  /// Date-scoped failed toggle
  void toggleFailedForDate(String id, DateTime date) {
    final dateKey = DateFormat('yyyy-MM-dd').format(date);
    state = [
      for (final item in state)
        if (item.id == id)
          () {
            final failed = List<String>.from(item.failedDates);
            final completed = List<String>.from(item.completedDates);
            final unmarked = List<String>.from(item.unmarkedDates)..remove(dateKey);
            if (failed.contains(dateKey)) {
              failed.remove(dateKey);
            } else {
              failed.add(dateKey);
              completed.remove(dateKey);
            }
            return item.copyWith(
              failedDates: failed,
              completedDates: completed,
              unmarkedDates: unmarked,
              isCompleted: completed.isNotEmpty,
              clearCompletedAt: completed.isEmpty,
            );
          }()
        else
          item,
    ];
    _persistAndSync('toggle_failed', {'id': id});
  }

  /// Delete an item and all its recursive descendants
  void deleteItem(String id) {
    final descendantIds = AggregationEngine.getDescendants(id, state).map((e) => e.id).toSet();
    descendantIds.add(id);

    state = state.where((item) => !descendantIds.contains(item.id)).toList();
    _persistAndSync('delete_item', {'id': id});
  }
}

final neuroItemsProvider = StateNotifierProvider<NeuroItemsNotifier, List<NeuroItem>>((ref) {
  final storage = ref.watch(storageServiceProvider);
  final cloudSync = ref.watch(cloudSyncServiceProvider);
  return NeuroItemsNotifier(storage, cloudSync);
});

/// Filtered provider for Top-Level Visions sorted by Priority ascending
final visionsProvider = Provider<List<NeuroItem>>((ref) {
  final items = ref.watch(neuroItemsProvider);
  final list = items
      .where((item) => item.type == NeuroItemType.vision && item.parentId == null)
      .toList();
  list.sort((a, b) => a.priority.compareTo(b.priority));
  return list;
});

/// Overall Visions Completion Progress for Screen 1 Button 1 ("Visions")
final overallVisionsProgressProvider = Provider<double>((ref) {
  final items = ref.watch(neuroItemsProvider);
  final visions = items.where((item) => item.type == NeuroItemType.vision).toList();
  if (visions.isEmpty) return 0.0;

  double totalProgress = 0.0;
  for (final vision in visions) {
    totalProgress += AggregationEngine.calculateVisionProgress(
      rootVisionId: vision.id,
      allItems: items,
    );
  }
  return (totalProgress / visions.length).clamp(0.0, 1.0);
});

/// Overall Visions Progress Text for Screen 1 Button 1
final overallVisionsProgressTextProvider = Provider<String>((ref) {
  final items = ref.watch(neuroItemsProvider);
  final visions = items.where((item) => item.type == NeuroItemType.vision).toList();
  if (visions.isEmpty) return 'No visions set';

  final progress = ref.watch(overallVisionsProgressProvider);
  if (progress == 1.0) {
    return '100% Achieved!';
  }
  return '${(progress * 100).toInt()}% Macro Growth';
});

/// Filtered provider for Top-Level Routine Folders sorted by Priority
final routineFoldersProvider = Provider<List<NeuroItem>>((ref) {
  final items = ref.watch(neuroItemsProvider);
  final list = items
      .where((item) => item.type == NeuroItemType.routineFolder && item.parentId == null)
      .toList();
  list.sort((a, b) => a.priority.compareTo(b.priority));
  return list;
});

/// Routine Tasks inside a specific Routine Folder
final routineFolderTasksProvider = Provider.family<List<NeuroItem>, String>((ref, folderId) {
  final items = ref.watch(neuroItemsProvider);
  final list = items.where((item) => item.parentId == folderId).toList();
  list.sort((a, b) {
    if (a.isCompleted != b.isCompleted) return a.isCompleted ? 1 : -1;
    return a.priority.compareTo(b.priority);
  });
  return list;
});

/// Progress for a specific Routine Folder button (calculated from startDate to endDate ?? today)
final folderProgressProvider = Provider.family<double, String>((ref, folderId) {
  final items = ref.watch(neuroItemsProvider);
  final folder = items.firstWhere(
    (item) => item.id == folderId,
    orElse: () => NeuroItem(id: folderId, title: '', type: NeuroItemType.routineFolder),
  );
  return AggregationEngine.calculateRoutineFolderProgress(
    folder: folder,
    allItems: items,
  );
});

/// Overall Routines Completion Progress for Screen 1 Button 2 (depends on routine folder progress bars)
final overallRoutinesProgressProvider = Provider<double>((ref) {
  final items = ref.watch(neuroItemsProvider);
  return AggregationEngine.calculateOverallRoutinesProgress(
    allItems: items,
  );
});

/// Overall Routines Progress Text for Screen 1 Button 2
final overallRoutinesProgressTextProvider = Provider<String>((ref) {
  final items = ref.watch(neuroItemsProvider);
  final folders = items
      .where((item) => item.type == NeuroItemType.routineFolder && item.parentId == null)
      .toList();

  if (folders.isEmpty) return 'No routines set';
  final progress = ref.watch(overallRoutinesProgressProvider);

  if (progress == 1.0) {
    return '100% Completed!';
  }
  return '${(progress * 100).toInt()}% Routines Achieved';
});

/// Filtered provider for To-Do List Tasks
final dateTasksProvider = Provider.family<List<NeuroItem>, DateTime?>((ref, selectedDate) {
  final items = ref.watch(neuroItemsProvider);

  List<NeuroItem> rawList;
  if (selectedDate == null) {
    rawList = items
        .where((item) =>
            item.type == NeuroItemType.task &&
            item.targetDate == null &&
            item.parentId == null &&
            item.rootVisionId == null)
        .toList();
  } else {
    final targetDay = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);

    rawList = items.where((item) {
      if (item.type != NeuroItemType.task) return false;

      // To-Do List Isolation: Only items created directly in To-Do List
      if (item.parentId != null || item.rootVisionId != null) return false;

      if (item.targetDate == null) return false;

      final createdDay = DateTime(item.createdAt.year, item.createdAt.month, item.createdAt.day);
      if (targetDay.isBefore(createdDay)) return false;

      final itemDate = DateTime(item.targetDate!.year, item.targetDate!.month, item.targetDate!.day);

      // 1. Scheduled on this target date
      if (itemDate.isAtSameMomentAs(targetDay)) return true;

      // 2. Uncompleted carryover/flexible task carried forward to any date after targetDate
      // ONLY if it was NOT marked as failed prior to targetDay (only unmarked or pending tasks carry forward)
      if ((item.isPendingCarryover || item.isFlexibleCarryover) && !item.isCompleted) {
        if (itemDate.isBefore(targetDay)) {
          bool hasFailedPrior = false;
          for (var d = itemDate; d.isBefore(targetDay); d = d.add(const Duration(days: 1))) {
            final dKey = DateFormat('yyyy-MM-dd').format(d);
            if (item.failedDates.contains(dKey)) {
              hasFailedPrior = true;
              break;
            }
          }
          if (!hasFailedPrior) return true;
        }
      }

      // 3. Completed carryover task shown on the date it was completed
      if (item.isCompleted && item.completedAt != null && (item.isPendingCarryover || item.isFlexibleCarryover)) {
        final completedDay = DateTime(item.completedAt!.year, item.completedAt!.month, item.completedAt!.day);
        if (completedDay.isAtSameMomentAs(targetDay)) return true;
      }

      return false;
    }).toList();
  }

  rawList.sort((a, b) {
    final aCompleted = selectedDate != null ? a.isCompletedOnDate(selectedDate) : a.isCompleted;
    final bCompleted = selectedDate != null ? b.isCompletedOnDate(selectedDate) : b.isCompleted;
    final aFailed = selectedDate != null ? a.isFailedOnDate(selectedDate) : false;
    final bFailed = selectedDate != null ? b.isFailedOnDate(selectedDate) : false;
    final aDone = aCompleted || aFailed;
    final bDone = bCompleted || bFailed;
    if (aDone != bDone) {
      return aDone ? 1 : -1;
    }
    return a.priority.compareTo(b.priority);
  });

  return rawList;
});

/// Today's task completion progress for Screen 1 Button 3
final todayProgressProvider = Provider<double>((ref) {
  final today = DateTime.now();
  final todayTasks = ref.watch(dateTasksProvider(today));

  if (todayTasks.isEmpty) return 0.0;
  double completedFraction = 0.0;
  for (final t in todayTasks) {
    completedFraction += AggregationEngine.getItemCompletionFractionOnDate(t, today);
  }
  return (completedFraction / todayTasks.length).clamp(0.0, 1.0);
});

/// Formatted text for Screen 1 Button 3
final todayProgressTextProvider = Provider<String>((ref) {
  final today = DateTime.now();
  final todayTasks = ref.watch(dateTasksProvider(today));

  if (todayTasks.isEmpty) return 'No tasks scheduled';
  final progress = ref.watch(todayProgressProvider);
  if (progress == 1.0) {
    return '100% Completed!';
  }
  final completedCount = todayTasks.where((t) => t.isCompleted).length;
  final percent = (progress * 100).toInt();
  if (completedCount == 0 && percent > 0) {
    return '$percent% In Progress';
  }
  return '$completedCount of ${todayTasks.length} completed ($percent%)';
});

final dailyCategoriesProvider = StateNotifierProvider<DailyCategoriesNotifier, List<DailyCategory>>((ref) {
  final storage = ref.watch(storageServiceProvider);
  final cloudSync = ref.watch(cloudSyncServiceProvider);
  return DailyCategoriesNotifier(storage, cloudSync);
});

class DailyCategoriesNotifier extends StateNotifier<List<DailyCategory>> {
  final HiveStorageService _storage;
  final CloudSyncService? _cloudSync;

  DailyCategoriesNotifier(this._storage, [this._cloudSync]) : super(_storage.getDailyCategories());

  void setCategories(List<DailyCategory> categories) {
    state = categories;
  }

  void _persistAndSync(String actionType, [Map<String, dynamic>? payload]) {
    _storage.saveDailyCategories(state);
    final user = _storage.getCurrentUser();
    if (user != null && !user.isGuest && _cloudSync != null) {
      _cloudSync.syncAction(
        userId: user.id,
        actionType: actionType,
        payload: payload ?? {'count': state.length},
        currentLocalItems: _storage.getAllItems(),
        currentLocalCategories: state,
      );
    }
  }

  void addCategory(DailyCategory category) {
    state = [...state, category];
    _persistAndSync('category_add', {'id': category.id, 'name': category.name});
  }

  void updateCategory(DailyCategory updated) {
    state = [for (final c in state) if (c.id == updated.id) updated else c];
    _persistAndSync('category_update', {'id': updated.id, 'name': updated.name});
  }

  void deleteCategory(String id) {
    state = state.where((c) => c.id != id).toList();
    _persistAndSync('category_delete', {'id': id});
  }

  void deleteAllCategories() {
    state = [];
    _persistAndSync('category_delete_all');
  }

  void reorderCategories(List<DailyCategory> reorderedList) {
    final updated = <DailyCategory>[];
    final updatedIds = <String>{};
    for (int i = 0; i < reorderedList.length; i++) {
      final newPriority = (i + 1).clamp(1, 100);
      updated.add(reorderedList[i].copyWith(priority: newPriority));
      updatedIds.add(reorderedList[i].id);
    }
    // Retain any existing categories that were not present in reorderedList so they are NEVER dropped!
    for (final existing in state) {
      if (!updatedIds.contains(existing.id)) {
        updated.add(existing);
      }
    }
    state = updated;
    _persistAndSync('category_reorder', {'count': state.length});
  }
}

// --- BUTTON 4: DAILY TRACK PROVIDERS ---

/// Daily Track Execution Provider: Aggregates ALL tasks, habits, and repetitive tasks
/// created across Visions, Routine Folders, and To-Do List for a specific date.
/// EXCLUDES Flexible "F" tab tasks (targetDate == null).
final dailyTrackItemsProvider = Provider.family<List<NeuroItem>, DateTime>((ref, selectedDate) {
  final items = ref.watch(neuroItemsProvider);
  final targetDay = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);

  final list = items.where((item) {
    // Exclude folder containers themselves (Visions and Routine Folders)
    if (item.type == NeuroItemType.vision || item.type == NeuroItemType.routineFolder) {
      return false;
    }

    // EXCLUDE Flexible ("F" Tab / No Date) tasks with no targetDate
    if (item.type == NeuroItemType.task && item.targetDate == null) {
      return false;
    }

    // Don't show items before their creation date or start date
    final createdDay = DateTime(item.createdAt.year, item.createdAt.month, item.createdAt.day);
    if (targetDay.isBefore(createdDay)) return false;

    if (item.startDate != null) {
      final startDay = DateTime(item.startDate!.year, item.startDate!.month, item.startDate!.day);
      if (targetDay.isBefore(startDay)) return false;
    }

    if (item.endDate != null) {
      final endDay = DateTime(item.endDate!.year, item.endDate!.month, item.endDate!.day);
      if (targetDay.isAfter(endDay)) return false;
    }

    // 1. If it's a Routine/Habit from Routine Track or Visions:
    if (item.type == NeuroItemType.routine) {
      if (AggregationEngine.isItemScheduledOnDate(item, targetDay)) {
        return true;
      }

      // Carry-forward routine: repeats until the next scheduled occurrence
      if ((item.isPendingCarryover || item.isFlexibleCarryover) &&
          item.scheduleType != ScheduleType.everyday) {
        final startDay = DateTime(
          (item.startDate ?? item.createdAt).year,
          (item.startDate ?? item.createdAt).month,
          (item.startDate ?? item.createdAt).day,
        );
        if (targetDay.isBefore(startDay)) return false;

        DateTime? lastScheduled;
        for (var d = targetDay.subtract(const Duration(days: 1));
            !d.isBefore(startDay);
            d = d.subtract(const Duration(days: 1))) {
          if (AggregationEngine.isItemScheduledOnDate(item, d)) {
            lastScheduled = d;
            break;
          }
        }

        if (lastScheduled != null) {
          // Check if already completed OR marked failed in the current cycle prior to targetDay
          bool completedInCycle = false;
          bool failedInCycle = false;
          for (var d = lastScheduled;
              d.isBefore(targetDay);
              d = d.add(const Duration(days: 1))) {
            final dKey = DateFormat('yyyy-MM-dd').format(d);
            if (item.completedDates.contains(dKey)) {
              completedInCycle = true;
              break;
            }
            if (item.failedDates.contains(dKey)) {
              failedInCycle = true;
              break;
            }
          }

          if (!failedInCycle && (!completedInCycle || item.isCompletedOnDate(targetDay))) {
            return true;
          }
        }
      }
      return false;
    }

    // 2. If it's a Dated Task from Visions or Daily To-Do List:
    if (item.targetDate != null) {
      final itemDate = DateTime(item.targetDate!.year, item.targetDate!.month, item.targetDate!.day);

      // 1. Scheduled on this target date
      if (itemDate.isAtSameMomentAs(targetDay)) return true;

      // 2. Uncompleted carryover/flexible task carried forward to any date after targetDate
      // ONLY if it was NOT marked as failed prior to targetDay (only unmarked or pending tasks carry forward)
      if ((item.isPendingCarryover || item.isFlexibleCarryover) && !item.isCompleted) {
        if (itemDate.isBefore(targetDay)) {
          bool hasFailedPrior = false;
          for (var d = itemDate; d.isBefore(targetDay); d = d.add(const Duration(days: 1))) {
            final dKey = DateFormat('yyyy-MM-dd').format(d);
            if (item.failedDates.contains(dKey)) {
              hasFailedPrior = true;
              break;
            }
          }
          if (!hasFailedPrior) return true;
        }
      }

      // 3. Completed carryover task shown on the date it was completed
      if (item.isCompleted && item.completedAt != null && (item.isPendingCarryover || item.isFlexibleCarryover)) {
        final completedDay = DateTime(item.completedAt!.year, item.completedAt!.month, item.completedAt!.day);
        if (completedDay.isAtSameMomentAs(targetDay)) return true;
      }
    }

    return false;
  }).toList();

  // Sort: Active/Incomplete first (by priority), Completed AND Failed pushed to bottom (also by priority)
  list.sort((a, b) {
    final aCompleted = a.isCompletedOnDate(selectedDate);
    final bCompleted = b.isCompletedOnDate(selectedDate);
    final aFailed = a.isFailedOnDate(selectedDate);
    final bFailed = b.isFailedOnDate(selectedDate);
    final aDone = aCompleted || aFailed;
    final bDone = bCompleted || bFailed;
    if (aDone != bDone) return aDone ? 1 : -1;
    return a.priority.compareTo(b.priority);
  });

  return list;
});

/// Daily Net Score provider for a given date
final dailyTrackNetScoreProvider = Provider.family<DailyNetScore, DateTime>((ref, date) {
  final items = ref.watch(dailyTrackItemsProvider(date));
  return AggregationEngine.calculateDailyNetScore(items, date);
});

/// Daily Track completion progress for Button 4 on Screen 1
final dailyTrackProgressProvider = Provider<double>((ref) {
  final today = DateTime.now();
  final score = ref.watch(dailyTrackNetScoreProvider(today));
  return score.normalizedProgress;
});

/// Formatted text for Button 4 Daily Track
final dailyTrackProgressTextProvider = Provider<String>((ref) {
  final today = DateTime.now();
  final score = ref.watch(dailyTrackNetScoreProvider(today));
  if (score.totalItems == 0) return 'No tasks scheduled for today';
  final netScore = score.netScore;
  final netFormatted = netScore >= 0
      ? '+${netScore.toStringAsFixed(netScore.truncateToDouble() == netScore ? 0 : 1)}'
      : netScore.toStringAsFixed(netScore.truncateToDouble() == netScore ? 0 : 1);
  return 'Net Score: $netFormatted (${(score.normalizedProgress * 100).toInt()}%)';
});
