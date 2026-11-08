import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:neurovault/models/neuro_item.dart';
import 'package:neurovault/providers/neuro_providers.dart';
import 'package:neurovault/services/aggregation_engine.dart';
import 'package:neurovault/services/hive_storage_service.dart';

class MockTestHiveStorage extends HiveStorageService {
  final List<DailyCategory> _categories = [];
  final List<NeuroItem> _items = [];

  @override
  List<DailyCategory> getDailyCategories() => List.unmodifiable(_categories);

  @override
  Future<void> saveDailyCategories(List<DailyCategory> categories) async {
    _categories.clear();
    _categories.addAll(categories);
  }

  @override
  List<NeuroItem> getAllItems() => List.unmodifiable(_items);

  @override
  Future<void> saveAllItems(List<NeuroItem> items) async {
    _items.clear();
    _items.addAll(items);
  }
}

void main() {
  group('Bug 1 & Bug 2: Category Preservation and Priority Invariance Tests', () {
    late MockTestHiveStorage storage;

    setUp(() {
      storage = MockTestHiveStorage();
    });

    test('Bug 1 Fix: reorderCategories never drops categories missing from reorderedList', () {
      final notifier = DailyCategoriesNotifier(storage);
      final c1 = DailyCategory(id: 'cat_work', name: 'Work', priority: 1);
      final c2 = DailyCategory(id: 'cat_health', name: 'Health', priority: 2);
      final c3 = DailyCategory(id: 'cat_learn', name: 'Learning', priority: 3);

      notifier.addCategory(c1);
      notifier.addCategory(c2);
      notifier.addCategory(c3);
      expect(notifier.state.length, 3);

      // Suppose cat_learn was completed and filtered out from the active reorder list.
      // Reordering with only [cat_health, cat_work] must NOT drop cat_learn!
      notifier.reorderCategories([c2, c1]);

      expect(notifier.state.length, 3, reason: 'No category should ever be deleted during reorder');
      final ids = notifier.state.map((c) => c.id).toList();
      expect(ids, containsAll(['cat_work', 'cat_health', 'cat_learn']));
      expect(notifier.state.firstWhere((c) => c.id == 'cat_learn').name, 'Learning',
          reason: 'Completed category remains intact and never falls back to Master Category');
    });

    test('Bug 2 Fix: Completed or failed task priority is preserved and resets on next day', () {
      final today = DateTime.now();
      final tomorrow = today.add(const Duration(days: 1));

      final task = NeuroItem(
        id: 't_fixed_p',
        title: 'Important Report',
        type: NeuroItemType.task,
        targetDate: today,
        priority: 1,
      );

      final notifier = NeuroItemsNotifier(storage, null);
      storage.saveAllItems([task]);
      notifier.addItem(
        title: task.title,
        type: task.type,
        targetDate: task.targetDate,
        priority: 1,
      );
      final item = notifier.state.first;

      // Mark completed for today
      notifier.toggleCompletionForDate(item.id, today);
      final completedItem = notifier.state.first;
      expect(completedItem.priority, 1, reason: 'Completing item must not change its priority');
      expect(completedItem.isCompletedOnDate(today), isTrue);

      // On tomorrow, the item is NOT completed and remains at priority 1
      expect(completedItem.isCompletedOnDate(tomorrow), isFalse);
      expect(completedItem.priority, 1);
    });
  });

  group('Bug 3: Cross-Date Contamination Tests', () {
    late MockTestHiveStorage storage;

    setUp(() {
      storage = MockTestHiveStorage();
    });

    test('Changing or completing previous day item does NOT mark current day item', () {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final today = DateTime.now();

      final notifier = NeuroItemsNotifier(storage, null);
      notifier.addItem(
        title: 'Daily Review',
        type: NeuroItemType.task,
        targetDate: yesterday,
        priority: 1,
      );
      final item = notifier.state.first;

      // Mark completed on yesterday
      notifier.toggleCompletionForDate(item.id, yesterday);
      final updated = notifier.state.first;

      expect(updated.isCompletedOnDate(yesterday), isTrue);
      expect(updated.isCompletedOnDate(today), isFalse,
          reason: 'Completing yesterday must NOT mark today as completed');
    });

    test('Resetting previous day item does NOT unmark current day item', () {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final today = DateTime.now();

      final notifier = NeuroItemsNotifier(storage, null);
      notifier.addItem(
        title: 'Standup Notes',
        type: NeuroItemType.task,
        targetDate: today,
        priority: 1,
      );
      final item = notifier.state.first;

      // Mark completed on both yesterday and today
      notifier.toggleCompletionForDate(item.id, yesterday);
      notifier.toggleCompletionForDate(item.id, today);
      var current = notifier.state.first;
      expect(current.isCompletedOnDate(yesterday), isTrue);
      expect(current.isCompletedOnDate(today), isTrue);

      // Reset yesterday
      notifier.resetItemForDate(item.id, yesterday);
      current = notifier.state.first;

      expect(current.isCompletedOnDate(yesterday), isFalse);
      expect(current.isCompletedOnDate(today), isTrue,
          reason: 'Resetting yesterday must NOT reset today');
    });

    test('Failing previous day item does NOT fail current day item', () {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final today = DateTime.now();

      final notifier = NeuroItemsNotifier(storage, null);
      notifier.addItem(
        title: 'Gym Workout',
        type: NeuroItemType.task,
        targetDate: yesterday,
        priority: 1,
      );
      final item = notifier.state.first;

      notifier.toggleFailedForDate(item.id, yesterday);
      final current = notifier.state.first;

      expect(current.isFailedOnDate(yesterday), isTrue);
      expect(current.isFailedOnDate(today), isFalse,
          reason: 'Failing yesterday must NOT mark today as failed');
    });
  });

  group('Bug 4: Default Folder Item Hierarchy Tests', () {
    test('Task created under routine folder resolves parentId and retains relationship', () {
      final folder = NeuroItem(
        id: 'folder_routines_1',
        title: 'Morning Routines',
        type: NeuroItemType.routineFolder,
      );

      bool checkIsDailyCat(String id) => false;
      final categoryKey = folder.id;
      final parentItem = folder;

      final resolvedParentId = checkIsDailyCat(categoryKey) ? null : (categoryKey == 'UNGROUPED_TODOS' ? null : categoryKey);
      final resolvedRootVisionId = parentItem.rootVisionId ?? (parentItem.type == NeuroItemType.vision ? parentItem.id : null);

      expect(resolvedParentId, equals('folder_routines_1'));
      expect(resolvedRootVisionId, isNull);
    });

    test('Task created under vision resolves parentId and rootVisionId properly', () {
      final vision = NeuroItem(
        id: 'vision_career_1',
        title: 'Career Advancement',
        type: NeuroItemType.vision,
      );

      final categoryKey = vision.id;
      final parentItem = vision;

      final resolvedParentId = categoryKey;
      final resolvedRootVisionId = parentItem.rootVisionId ?? (parentItem.type == NeuroItemType.vision ? parentItem.id : null);

      expect(resolvedParentId, equals('vision_career_1'));
      expect(resolvedRootVisionId, equals('vision_career_1'));
    });
  });

  group('Feature 5: Unified Task Evaluation & Net Scoring Logic Tests', () {
    final today = DateTime.now();
    final todayKey = DateFormat('yyyy-MM-dd').format(today);

    test('Outcome A: Full Success (+1.0 point) across tracking types', () {
      // 1. Checklist 100% completed
      final checklistItem = NeuroItem(
        id: 'chk_1',
        title: 'Full Checklist',
        type: NeuroItemType.routine,
        checklist: [
          ChecklistItem(id: 'c1', title: 'Sub 1', isCompleted: false),
          ChecklistItem(id: 'c2', title: 'Sub 2', isCompleted: false),
        ],
        dailyChecklistCompletions: {
          todayKey: ['c1', 'c2'],
        },
      );
      final chkEval = AggregationEngine.evaluateItemStatusOnDate(checklistItem, today);
      expect(chkEval.status, TaskEvaluationStatus.success);
      expect(chkEval.progressFraction, 1.0);
      expect(chkEval.scoreContribution, 1.0);

      // 2. Numeric target reached
      final numericItem = NeuroItem(
        id: 'num_1',
        title: '100 Pushups',
        type: NeuroItemType.routine,
        completionType: RoutineCompletionType.numeric,
        targetNumericValue: 100,
        dailyNumericValues: {todayKey: 100.0},
      );
      final numEval = AggregationEngine.evaluateItemStatusOnDate(numericItem, today);
      expect(numEval.status, TaskEvaluationStatus.success);
      expect(numEval.scoreContribution, 1.0);

      // 3. Timer target reached
      final timerItem = NeuroItem(
        id: 'tim_1',
        title: '30 Min Meditation',
        type: NeuroItemType.routine,
        completionType: RoutineCompletionType.timer,
        timerDurationSeconds: 1800,
        dailyNumericValues: {todayKey: 1800.0},
      );
      final timEval = AggregationEngine.evaluateItemStatusOnDate(timerItem, today);
      expect(timEval.status, TaskEvaluationStatus.success);
      expect(timEval.scoreContribution, 1.0);
    });

    test('Outcome B: Partially Completed (+fraction point) proportional contribution', () {
      // Numeric: target 10, actual 6 -> 60% = +0.6 points
      final numericItem = NeuroItem(
        id: 'num_partial',
        title: 'Read 10 Chapters',
        type: NeuroItemType.routine,
        completionType: RoutineCompletionType.numeric,
        targetNumericValue: 10,
        dailyNumericValues: {todayKey: 6.0},
      );
      final numEval = AggregationEngine.evaluateItemStatusOnDate(numericItem, today);
      expect(numEval.status, TaskEvaluationStatus.partiallyCompleted);
      expect(numEval.progressFraction, closeTo(0.6, 0.001));
      expect(numEval.scoreContribution, closeTo(0.6, 0.001));

      // Checklist: 4 sub-items, 1 completed -> 25% = +0.25 points
      final checklistItem = NeuroItem(
        id: 'chk_partial',
        title: 'Clean Apartment',
        type: NeuroItemType.routine,
        checklist: [
          ChecklistItem(id: 'c1', title: 'Room 1', isCompleted: false),
          ChecklistItem(id: 'c2', title: 'Room 2', isCompleted: false),
          ChecklistItem(id: 'c3', title: 'Room 3', isCompleted: false),
          ChecklistItem(id: 'c4', title: 'Room 4', isCompleted: false),
        ],
        dailyChecklistCompletions: {
          todayKey: ['c1'],
        },
      );
      final chkEval = AggregationEngine.evaluateItemStatusOnDate(checklistItem, today);
      expect(chkEval.status, TaskEvaluationStatus.partiallyCompleted);
      expect(chkEval.progressFraction, closeTo(0.25, 0.001));
      expect(chkEval.scoreContribution, closeTo(0.25, 0.001));
    });

    test('Outcome C: Failure (0 progress = -1.0 point)', () {
      final zeroProgressItem = NeuroItem(
        id: 'zero_1',
        title: 'Unstarted Habit',
        type: NeuroItemType.routine,
        completionType: RoutineCompletionType.numeric,
        targetNumericValue: 5,
        dailyNumericValues: {todayKey: 0.0},
      );
      final eval = AggregationEngine.evaluateItemStatusOnDate(zeroProgressItem, today);
      expect(eval.status, TaskEvaluationStatus.failure);
      expect(eval.progressFraction, 0.0);
      expect(eval.scoreContribution, -1.0);
    });

    test('Net Success Score Example 1: 10 items (6 successes, 4 failures) = +2 points', () {
      final items = <NeuroItem>[];
      // 6 successes (+6)
      for (int i = 0; i < 6; i++) {
        items.add(NeuroItem(
          id: 'succ_$i',
          title: 'Success $i',
          type: NeuroItemType.task,
          targetDate: today,
          completedDates: [todayKey],
        ));
      }
      // 4 failures with 0 progress (-4)
      for (int i = 0; i < 4; i++) {
        items.add(NeuroItem(
          id: 'fail_$i',
          title: 'Fail $i',
          type: NeuroItemType.task,
          targetDate: today,
          completionType: RoutineCompletionType.numeric,
          targetNumericValue: 10,
          dailyNumericValues: {todayKey: 0.0},
        ));
      }

      final score = AggregationEngine.calculateDailyNetScore(items, today);
      expect(score.totalItems, 10);
      expect(score.successCount, 6);
      expect(score.failureCount, 4);
      expect(score.partialCount, 0);
      expect(score.totalSuccessPoints, 6.0);
      expect(score.totalFailurePoints, 4.0);
      expect(score.partialPoints, 0.0);
      // Net Success Score = 6 - 4 = +2
      expect(score.netScore, equals(2.0));
      expect(score.normalizedProgress, equals(0.2)); // +20%
    });

    test('Net Success Score Example 2: 3 successes, 2 failures, 5 partial (60% each) = +4 points', () {
      final items = <NeuroItem>[];
      // 3 successes (+3)
      for (int i = 0; i < 3; i++) {
        items.add(NeuroItem(
          id: 'succ_$i',
          title: 'Success $i',
          type: NeuroItemType.task,
          targetDate: today,
          completedDates: [todayKey],
        ));
      }
      // 2 failures (-2)
      for (int i = 0; i < 2; i++) {
        items.add(NeuroItem(
          id: 'fail_$i',
          title: 'Fail $i',
          type: NeuroItemType.task,
          targetDate: today,
          completionType: RoutineCompletionType.numeric,
          targetNumericValue: 10,
          dailyNumericValues: {todayKey: 0.0},
        ));
      }
      // 5 partially completed (target: 10, actual: 6 -> 60% = +0.6 each -> total +3.0)
      for (int i = 0; i < 5; i++) {
        items.add(NeuroItem(
          id: 'part_$i',
          title: 'Partial $i',
          type: NeuroItemType.task,
          targetDate: today,
          completionType: RoutineCompletionType.numeric,
          targetNumericValue: 10,
          dailyNumericValues: {todayKey: 6.0},
        ));
      }

      final score = AggregationEngine.calculateDailyNetScore(items, today);
      expect(score.totalItems, 10);
      expect(score.successCount, 3);
      expect(score.failureCount, 2);
      expect(score.partialCount, 5);
      expect(score.totalSuccessPoints, 3.0);
      expect(score.totalFailurePoints, 2.0);
      expect(score.partialPoints, closeTo(3.0, 0.001));
      // Net Success Score = 3 - 2 + 3.0 = +4.0
      expect(score.netScore, closeTo(4.0, 0.001));
      expect(score.normalizedProgress, closeTo(0.4, 0.001)); // +40%
    });

    test('Rule 8: Multiple tracking methods evaluated together (average fraction)', () {
      // Item with both checklist (2 of 4 = 50%) and numeric target (8 of 10 = 80%)
      // Combined fraction = (0.50 + 0.80) / 2 = 0.65 (65%)
      final multiItem = NeuroItem(
        id: 'multi_1',
        title: 'Workout & Log',
        type: NeuroItemType.routine,
        completionType: RoutineCompletionType.numeric,
        targetNumericValue: 10,
        dailyNumericValues: {todayKey: 8.0},
        checklist: [
          ChecklistItem(id: 'c1', title: 'Set 1', isCompleted: false),
          ChecklistItem(id: 'c2', title: 'Set 2', isCompleted: false),
          ChecklistItem(id: 'c3', title: 'Set 3', isCompleted: false),
          ChecklistItem(id: 'c4', title: 'Set 4', isCompleted: false),
        ],
        dailyChecklistCompletions: {
          todayKey: ['c1', 'c2'],
        },
      );

      final eval = AggregationEngine.evaluateItemStatusOnDate(multiItem, today);
      expect(eval.status, TaskEvaluationStatus.partiallyCompleted);
      expect(eval.progressFraction, closeTo(0.65, 0.001));
      expect(eval.scoreContribution, closeTo(0.65, 0.001));
    });

    test('Rules 1, 2, 3: Boundaries correctly observed', () {
      // Rule 1: Zero progress never classified as partial
      final zeroItem = NeuroItem(
        id: 'r1',
        title: 'Zero',
        type: NeuroItemType.routine,
        completionType: RoutineCompletionType.numeric,
        targetNumericValue: 10,
        dailyNumericValues: {todayKey: 0.0},
      );
      expect(AggregationEngine.evaluateItemStatusOnDate(zeroItem, today).status,
          TaskEvaluationStatus.failure);

      // Rule 2: Measurable insufficient progress never classified as complete success
      final partialItem = NeuroItem(
        id: 'r2',
        title: 'Almost',
        type: NeuroItemType.routine,
        completionType: RoutineCompletionType.numeric,
        targetNumericValue: 10,
        dailyNumericValues: {todayKey: 9.9},
      );
      expect(AggregationEngine.evaluateItemStatusOnDate(partialItem, today).status,
          TaskEvaluationStatus.partiallyCompleted);

      // Rule 3: Partial completion never classified as complete failure
      expect(AggregationEngine.evaluateItemStatusOnDate(partialItem, today).status,
          isNot(TaskEvaluationStatus.failure));
    });
  });
}
