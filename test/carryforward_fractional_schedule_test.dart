import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:neurovault/models/neuro_item.dart';
import 'package:neurovault/models/app_user.dart';
import 'package:neurovault/providers/neuro_providers.dart';
import 'package:neurovault/services/aggregation_engine.dart';
import 'package:neurovault/services/hive_storage_service.dart';

class _MockStorage extends HiveStorageService {
  List<NeuroItem> _items = [];
  List<String> _collapsedCategoryIds = [];
  List<String> _expandedChecklistItemIds = [];

  @override
  List<NeuroItem> getAllItems() => _items;
  @override
  Future<void> saveAllItems(List<NeuroItem> items) async => _items = items;
  @override
  Future<void> saveItem(NeuroItem item) async {}
  @override
  bool get hasSeeded => true;
  @override
  AppUser? getCurrentUser() => null;
  @override
  List<DailyCategory> getDailyCategories() => const [];

  @override
  List<String> getCollapsedCategoryIds() => List.unmodifiable(_collapsedCategoryIds);
  @override
  Future<void> saveCollapsedCategoryIds(List<String> ids) async => _collapsedCategoryIds = List.from(ids);

  @override
  List<String> getExpandedChecklistItemIds() => List.unmodifiable(_expandedChecklistItemIds);
  @override
  Future<void> saveExpandedChecklistItemIds(List<String> ids) async => _expandedChecklistItemIds = List.from(ids);
}

void main() {
  group('Sub-Item Checklist Carry-Forward Tests', () {
    test('Carryover enabled item carries forward completed sub-items to subsequent days', () {
      final day1 = DateTime(2026, 10, 4);
      final day2 = DateTime(2026, 10, 5);
      final day1Key = DateFormat('yyyy-MM-dd').format(day1);

      final item = NeuroItem(
        id: 'task_carry_1',
        title: 'Weekly Report',
        type: NeuroItemType.task,
        isPendingCarryover: true,
        targetDate: day1,
        checklist: [
          ChecklistItem(id: 'sub_1', title: 'Expense sheet fill', isCompleted: false),
          ChecklistItem(id: 'sub_2', title: 'Summary writeup', isCompleted: false),
          ChecklistItem(id: 'sub_3', title: 'Submit to lead', isCompleted: false),
        ],
        // Day 1 has sub_1 checked
        dailyChecklistCompletions: {
          day1Key: ['sub_1'],
        },
      );

      // On Day 1, sub_1 is completed, 1/3
      expect(item.isChecklistItemCompletedOnDate('sub_1', day1), isTrue);
      expect(item.isChecklistItemCompletedOnDate('sub_2', day1), isFalse);
      expect(item.getChecklistCompletedCountForDate(day1), equals(1));

      // On Day 2, sub_1 carries forward!
      expect(item.isChecklistItemCompletedOnDate('sub_1', day2), isTrue);
      expect(item.isChecklistItemCompletedOnDate('sub_2', day2), isFalse);
      expect(item.getChecklistCompletedCountForDate(day2), equals(1));
    });

    test('Carryover disabled item does not inherit previous day completed sub-items', () {
      final day1 = DateTime(2026, 10, 4);
      final day2 = DateTime(2026, 10, 5);
      final day1Key = DateFormat('yyyy-MM-dd').format(day1);

      final item = NeuroItem(
        id: 'task_no_carry',
        title: 'Daily Hygiene',
        type: NeuroItemType.task,
        isPendingCarryover: false,
        isFlexibleCarryover: false,
        targetDate: day1,
        checklist: [
          ChecklistItem(id: 'sub_1', title: 'Brush teeth', isCompleted: false),
          ChecklistItem(id: 'sub_2', title: 'Floss', isCompleted: false),
        ],
        dailyChecklistCompletions: {
          day1Key: ['sub_1'],
        },
      );

      // On Day 1, sub_1 is completed
      expect(item.isChecklistItemCompletedOnDate('sub_1', day1), isTrue);

      // On Day 2, carryover is disabled so sub_1 is not inherited
      expect(item.isChecklistItemCompletedOnDate('sub_1', day2), isFalse);
      expect(item.getChecklistCompletedCountForDate(day2), equals(0));
    });

    test('Recurring routine resets carry-forward sub-items when new scheduled cycle arrives', () {
      // Routine scheduled on Tuesdays and Thursdays
      // Tuesday = 2026-10-06 (weekday 2), Wednesday = 2026-10-07, Thursday = 2026-10-08 (weekday 4)
      final tuesday = DateTime(2026, 10, 6);
      final wednesday = DateTime(2026, 10, 7);
      final thursday = DateTime(2026, 10, 8);
      final tuesdayKey = DateFormat('yyyy-MM-dd').format(tuesday);

      final routine = NeuroItem(
        id: 'routine_repeat',
        title: 'Bi-weekly Gym',
        type: NeuroItemType.routine,
        isPendingCarryover: true,
        scheduleType: ScheduleType.specificDaysOfWeek,
        selectedDaysOfWeek: const [DateTime.tuesday, DateTime.thursday],
        startDate: tuesday,
        checklist: [
          ChecklistItem(id: 'c_1', title: 'Warm up', isCompleted: false),
          ChecklistItem(id: 'c_2', title: 'Main workout', isCompleted: false),
        ],
        dailyChecklistCompletions: {
          tuesdayKey: ['c_1'],
        },
      );

      // On Tuesday, c_1 completed
      expect(routine.isChecklistItemCompletedOnDate('c_1', tuesday), isTrue);

      // On Wednesday (off-day, carrying forward), c_1 is inherited
      expect(routine.isChecklistItemCompletedOnDate('c_1', wednesday), isTrue);
      expect(routine.getChecklistCompletedCountForDate(wednesday), equals(1));

      // On Thursday (new scheduled recurrence day), resets to fresh cycle!
      expect(routine.isChecklistItemCompletedOnDate('c_1', thursday), isFalse);
      expect(routine.getChecklistCompletedCountForDate(thursday), equals(0));
    });
  });

  group('Fractional Progress Impact Tests', () {
    test('Numeric routine partial completion returns proportional fraction', () {
      final date = DateTime(2026, 10, 5);
      final dateKey = DateFormat('yyyy-MM-dd').format(date);

      final routine = NeuroItem(
        id: 'water_routine',
        title: 'Drink 2000ml water',
        type: NeuroItemType.routine,
        completionType: RoutineCompletionType.numeric,
        targetNumericValue: 2000,
        dailyNumericValues: {
          dateKey: 500, // 500 / 2000 = 0.25 (25%)
        },
      );

      final fraction = AggregationEngine.getItemCompletionFractionOnDate(routine, date);
      expect(fraction, closeTo(0.25, 0.001));
    });

    test('Checklist task partial completion returns proportional fraction', () {
      final date = DateTime(2026, 10, 5);
      final dateKey = DateFormat('yyyy-MM-dd').format(date);

      final task = NeuroItem(
        id: 'chk_task',
        title: 'Project Launch Steps',
        type: NeuroItemType.task,
        targetDate: date,
        checklist: [
          ChecklistItem(id: 's1', title: 'Step 1', isCompleted: false),
          ChecklistItem(id: 's2', title: 'Step 2', isCompleted: false),
          ChecklistItem(id: 's3', title: 'Step 3', isCompleted: false),
          ChecklistItem(id: 's4', title: 'Step 4', isCompleted: false),
          ChecklistItem(id: 's5', title: 'Step 5', isCompleted: false),
        ],
        dailyChecklistCompletions: {
          dateKey: ['s1', 's2'], // 2 of 5 = 0.4 (40%)
        },
      );

      final fraction = AggregationEngine.getItemCompletionFractionOnDate(task, date);
      expect(fraction, closeTo(0.40, 0.001));
    });

    test('Routine folder progress accumulates fractional completions accurately', () {
      final date = DateTime(2026, 10, 5);
      final dateKey = DateFormat('yyyy-MM-dd').format(date);

      final folder = NeuroItem(
        id: 'folder_f1',
        title: 'Wellness',
        type: NeuroItemType.routineFolder,
        startDate: date,
        endDate: date,
      );

      // Routine 1: 100% completed
      final r1 = NeuroItem(
        id: 'r_full',
        title: 'Meditation',
        type: NeuroItemType.routine,
        parentId: 'folder_f1',
        scheduleType: ScheduleType.everyday,
        completedDates: [dateKey],
        successContributesToProgress: true,
      );

      // Routine 2: 50% partial completion (numeric target 10, done 5)
      final r2 = NeuroItem(
        id: 'r_part',
        title: 'Pushups',
        type: NeuroItemType.routine,
        parentId: 'folder_f1',
        scheduleType: ScheduleType.everyday,
        completionType: RoutineCompletionType.numeric,
        targetNumericValue: 10,
        dailyNumericValues: {dateKey: 5.0},
        successContributesToProgress: true,
      );

      final allItems = [folder, r1, r2];
      final progress = AggregationEngine.calculateRoutineFolderProgress(
        folder: folder,
        allItems: allItems,
      );

      // (1.0 + 0.5) / 2 = 0.75 (75%)
      expect(progress, closeTo(0.75, 0.001));
    });

    test('calculateVisionNodeProgress accumulates fractional completions accurately', () {
      final date = DateTime(2026, 10, 5);
      final dateKey = DateFormat('yyyy-MM-dd').format(date);

      final vision = NeuroItem(
        id: 'vision_v1',
        title: 'Fitness Goals',
        type: NeuroItemType.vision,
        startDate: date,
        endDate: date,
      );

      // Task 1: 100% completed
      final t1 = NeuroItem(
        id: 't_done',
        title: 'Buy running shoes',
        type: NeuroItemType.task,
        rootVisionId: 'vision_v1',
        targetDate: date,
        isCompleted: true,
        completedAt: date,
        successContributesToProgress: true,
      );

      // Task 2: 25% completed (1 of 4 checklist items)
      final t2 = NeuroItem(
        id: 't_check',
        title: 'Plan weekly meals',
        type: NeuroItemType.task,
        rootVisionId: 'vision_v1',
        targetDate: date,
        checklist: [
          ChecklistItem(id: 'm1', title: 'Breakfast', isCompleted: false),
          ChecklistItem(id: 'm2', title: 'Lunch', isCompleted: false),
          ChecklistItem(id: 'm3', title: 'Snack', isCompleted: false),
          ChecklistItem(id: 'm4', title: 'Dinner', isCompleted: false),
        ],
        dailyChecklistCompletions: {
          dateKey: ['m1'],
        },
        successContributesToProgress: true,
      );

      final allItems = [vision, t1, t2];
      final progress = AggregationEngine.calculateVisionNodeProgress(
        vision: vision,
        allItems: allItems,
      );

      // (1.0 + 0.25) / 2 = 0.625 (62.5%)
      expect(progress, closeTo(0.625, 0.001));
    });
  });

  group('Schedule Info & Filter Tests', () {
    test('getItemScheduleInfo computes past, today, and upcoming schedule correctly', () {
      final refDate = DateTime(2026, 10, 5); // Monday
      final friday = DateTime(2026, 10, 2); // Friday (scheduled)
      final fridayKey = DateFormat('yyyy-MM-dd').format(friday);

      final routine = NeuroItem(
        id: 'gym_sched',
        title: 'Gym Workout',
        type: NeuroItemType.routine,
        scheduleType: ScheduleType.specificDaysOfWeek,
        selectedDaysOfWeek: const [DateTime.monday, DateTime.wednesday, DateTime.friday],
        startDate: DateTime(2026, 10, 1),
        completedDates: [fridayKey],
      );

      final info = AggregationEngine.getItemScheduleInfo(routine, refDate);

      // Today (Monday) is scheduled
      expect(info.isScheduledToday, isTrue);
      expect(info.isCompletedToday, isFalse);
      expect(info.todaySummary, equals('Due Today'));

      // Past summary has past schedules
      expect(info.hasPastSchedules, isTrue);
      expect(info.pastCompletedCount, equals(1));

      // Upcoming next schedule is Wednesday Oct 7
      expect(info.hasUpcoming, isTrue);
      expect(info.nextScheduledDate, isNotNull);
      expect(info.nextScheduledDate!.weekday, equals(DateTime.wednesday));
    });

    test('ScheduleFilterOption filters items into past, today, and upcoming correctly', () {
      final refDate = DateTime(2026, 10, 5); // Monday
      final yesterday = DateTime(2026, 10, 4);
      final tomorrow = DateTime(2026, 10, 6);

      // Item 1: Scheduled only today
      final itemToday = NeuroItem(
        id: 'item_today',
        title: 'Today Task',
        type: NeuroItemType.task,
        targetDate: refDate,
      );

      // Item 2: Scheduled in the past
      final itemPast = NeuroItem(
        id: 'item_past',
        title: 'Past Task',
        type: NeuroItemType.task,
        targetDate: yesterday,
        isCompleted: true,
        completedAt: yesterday,
      );

      // Item 3: Scheduled tomorrow
      final itemUpcoming = NeuroItem(
        id: 'item_upcoming',
        title: 'Tomorrow Task',
        type: NeuroItemType.task,
        targetDate: tomorrow,
      );

      // All filter matches all
      expect(AggregationEngine.matchesScheduleFilter(itemToday, ScheduleFilterOption.all, refDate), isTrue);
      expect(AggregationEngine.matchesScheduleFilter(itemPast, ScheduleFilterOption.all, refDate), isTrue);
      expect(AggregationEngine.matchesScheduleFilter(itemUpcoming, ScheduleFilterOption.all, refDate), isTrue);

      // Today filter
      expect(AggregationEngine.matchesScheduleFilter(itemToday, ScheduleFilterOption.today, refDate), isTrue);
      expect(AggregationEngine.matchesScheduleFilter(itemPast, ScheduleFilterOption.today, refDate), isFalse);

      // Past filter
      expect(AggregationEngine.matchesScheduleFilter(itemPast, ScheduleFilterOption.past, refDate), isTrue);
      expect(AggregationEngine.matchesScheduleFilter(itemUpcoming, ScheduleFilterOption.past, refDate), isFalse);

      // Upcoming filter
      expect(AggregationEngine.matchesScheduleFilter(itemUpcoming, ScheduleFilterOption.upcoming, refDate), isTrue);
      expect(AggregationEngine.matchesScheduleFilter(itemPast, ScheduleFilterOption.upcoming, refDate), isFalse);
    });
  });

  group('Reset to Unmarked and Partial Completion Indicator Tests', () {
    test('resetItemForDate clears completed status, dates, and completedAt', () {
      final date = DateTime(2026, 10, 5);
      final dateKey = DateFormat('yyyy-MM-dd').format(date);

      final task = NeuroItem(
        id: 't_reset_comp',
        title: 'Task to Reset',
        type: NeuroItemType.task,
        targetDate: date,
        isCompleted: true,
        completedAt: date,
        completedDates: [dateKey],
      );

      final notifier = NeuroItemsNotifier(_MockStorage())..setItems([task]);
      expect(notifier.state.first.isCompleted, isTrue);
      expect(notifier.state.first.completedDates.contains(dateKey), isTrue);

      notifier.resetItemForDate(task.id, date);

      final resetItem = notifier.state.first;
      expect(resetItem.isCompleted, isFalse);
      expect(resetItem.completedDates.contains(dateKey), isFalse);
      expect(resetItem.completedAt, isNull);
    });

    test('resetItemForDate clears failed status and failedDates', () {
      final date = DateTime(2026, 10, 5);
      final dateKey = DateFormat('yyyy-MM-dd').format(date);

      final routine = NeuroItem(
        id: 'r_reset_fail',
        title: 'Routine to Reset Failed',
        type: NeuroItemType.routine,
        failedDates: [dateKey],
      );

      final notifier = NeuroItemsNotifier(_MockStorage())..setItems([routine]);
      expect(notifier.state.first.failedDates.contains(dateKey), isTrue);

      notifier.resetItemForDate(routine.id, date);

      final resetItem = notifier.state.first;
      expect(resetItem.failedDates.contains(dateKey), isFalse);
    });

    test('resetItemForDate clears numeric progress and sub-checklists for date', () {
      final date = DateTime(2026, 10, 5);
      final dateKey = DateFormat('yyyy-MM-dd').format(date);

      final routine = NeuroItem(
        id: 'r_partial',
        title: 'Water Intake',
        type: NeuroItemType.routine,
        completionType: RoutineCompletionType.numeric,
        targetNumericValue: 10,
        dailyNumericValues: {dateKey: 5.0},
        checklist: [
          ChecklistItem(id: 'c1', title: 'Glass 1', isCompleted: false),
          ChecklistItem(id: 'c2', title: 'Glass 2', isCompleted: false),
        ],
        dailyChecklistCompletions: {
          dateKey: ['c1'],
        },
      );

      final notifier = NeuroItemsNotifier(_MockStorage())..setItems([routine]);

      // Before reset: partial fraction is 0.5 (numeric)
      final fractionBefore = AggregationEngine.getItemCompletionFractionOnDate(notifier.state.first, date);
      expect(fractionBefore, closeTo(0.5, 0.001));

      // Reset to unmarked
      notifier.resetItemForDate(routine.id, date);

      final resetItem = notifier.state.first;
      expect(resetItem.getNumericValueForDate(date), equals(0.0));
      expect(resetItem.getChecklistCompletedCountForDate(date), equals(0));
      final fractionAfter = AggregationEngine.getItemCompletionFractionOnDate(resetItem, date);
      expect(fractionAfter, equals(0.0));
    });

    test('toggleCompletionForDate automatically clears failed status when marking completed', () {
      final date = DateTime(2026, 10, 5);
      final dateKey = DateFormat('yyyy-MM-dd').format(date);

      final task = NeuroItem(
        id: 't_fail_then_comp',
        title: 'Task Failed Then Done',
        type: NeuroItemType.task,
        targetDate: date,
        failedDates: [dateKey],
      );

      final notifier = NeuroItemsNotifier(_MockStorage())..setItems([task]);
      expect(notifier.state.first.failedDates.contains(dateKey), isTrue);

      // Toggle complete
      notifier.toggleCompletionForDate(task.id, date);

      final updated = notifier.state.first;
      expect(updated.isCompleted, isTrue);
      expect(updated.completedDates.contains(dateKey), isTrue);
      expect(updated.failedDates.contains(dateKey), isFalse); // Failed cleared!
    });

    test('Partial completion fraction triggers isPartiallyCompleted flag accurately', () {
      final now = DateTime.now();
      final date = DateTime(now.year, now.month, now.day);
      final dateKey = DateFormat('yyyy-MM-dd').format(date);

      // 1. Unmarked task: fraction = 0.0
      final taskUnmarked = NeuroItem(
        id: 't_unmarked',
        title: 'Task Unmarked',
        type: NeuroItemType.task,
        targetDate: date,
      );
      final fracUnmarked = AggregationEngine.getItemCompletionFractionOnDate(taskUnmarked, date);
      final isPartUnmarked = !taskUnmarked.isCompletedOnDate(date) &&
          !taskUnmarked.isFailedOnDate(date) &&
          fracUnmarked > 0.0 &&
          fracUnmarked < 1.0;
      expect(isPartUnmarked, isFalse);

      // 2. Partial task (3 out of 10 done): fraction = 0.3
      final taskPartial = NeuroItem(
        id: 't_partial',
        title: 'Task Partial',
        type: NeuroItemType.task,
        targetDate: date,
        completionType: RoutineCompletionType.numeric,
        targetNumericValue: 10,
        dailyNumericValues: {dateKey: 3.0},
      );
      final fracPartial = AggregationEngine.getItemCompletionFractionOnDate(taskPartial, date);
      final isPartPartial = !taskPartial.isCompletedOnDate(date) &&
          !taskPartial.isFailedOnDate(date) &&
          fracPartial > 0.0 &&
          fracPartial < 1.0;
      expect(isPartPartial, isTrue);
      expect(fracPartial, closeTo(0.3, 0.001));

      // 3. Fully completed task: fraction = 1.0
      final taskComplete = NeuroItem(
        id: 't_complete',
        title: 'Task Complete',
        type: NeuroItemType.task,
        targetDate: date,
        isCompleted: true,
        completedDates: [dateKey],
      );
      final fracComplete = AggregationEngine.getItemCompletionFractionOnDate(taskComplete, date);
      final isPartComplete = !taskComplete.isCompletedOnDate(date) &&
          !taskComplete.isFailedOnDate(date) &&
          fracComplete > 0.0 &&
          fracComplete < 1.0;
      expect(isPartComplete, isFalse);
      expect(fracComplete, equals(1.0));
    });

    test('Past date resetItemForDate marks item as unmarked and overrides auto-fail', () {
      final pastDate = DateTime.now().subtract(const Duration(days: 2));
      final pastDay = DateTime(pastDate.year, pastDate.month, pastDate.day);
      final pastKey = DateFormat('yyyy-MM-dd').format(pastDay);

      final task = NeuroItem(
        id: 'task_past_reset',
        title: 'Past Task',
        type: NeuroItemType.task,
        targetDate: pastDay,
        isCompleted: false,
        failedDates: [pastKey],
      );

      final notifier = NeuroItemsNotifier(_MockStorage())..setItems([task]);

      // Before reset: isFailedOnDate is true
      expect(notifier.state.first.isFailedOnDate(pastDay), isTrue);

      // Reset to unmarked
      notifier.resetItemForDate(task.id, pastDay);

      final resetItem = notifier.state.first;
      expect(resetItem.unmarkedDates.contains(pastKey), isTrue);
      expect(resetItem.failedDates.contains(pastKey), isFalse);
      expect(resetItem.completedDates.contains(pastKey), isFalse);
      // Crucial: isFailedOnDate is false despite being in the past!
      expect(resetItem.isFailedOnDate(pastDay), isFalse);
      expect(resetItem.isCompletedOnDate(pastDay), isFalse);
      expect(AggregationEngine.getItemCompletionFractionOnDate(resetItem, pastDay), equals(0.0));

      // Marking complete removes it from unmarkedDates
      notifier.toggleCompletionForDate(task.id, pastDay);
      final completedItem = notifier.state.first;
      expect(completedItem.unmarkedDates.contains(pastKey), isFalse);
      expect(completedItem.isCompletedOnDate(pastDay), isTrue);
    });

    test('Item insights calculateItemInsights handles empty and non-empty allItems safely', () {
      final item = NeuroItem(
        id: 'routine_item',
        title: 'Morning Walk',
        type: NeuroItemType.routine,
        scheduleType: ScheduleType.everyday,
      );

      // Safe with empty allItems
      final insightsEmpty = AggregationEngine.calculateItemInsights(
        item: item,
        allItems: const [],
        lookbackDays: 90,
      );
      expect(insightsEmpty['isFolder'], isFalse);
      expect(insightsEmpty['totalCompleted'], isA<double>());
      expect(insightsEmpty['completionRate'], isA<double>());

      // Safe with allItems
      final insightsPopulated = AggregationEngine.calculateItemInsights(
        item: item,
        allItems: [item],
        lookbackDays: 90,
      );
      expect(insightsPopulated['isFolder'], isFalse);
      expect(insightsPopulated['totalCompleted'], isA<double>());
    });
  });

  group('Carry-Forward Stopped When Marked Failed Tests', () {
    test('Unmarked/pending carryover task carries forward to next day', () {
      final day1 = DateTime(2026, 10, 4);
      final day2 = DateTime(2026, 10, 5);

      final task = NeuroItem(
        id: 'carry_pending',
        title: 'Pending Carryover Task',
        type: NeuroItemType.task,
        targetDate: day1,
        isPendingCarryover: true,
        createdAt: day1,
      );

      final mockStorage = _MockStorage();
      final container = ProviderContainer(
        overrides: [
          storageServiceProvider.overrideWithValue(mockStorage),
        ],
      );
      container.read(neuroItemsProvider.notifier).setItems([task]);

      // Day 1: scheduled
      final day1Tasks = container.read(dateTasksProvider(day1));
      expect(day1Tasks.any((t) => t.id == 'carry_pending'), isTrue);

      final day1TrackItems = container.read(dailyTrackItemsProvider(day1));
      expect(day1TrackItems.any((t) => t.id == 'carry_pending'), isTrue);

      // Day 2: carries forward because unmarked/pending
      final day2Tasks = container.read(dateTasksProvider(day2));
      expect(day2Tasks.any((t) => t.id == 'carry_pending'), isTrue);

      final day2TrackItems = container.read(dailyTrackItemsProvider(day2));
      expect(day2TrackItems.any((t) => t.id == 'carry_pending'), isTrue);
    });

    test('Carryover task marked as failed on Day 1 does NOT carry forward to Day 2', () {
      final day1 = DateTime(2026, 10, 4);
      final day2 = DateTime(2026, 10, 5);
      final day1Key = DateFormat('yyyy-MM-dd').format(day1);

      final task = NeuroItem(
        id: 'carry_failed',
        title: 'Failed Carryover Task',
        type: NeuroItemType.task,
        targetDate: day1,
        isPendingCarryover: true,
        createdAt: day1,
        failedDates: [day1Key],
      );

      final mockStorage = _MockStorage();
      final container = ProviderContainer(
        overrides: [
          storageServiceProvider.overrideWithValue(mockStorage),
        ],
      );
      container.read(neuroItemsProvider.notifier).setItems([task]);

      // Day 1: Scheduled on target date (shows as failed)
      final day1Tasks = container.read(dateTasksProvider(day1));
      expect(day1Tasks.any((t) => t.id == 'carry_failed'), isTrue);

      final day1TrackItems = container.read(dailyTrackItemsProvider(day1));
      expect(day1TrackItems.any((t) => t.id == 'carry_failed'), isTrue);

      // Day 2: Does NOT carry forward because it was marked as failed!
      final day2Tasks = container.read(dateTasksProvider(day2));
      expect(day2Tasks.any((t) => t.id == 'carry_failed'), isFalse);

      final day2TrackItems = container.read(dailyTrackItemsProvider(day2));
      expect(day2TrackItems.any((t) => t.id == 'carry_failed'), isFalse);
    });

    test('Carryover routine marked as failed in cycle does not carry forward to subsequent cycle days', () {
      // Routine scheduled on Tuesdays and Fridays
      final tuesday = DateTime(2026, 10, 6);
      final wednesday = DateTime(2026, 10, 7);
      final thursday = DateTime(2026, 10, 8);
      final tuesdayKey = DateFormat('yyyy-MM-dd').format(tuesday);

      final routine = NeuroItem(
        id: 'routine_fail_carry',
        title: 'Gym Session',
        type: NeuroItemType.routine,
        scheduleType: ScheduleType.specificDaysOfWeek,
        selectedDaysOfWeek: const [DateTime.tuesday, DateTime.friday],
        startDate: tuesday,
        createdAt: tuesday,
        isPendingCarryover: true,
        failedDates: [tuesdayKey],
      );

      final mockStorage = _MockStorage();
      final container = ProviderContainer(
        overrides: [
          storageServiceProvider.overrideWithValue(mockStorage),
        ],
      );
      container.read(neuroItemsProvider.notifier).setItems([routine]);

      // Tuesday: scheduled
      final tuesdayItems = container.read(dailyTrackItemsProvider(tuesday));
      expect(tuesdayItems.any((i) => i.id == 'routine_fail_carry'), isTrue);

      // Wednesday & Thursday: Should NOT carry forward because marked as failed on Tuesday!
      final wednesdayItems = container.read(dailyTrackItemsProvider(wednesday));
      expect(wednesdayItems.any((i) => i.id == 'routine_fail_carry'), isFalse);

      final thursdayItems = container.read(dailyTrackItemsProvider(thursday));
      expect(thursdayItems.any((i) => i.id == 'routine_fail_carry'), isFalse);
    });

    test('Sub-checklist carryover stops if item is marked failed on a prior day in cycle', () {
      final day1 = DateTime(2026, 10, 4);
      final day2 = DateTime(2026, 10, 5);
      final day1Key = DateFormat('yyyy-MM-dd').format(day1);

      final item = NeuroItem(
        id: 'task_sub_fail',
        title: 'Complex Task',
        type: NeuroItemType.task,
        targetDate: day1,
        isPendingCarryover: true,
        checklist: [
          ChecklistItem(id: 'sub_1', title: 'Sub 1', isCompleted: false),
          ChecklistItem(id: 'sub_2', title: 'Sub 2', isCompleted: false),
        ],
        dailyChecklistCompletions: {
          day1Key: ['sub_1'],
        },
        failedDates: [day1Key],
      );

      // On Day 1, sub_1 is marked completed for that day
      expect(item.isChecklistItemCompletedOnDate('sub_1', day1), isTrue);

      // On Day 2, since item failed on Day 1, completions do NOT carry forward
      expect(item.isChecklistItemCompletedOnDate('sub_1', day2), isFalse);
      expect(item.getChecklistCompletedCountForDate(day2), equals(0));
    });

    test('Collapsed category IDs and expanded checklist item IDs persist in HiveStorageService', () async {
      final storage = _MockStorage();

      expect(storage.getCollapsedCategoryIds(), isEmpty);
      expect(storage.getExpandedChecklistItemIds(), isEmpty);

      await storage.saveCollapsedCategoryIds(['cat_1', 'cat_2']);
      await storage.saveExpandedChecklistItemIds(['item_abc', 'item_xyz']);

      expect(storage.getCollapsedCategoryIds(), equals(['cat_1', 'cat_2']));
      expect(storage.getExpandedChecklistItemIds(), equals(['item_abc', 'item_xyz']));
    });
  });

  group('Target Value Partial Progress & Failure Penalty Tests', () {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayKey = DateFormat('yyyy-MM-dd').format(today);

    test('Partial completion adds fraction when successContributesToProgress is true, ignores when false', () {
      final folder = NeuroItem(
        id: 'folder_partial',
        title: 'Routine Folder',
        type: NeuroItemType.routineFolder,
        startDate: today,
        endDate: today,
      );

      // Routine with target 100, completed 50 (fraction = 0.5)
      // Case A: successContributesToProgress = true, failureContributesToProgress = false
      final routineA = NeuroItem(
        id: 'routine_a',
        title: 'Pushups',
        type: NeuroItemType.routine,
        parentId: folder.id,
        completionType: RoutineCompletionType.numeric,
        targetNumericValue: 100,
        dailyNumericValues: {todayKey: 50.0},
        successContributesToProgress: true,
        failureContributesToProgress: false,
      );

      final progressA = AggregationEngine.calculateRoutineFolderProgress(
        folder: folder,
        allItems: [folder, routineA],
      );
      // Scheduled 1, completed 0.5 => 0.5 / 1.0 = 0.5 (50%)
      expect(progressA, closeTo(0.5, 0.001));

      // Case B: successContributesToProgress = false, failureContributesToProgress = false
      final routineB = routineA.copyWith(successContributesToProgress: false);
      final progressB = AggregationEngine.calculateRoutineFolderProgress(
        folder: folder,
        allItems: [folder, routineB],
      );
      // Success does not contribute => 0.0
      expect(progressB, closeTo(0.0, 0.001));
    });

    test('Unfinished fraction penalizes progress when failureContributesToProgress is true, ignores when false', () {
      final folder = NeuroItem(
        id: 'folder_fail',
        title: 'Routine Folder',
        type: NeuroItemType.routineFolder,
        startDate: today,
        endDate: today,
      );

      // 4 sub-items checklist, 1 checked (fraction = 0.25), unfinished = 0.75, marked failed
      final routineFailed = NeuroItem(
        id: 'routine_failed',
        title: 'Morning Routine',
        type: NeuroItemType.routine,
        parentId: folder.id,
        checklist: [
          ChecklistItem(id: 's1', title: '1', isCompleted: false),
          ChecklistItem(id: 's2', title: '2', isCompleted: false),
          ChecklistItem(id: 's3', title: '3', isCompleted: false),
          ChecklistItem(id: 's4', title: '4', isCompleted: false),
        ],
        dailyChecklistCompletions: {
          todayKey: ['s1'],
        },
        failedDates: [todayKey],
        successContributesToProgress: true,
        failureContributesToProgress: true,
      );

      final progressFailedWithPenalty = AggregationEngine.calculateRoutineFolderProgress(
        folder: folder,
        allItems: [folder, routineFailed],
      );
      // Completed = 0.25, penalty = (1.0 - 0.25) = 0.75, net = 0.25 - 0.75 = -0.5
      expect(progressFailedWithPenalty, closeTo(-0.5, 0.001));

      // Without failureContributesToProgress penalty:
      final routineNoPenalty = routineFailed.copyWith(failureContributesToProgress: false);
      final progressNoPenalty = AggregationEngine.calculateRoutineFolderProgress(
        folder: folder,
        allItems: [folder, routineNoPenalty],
      );
      // Completed = 0.25, penalty = 0.0 => 0.25
      expect(progressNoPenalty, closeTo(0.25, 0.001));
    });

    test('computeRollingSeries generates rolling line chart spots for Routine Folder with negative dips', () {
      final folder = NeuroItem(
        id: 'folder_series',
        title: 'Routine Series Folder',
        type: NeuroItemType.routineFolder,
        startDate: today.subtract(const Duration(days: 6)),
        endDate: today,
      );

      // A routine that failed yesterday with 0% progress and failureContributesToProgress: true
      final yesterday = today.subtract(const Duration(days: 1));
      final yesterdayKey = DateFormat('yyyy-MM-dd').format(yesterday);

      final routine = NeuroItem(
        id: 'routine_series',
        title: 'Study session',
        type: NeuroItemType.routine,
        parentId: folder.id,
        completionType: RoutineCompletionType.timer,
        targetNumericValue: 3600,
        timerDurationSeconds: 3600,
        dailyNumericValues: {
          todayKey: 3600.0, // 100% today
          yesterdayKey: 900.0, // 25% completed yesterday (0.25), 75% unfinished (0.75)
        },
        failedDates: [yesterdayKey],
        completedDates: [todayKey],
        successContributesToProgress: true,
        failureContributesToProgress: true,
      );

      final series = AggregationEngine.computeRollingSeries(
        rootVisionId: folder.id,
        allItems: [folder, routine],
        days: 7,
        referenceDate: today,
      );

      expect(series.length, equals(7));
      // Yesterday spot (index 5) has net dip: +0.25 completed - 0.75 unfinished = -0.50
      expect(series[5], closeTo(-0.5, 0.001));
      // Today spot (index 6) has +1.0 full completion
      expect(series[6], closeTo(1.0, 0.001));
    });

    test('ProgressTimeRange.custom exists and formats label correctly', () {
      expect(ProgressTimeRange.custom.label, equals('Custom'));
      expect(ProgressTimeRange.custom.days, isNull);
    });

    test('Custom date range calculates progress with specified days and referenceDate', () {
      final refDate = DateTime(2026, 10, 15);
      final day10 = DateTime(2026, 10, 10);
      final day10Key = DateFormat('yyyy-MM-dd').format(day10);

      final vision = NeuroItem(
        id: 'custom_vision',
        title: 'Custom Vision',
        type: NeuroItemType.vision,
        startDate: DateTime(2026, 10, 1),
      );

      final task = NeuroItem(
        id: 'custom_task',
        title: 'Custom Range Task',
        type: NeuroItemType.task,
        parentId: vision.id,
        targetDate: day10,
        completedDates: [day10Key],
        isCompleted: true,
        successContributesToProgress: true,
      );

      // Custom range: 10 days ending on refDate (Oct 6 to Oct 15) -> includes day10
      final progressWithin = AggregationEngine.calculateVisionProgress(
        rootVisionId: vision.id,
        allItems: [vision, task],
        days: 10,
        referenceDate: refDate,
      );
      expect(progressWithin, equals(1.0));

      // Custom range: 3 days ending on refDate (Oct 13 to Oct 15) -> does NOT include day10
      final progressOutside = AggregationEngine.calculateVisionProgress(
        rootVisionId: vision.id,
        allItems: [vision, task],
        days: 3,
        referenceDate: refDate,
      );
      expect(progressOutside, equals(0.0));
    });
  });
}

