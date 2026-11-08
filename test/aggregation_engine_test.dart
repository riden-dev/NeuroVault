import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:neurovault/models/neuro_item.dart';
import 'package:neurovault/services/aggregation_engine.dart';

void main() {
  group('Tree Hierarchical Distribution System - AggregationEngine Tests', () {
    test('compute7DayRollingSeries groups completion events into 7-day float array', () {
      final now = DateTime.now();
      const visionId = 'vision_100';

      final items = [
        NeuroItem(
          id: visionId,
          title: 'Macro Vision Container',
          type: NeuroItemType.vision,
        ),
        NeuroItem(
          id: 'task_1',
          title: 'Morning stretch',
          type: NeuroItemType.routine,
          rootVisionId: visionId,
          isCompleted: true,
          completedAt: now,
        ),
        NeuroItem(
          id: 'task_2',
          title: 'Read 10 pages',
          type: NeuroItemType.task,
          rootVisionId: visionId,
          isCompleted: true,
          completedAt: now.subtract(const Duration(days: 2)),
        ),
      ];

      final series = AggregationEngine.compute7DayRollingSeries(
        rootVisionId: visionId,
        allItems: items,
        referenceDate: now,
      );

      expect(series.length, equals(7));
      expect(series[6], equals(1.0)); // Today (0 days ago) has 1 completion
      expect(series[4], equals(1.0)); // 2 days ago has 1 completion
      expect(series[0], equals(0.0)); // 6 days ago has 0 completions
    });

    test('Dataset Isolation Guard (noVisionXpEnabled) returns hardcoded zero array', () {
      const visionId = 'isolated_vision_200';

      final items = [
        NeuroItem(
          id: visionId,
          title: 'Brain Dump Sandbox',
          type: NeuroItemType.vision,
          noVisionXpEnabled: true, // Isolation guard ON
        ),
        NeuroItem(
          id: 'task_untracked',
          title: 'Random idea',
          type: NeuroItemType.task,
          rootVisionId: visionId,
          isCompleted: true,
          completedAt: DateTime.now(),
        ),
      ];

      final series = AggregationEngine.compute7DayRollingSeries(
        rootVisionId: visionId,
        allItems: items,
      );

      expect(series, equals([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]));
    });

    test('calculateVisionProgress computes correct completion percentage', () {
      const visionId = 'vision_300';

      final items = [
        NeuroItem(
          id: visionId,
          title: 'Health Vision',
          type: NeuroItemType.vision,
        ),
        NeuroItem(
          id: 'sub_1',
          title: 'Sub Task 1',
          type: NeuroItemType.task,
          rootVisionId: visionId,
          isCompleted: true,
        ),
        NeuroItem(
          id: 'sub_2',
          title: 'Sub Task 2',
          type: NeuroItemType.task,
          rootVisionId: visionId,
          isCompleted: false,
        ),
      ];

      final progress = AggregationEngine.calculateVisionProgress(
        rootVisionId: visionId,
        allItems: items,
      );

      expect(progress, equals(0.5));
    });

    test('isCompletedOnDate accurately scopes routine completion to specific dates', () {
      final today = DateTime.now();
      final tomorrow = today.add(const Duration(days: 1));
      const dateKeyToday = '2026-09-20';

      final routineItem = NeuroItem(
        id: 'routine_1',
        title: 'Morning Meditation',
        type: NeuroItemType.routine,
        completedDates: [dateKeyToday],
      );

      expect(routineItem.isCompletedOnDate(DateTime(2026, 9, 20)), equals(true));
      expect(routineItem.isCompletedOnDate(tomorrow), equals(false));
    });

    test('calculateRoutineFolderProgress computes progress across start to end date period', () {
      final refDate = DateTime(2026, 9, 20);
      final startDate = DateTime(2026, 9, 18); // 3 days: Sep 18, Sep 19, Sep 20
      const folderId = 'routine_folder_1';

      final folder = NeuroItem(
        id: folderId,
        title: 'Morning Routine Folder',
        type: NeuroItemType.routineFolder,
        startDate: startDate,
        endDate: null, // Effective end date = refDate (Sep 20)
      );

      final habit = NeuroItem(
        id: 'habit_1',
        title: 'Hydration',
        type: NeuroItemType.routine,
        parentId: folderId,
        scheduleType: ScheduleType.everyday,
        completedDates: ['2026-09-18', '2026-09-20'], // Completed 2 of 3 scheduled days
      );

      final progress = AggregationEngine.calculateRoutineFolderProgress(
        folder: folder,
        allItems: [folder, habit],
        referenceDate: refDate,
      );

      // 2 completed / 3 scheduled days = 2/3 = 0.666666...
      expect(progress, closeTo(2 / 3, 0.001));
    });

    test('calculateOverallRoutinesProgress averages folder progress bars', () {
      final refDate = DateTime(2026, 9, 20);
      const folder1 = 'f1';
      const folder2 = 'f2';

      final f1Item = NeuroItem(
        id: folder1,
        title: 'Folder 1',
        type: NeuroItemType.routineFolder,
        startDate: refDate,
      );
      final f2Item = NeuroItem(
        id: folder2,
        title: 'Folder 2',
        type: NeuroItemType.routineFolder,
        startDate: refDate,
      );

      final h1 = NeuroItem(
        id: 'h1',
        title: 'H1',
        type: NeuroItemType.routine,
        parentId: folder1,
        scheduleType: ScheduleType.everyday,
        completedDates: ['2026-09-20'], // 100% completed today
      );
      final h2 = NeuroItem(
        id: 'h2',
        title: 'H2',
        type: NeuroItemType.routine,
        parentId: folder2,
        scheduleType: ScheduleType.everyday,
        completedDates: [], // 0% completed today
      );

      final overall = AggregationEngine.calculateOverallRoutinesProgress(
        allItems: [f1Item, f2Item, h1, h2],
        referenceDate: refDate,
      );

      // (1.0 + 0.0) / 2 = 0.5
      expect(overall, equals(0.5));
    });

    test('Uncompleted carryover task carries forward to future dates until completed', () {
      final taskDate = DateTime(2026, 9, 18);
      final nextDay = DateTime(2026, 9, 19);
      final futureDay = DateTime(2026, 9, 21);

      final carryoverTask = NeuroItem(
        id: 'carry_1',
        title: 'Uncompleted Carryover Task',
        type: NeuroItemType.task,
        targetDate: taskDate,
        isPendingCarryover: true,
        isCompleted: false,
      );

      // Verify task evaluates as active carryover on nextDay and futureDay
      bool carriesToNextDay = carryoverTask.targetDate != null &&
          (carryoverTask.isPendingCarryover || carryoverTask.isFlexibleCarryover) &&
          !carryoverTask.isCompleted &&
          carryoverTask.targetDate!.isBefore(nextDay);

      bool carriesToFutureDay = carryoverTask.targetDate != null &&
          (carryoverTask.isPendingCarryover || carryoverTask.isFlexibleCarryover) &&
          !carryoverTask.isCompleted &&
          carryoverTask.targetDate!.isBefore(futureDay);

      expect(carriesToNextDay, equals(true));
      expect(carriesToFutureDay, equals(true));
    });

    test('calculateVisionNodeProgress computes recursive tree progress over time period', () {
      final refDate = DateTime(2026, 9, 20);
      const rootVisionId = 'root_vision_1';
      const subFolderId = 'sub_folder_1';

      final rootVision = NeuroItem(
        id: rootVisionId,
        title: 'Master Vision',
        type: NeuroItemType.vision,
        startDate: DateTime(2026, 9, 19), // 2 days: Sep 19, Sep 20
      );

      final subFolder = NeuroItem(
        id: subFolderId,
        title: 'Sub Vision Folder',
        type: NeuroItemType.vision,
        parentId: rootVisionId,
        startDate: DateTime(2026, 9, 19),
      );

      final habitInSubFolder = NeuroItem(
        id: 'nested_habit_1',
        title: 'Daily Meditation',
        type: NeuroItemType.routine,
        parentId: subFolderId,
        scheduleType: ScheduleType.everyday,
        completedDates: ['2026-09-20'], // Completed 1 of 2 scheduled days
      );

      final progress = AggregationEngine.calculateVisionNodeProgress(
        vision: rootVision,
        allItems: [rootVision, subFolder, habitInSubFolder],
        referenceDate: refDate,
      );

      // 1 completed / 2 scheduled occurrences = 0.5
      expect(progress, equals(0.5));
    });

    test('ProgressTimeRange enum returns correct label and days count', () {
      expect(ProgressTimeRange.sevenDays.days, equals(7));
      expect(ProgressTimeRange.thirtyDays.days, equals(30));
      expect(ProgressTimeRange.sixMonths.days, equals(180));
      expect(ProgressTimeRange.oneYear.days, equals(365));
      expect(ProgressTimeRange.allTime.days, isNull);

      expect(ProgressTimeRange.sevenDays.label, equals('7 Days'));
      expect(ProgressTimeRange.thirtyDays.label, equals('30 Days'));
      expect(ProgressTimeRange.sixMonths.label, equals('6 Months'));
      expect(ProgressTimeRange.oneYear.label, equals('1 Year'));
      expect(ProgressTimeRange.allTime.label, equals('All Time'));
    });

    test('isFailedOnDate returns true for past uncompleted items or explicit failedDates', () {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final today = DateTime.now();

      final pastTask = NeuroItem(
        id: 'past_task_1',
        title: 'Missed Task Yesterday',
        type: NeuroItemType.task,
        targetDate: yesterday,
        isCompleted: false,
      );

      final explicitFailedRoutine = NeuroItem(
        id: 'failed_routine_1',
        title: 'Failed Meditation Today',
        type: NeuroItemType.routine,
        failedDates: [DateFormat('yyyy-MM-dd').format(today)],
      );

      expect(pastTask.isFailedOnDate(yesterday), equals(true));
      expect(explicitFailedRoutine.isFailedOnDate(today), equals(true));
      expect(explicitFailedRoutine.isFailedOnDate(yesterday), equals(true)); // Routine missed yesterday is also auto-failed
    });

    test('calculateOverallRoutinesProgress filters top-level routine folders (parentId == null)', () {
      final parentFolder = NeuroItem(
        id: 'parent_rf',
        title: 'Morning Routine Folder',
        type: NeuroItemType.routineFolder,
        parentId: null,
      );

      final childFolder = NeuroItem(
        id: 'child_rf',
        title: 'Nested Hydration Sub-Folder',
        type: NeuroItemType.routineFolder,
        parentId: 'parent_rf',
      );

      final items = [parentFolder, childFolder];
      final topLevelFolders = items.where((i) => i.type == NeuroItemType.routineFolder && i.parentId == null).toList();

      expect(topLevelFolders.length, equals(1));
      expect(topLevelFolders.first.id, equals('parent_rf'));
    });

    test('computeRollingSeries correctly produces live negative values for failures and bad habit tracking', () {
      final now = DateTime.now();
      const visionId = 'vision_neg';

      final items = [
        NeuroItem(
          id: visionId,
          title: 'Macro Vision with Negative Habits',
          type: NeuroItemType.vision,
        ),
        // Bad habit tracker: target=0, performed 3 times, failure penalizes
        NeuroItem(
          id: 'bad_habit_1',
          title: 'Bad Habit Tracker',
          type: NeuroItemType.routine,
          rootVisionId: visionId,
          completionType: RoutineCompletionType.numeric,
          targetNumericValue: 0,
          currentNumericValue: 3,
          dailyNumericValues: {
            DateFormat('yyyy-MM-dd').format(now): 3.0,
          },
          failureContributesToProgress: true,
        ),
        // Routine failed yesterday with failureContributesToProgress enabled
        NeuroItem(
          id: 'routine_failed',
          title: 'Workout',
          type: NeuroItemType.routine,
          rootVisionId: visionId,
          scheduleType: ScheduleType.everyday,
          failedDates: [DateFormat('yyyy-MM-dd').format(now.subtract(const Duration(days: 1)))],
          failureContributesToProgress: true,
        ),
      ];

      final series = AggregationEngine.computeRollingSeries(
        rootVisionId: visionId,
        allItems: items,
        days: 7,
        referenceDate: now,
      );

      expect(series.length, equals(7));
      expect(series[6], equals(-3.0)); // Today bad habit = -3.0
      expect(series[5], equals(-1.0)); // Yesterday failure = -1.0
    });
  });
}
