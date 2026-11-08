import 'package:intl/intl.dart';
import '../models/neuro_item.dart';

enum ScheduleFilterOption {
  all('All'),
  past('Past History'),
  today('Today'),
  upcoming('Upcoming');

  final String label;
  const ScheduleFilterOption(this.label);
}

class ItemScheduleInfo {
  final bool hasPastSchedules;
  final int pastScheduledCount;
  final int pastCompletedCount;
  final int pastFailedCount;
  final String pastSummary;

  final bool isScheduledToday;
  final bool isCompletedToday;
  final bool isFailedToday;
  final double todayCompletionFraction;
  final String todaySummary;

  final bool hasUpcoming;
  final DateTime? nextScheduledDate;
  final String upcomingSummary;

  const ItemScheduleInfo({
    required this.hasPastSchedules,
    required this.pastScheduledCount,
    required this.pastCompletedCount,
    required this.pastFailedCount,
    required this.pastSummary,
    required this.isScheduledToday,
    required this.isCompletedToday,
    required this.isFailedToday,
    required this.todayCompletionFraction,
    required this.todaySummary,
    required this.hasUpcoming,
    this.nextScheduledDate,
    required this.upcomingSummary,
  });
}

class TimeSeriesPoint {
  final DateTime date;
  final double value;
  final String dayLabel;

  TimeSeriesPoint({
    required this.date,
    required this.value,
    required this.dayLabel,
  });
}

enum ProgressTimeRange {
  sevenDays,     // 7 Days
  thirtyDays,    // 30 Days
  sixMonths,     // 6 Months (180 days)
  oneYear,       // 1 Year (365 days)
  allTime,       // All Time
  custom,        // Custom Date Range
}

extension ProgressTimeRangeExtension on ProgressTimeRange {
  String get label {
    switch (this) {
      case ProgressTimeRange.sevenDays:
        return '7 Days';
      case ProgressTimeRange.thirtyDays:
        return '30 Days';
      case ProgressTimeRange.sixMonths:
        return '6 Months';
      case ProgressTimeRange.oneYear:
        return '1 Year';
      case ProgressTimeRange.allTime:
        return 'All Time';
      case ProgressTimeRange.custom:
        return 'Custom';
    }
  }

  int? get days {
    switch (this) {
      case ProgressTimeRange.sevenDays:
        return 7;
      case ProgressTimeRange.thirtyDays:
        return 30;
      case ProgressTimeRange.sixMonths:
        return 180;
      case ProgressTimeRange.oneYear:
        return 365;
      case ProgressTimeRange.allTime:
      case ProgressTimeRange.custom:
        return null;
    }
  }
}

enum TaskEvaluationStatus {
  success,
  partiallyCompleted,
  failure,
}

class ItemEvaluationResult {
  final TaskEvaluationStatus status;
  final double progressFraction; // 0.0 to 1.0
  final double scoreContribution; // +1.0 for success, +progressFraction for partial, -1.0 for failure

  const ItemEvaluationResult({
    required this.status,
    required this.progressFraction,
    required this.scoreContribution,
  });
}

class DailyNetScore {
  final int totalItems;
  final int successCount;
  final int failureCount;
  final int partialCount;
  final double totalSuccessPoints;
  final double totalFailurePoints;
  final double partialPoints;
  final double netScore;
  final double maxPossibleScore;
  final double normalizedProgress; // -1.0 to 1.0

  const DailyNetScore({
    required this.totalItems,
    required this.successCount,
    required this.failureCount,
    required this.partialCount,
    required this.totalSuccessPoints,
    required this.totalFailurePoints,
    required this.partialPoints,
    required this.netScore,
    required this.maxPossibleScore,
    required this.normalizedProgress,
  });
}

class AggregationEngine {
  /// Evaluates the task status, progress fraction, and net score contribution for an item on a date.
  /// Follows the unified task evaluation rules:
  /// A. Completed / Success: 100% progress (+1 point)
  /// B. Partially Completed: Measurable progress between 0% and 100% (+progressFraction points)
  /// C. Failed: Exactly 0% progress (-1 point)
  /// If multiple tracking methods are enabled, evaluates them together (Rule 8).
  static ItemEvaluationResult evaluateItemStatusOnDate(NeuroItem item, DateTime date) {
    final dateKey = DateFormat('yyyy-MM-dd').format(date);
    if (item.unmarkedDates.contains(dateKey)) {
      return const ItemEvaluationResult(
        status: TaskEvaluationStatus.failure,
        progressFraction: 0.0,
        scoreContribution: -1.0,
      );
    }

    // Explicitly marked completed on this date
    if (item.isCompletedOnDate(date)) {
      return const ItemEvaluationResult(
        status: TaskEvaluationStatus.success,
        progressFraction: 1.0,
        scoreContribution: 1.0,
      );
    }

    final enabledFractions = <double>[];

    // 1. Checklist
    if (item.checklist.isNotEmpty) {
      final totalSub = item.checklist.length;
      final completedSub = item.getChecklistCompletedCountForDate(date);
      if (totalSub > 0) {
        enabledFractions.add((completedSub / totalSub).clamp(0.0, 1.0));
      }
    }

    // 2. Numeric Target
    if (item.completionType == RoutineCompletionType.numeric) {
      if (item.targetNumericValue == 0) {
        // Bad habit tracker: 0 occurrences means not broken (success)
        enabledFractions.add(item.getNumericValueForDate(date) == 0 ? 1.0 : 0.0);
      } else if (item.targetNumericValue != null && item.targetNumericValue! > 0) {
        final currentVal = item.getNumericValueForDate(date);
        enabledFractions.add((currentVal / item.targetNumericValue!).clamp(0.0, 1.0));
      }
    } else if (item.type == NeuroItemType.task &&
        item.targetDate == null &&
        item.targetNumericValue != null &&
        item.targetNumericValue! > 0) {
      enabledFractions.add((item.currentNumericValue / item.targetNumericValue!).clamp(0.0, 1.0));
    }

    // 3. Timer
    if (item.completionType == RoutineCompletionType.timer) {
      final targetSeconds = item.timerDurationSeconds ?? (item.targetNumericValue?.toInt() ?? 600);
      if (targetSeconds > 0) {
        final currentVal = item.getNumericValueForDate(date);
        enabledFractions.add((currentVal / targetSeconds).clamp(0.0, 1.0));
      }
    }

    double fraction;
    if (enabledFractions.isNotEmpty) {
      // Rule 8: Evaluate multiple tracking methods together (average)
      fraction = enabledFractions.reduce((a, b) => a + b) / enabledFractions.length;
    } else {
      // Simple boolean tracking
      if (item.isCompletedOnDate(date)) {
        fraction = 1.0;
      } else {
        fraction = 0.0;
      }
    }

    if (fraction >= 1.0) {
      return const ItemEvaluationResult(
        status: TaskEvaluationStatus.success,
        progressFraction: 1.0,
        scoreContribution: 1.0,
      );
    } else if (fraction > 0.0) {
      return ItemEvaluationResult(
        status: TaskEvaluationStatus.partiallyCompleted,
        progressFraction: fraction,
        scoreContribution: fraction,
      );
    } else {
      return const ItemEvaluationResult(
        status: TaskEvaluationStatus.failure,
        progressFraction: 0.0,
        scoreContribution: -1.0,
      );
    }
  }

  /// Returns the fraction (0.0 to 1.0) of completion for an item on a specific date.
  /// Fully completed returns 1.0.
  /// Partially completed returns the proportional fraction.
  static double getItemCompletionFractionOnDate(NeuroItem item, DateTime date) {
    return evaluateItemStatusOnDate(item, date).progressFraction;
  }

  /// Computes the net performance score for a list of items on a given date.
  /// Formula: Net Success Score = Total Success Points - Total Failure Points + Partial Completion Points
  static DailyNetScore calculateDailyNetScore(List<NeuroItem> items, DateTime date) {
    if (items.isEmpty) {
      return const DailyNetScore(
        totalItems: 0,
        successCount: 0,
        failureCount: 0,
        partialCount: 0,
        totalSuccessPoints: 0.0,
        totalFailurePoints: 0.0,
        partialPoints: 0.0,
        netScore: 0.0,
        maxPossibleScore: 0.0,
        normalizedProgress: 0.0,
      );
    }

    int successCount = 0;
    int failureCount = 0;
    int partialCount = 0;
    double totalSuccessPoints = 0.0;
    double totalFailurePoints = 0.0;
    double partialPoints = 0.0;

    for (final item in items) {
      final eval = evaluateItemStatusOnDate(item, date);
      switch (eval.status) {
        case TaskEvaluationStatus.success:
          successCount++;
          totalSuccessPoints += 1.0;
          break;
        case TaskEvaluationStatus.partiallyCompleted:
          partialCount++;
          partialPoints += eval.progressFraction;
          break;
        case TaskEvaluationStatus.failure:
          failureCount++;
          totalFailurePoints += 1.0;
          break;
      }
    }

    final netScore = totalSuccessPoints - totalFailurePoints + partialPoints;
    final maxScore = items.length.toDouble();
    final normalized = maxScore > 0 ? (netScore / maxScore).clamp(-1.0, 1.0) : 0.0;

    return DailyNetScore(
      totalItems: items.length,
      successCount: successCount,
      failureCount: failureCount,
      partialCount: partialCount,
      totalSuccessPoints: totalSuccessPoints,
      totalFailurePoints: totalFailurePoints,
      partialPoints: partialPoints,
      netScore: netScore,
      maxPossibleScore: maxScore,
      normalizedProgress: normalized,
    );
  }

  /// Analytics engine that computes rolling time-series completion points over custom days.
  /// Supports 7 days, 30 days, 6 months (180 days), 1 year (365 days), and All Time.
  static List<double> computeRollingSeries({
    required String rootVisionId,
    required List<NeuroItem> allItems,
    int days = 7,
    DateTime? referenceDate,
  }) {
    final ref = referenceDate ?? DateTime.now();
    final today = DateTime(ref.year, ref.month, ref.day);

    final rootItem = allItems.firstWhere(
      (item) => item.id == rootVisionId,
      orElse: () => NeuroItem(
        id: rootVisionId,
        title: '',
        type: NeuroItemType.vision,
      ),
    );

    if (rootItem.noVisionXpEnabled) {
      return List<double>.filled(days, 0.0);
    }

    final Map<int, double> dayCounts = {};
    for (int i = 0; i < days; i++) {
      dayCounts[i] = 0.0;
    }

    // Collect all items belonging to rootVisionId (direct children, root itself, and all descendants)
    final relevantItems = allItems.where((item) =>
        item.rootVisionId == rootVisionId ||
        item.id == rootVisionId ||
        item.parentId == rootVisionId).toSet();
    for (final desc in getDescendants(rootVisionId, allItems)) {
      relevantItems.add(desc);
    }
    if (relevantItems.isEmpty && rootItem.id == rootVisionId) {
      relevantItems.add(rootItem);
    }

    for (int i = 0; i < days; i++) {
      final targetDay = today.subtract(Duration(days: (days - 1) - i));
      double dayScore = 0.0;

      for (final item in relevantItems) {
        // Skip pure container groupings
        if (item.type == NeuroItemType.vision || item.type == NeuroItemType.routineFolder || item.type == NeuroItemType.goal) {
          continue;
        }

        // 1. Bad habit tracking (targetNumericValue == 0)
        if (item.completionType == RoutineCompletionType.numeric && item.targetNumericValue == 0) {
          final count = item.getNumericValueForDate(targetDay);
          if (count > 0) {
            // Bad habit committed count times: live negative contribution
            if (item.failureContributesToProgress) {
              dayScore -= count;
            }
          } else {
            if (item.successContributesToProgress && item.isCompletedOnDate(targetDay)) {
              dayScore += 1.0;
            }
          }
          continue;
        }

        // 2. Tasks (one-time deliverables)
        if (item.type == NeuroItemType.task) {
          DateTime? effectiveDate;
          if (item.completedAt != null) {
            effectiveDate = DateTime(item.completedAt!.year, item.completedAt!.month, item.completedAt!.day);
          } else if (item.targetDate != null) {
            effectiveDate = DateTime(item.targetDate!.year, item.targetDate!.month, item.targetDate!.day);
          }

          if (item.isCompleted) {
            if (effectiveDate != null && effectiveDate.isAtSameMomentAs(targetDay)) {
              if (item.successContributesToProgress) {
                dayScore += 1.0;
              }
            }
          } else {
            final isTargetDay = effectiveDate != null && effectiveDate.isAtSameMomentAs(targetDay);
            final dateKey = DateFormat('yyyy-MM-dd').format(targetDay);
            final hasActivityToday = item.dailyNumericValues.containsKey(dateKey) ||
                item.dailyChecklistCompletions.containsKey(dateKey);

            if (isTargetDay || hasActivityToday) {
              final fraction = getItemCompletionFractionOnDate(item, targetDay);
              if (item.successContributesToProgress) {
                dayScore += fraction;
              }
              if (item.failureContributesToProgress && item.isFailedOnDate(targetDay)) {
                final unfinished = (1.0 - fraction).clamp(0.0, 1.0);
                dayScore -= unfinished;
              }
            }
          }
          continue;
        }

        // 3. Routines
        if (item.type == NeuroItemType.routine) {
          final isScheduled = isItemScheduledOnDate(item, targetDay);
          final isDone = item.isCompletedOnDate(targetDay);

          if (isDone) {
            if (item.successContributesToProgress) {
              dayScore += 1.0;
            }
          } else if (isScheduled) {
            final fraction = getItemCompletionFractionOnDate(item, targetDay);
            if (item.successContributesToProgress) {
              dayScore += fraction;
            }
            if (item.failureContributesToProgress && item.isFailedOnDate(targetDay)) {
              final unfinished = (1.0 - fraction).clamp(0.0, 1.0);
              dayScore -= unfinished;
            }
          }
          continue;
        }
      }

      dayCounts[i] = dayScore;
    }

    return List<double>.generate(days, (i) => dayCounts[i] ?? 0.0);
  }

  /// Bounded rolling 7-day time-series analytics engine.
  static List<double> compute7DayRollingSeries({
    required String rootVisionId,
    required List<NeuroItem> allItems,
    DateTime? referenceDate,
  }) {
    return computeRollingSeries(
      rootVisionId: rootVisionId,
      allItems: allItems,
      days: 7,
      referenceDate: referenceDate,
    );
  }

  /// Recursively finds all descendant items under a parent item ID
  static List<NeuroItem> getDescendants(String parentId, List<NeuroItem> allItems) {
    final direct = allItems.where((item) =>
        (item.parentId == parentId || item.rootVisionId == parentId) && item.id != parentId).toList();
    final Map<String, NeuroItem> resultMap = {for (final e in direct) e.id: e};

    for (final child in direct) {
      if (child.parentId == parentId) {
        final subDescendants = getDescendants(child.id, allItems);
        for (final sub in subDescendants) {
          resultMap[sub.id] = sub;
        }
      }
    }
    return resultMap.values.toList();
  }

  /// Calculates progress for any Vision or Sub-Vision container node over its time period
  /// using the same system & logic as Button 2 (scheduled occurrences checked in Daily Track)
  static double calculateVisionNodeProgress({
    required NeuroItem vision,
    required List<NeuroItem> allItems,
    DateTime? referenceDate,
    int? days,
  }) {
    final now = referenceDate ?? DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);

    final start = vision.startDate ?? vision.createdAt;
    var startDate = DateTime(start.year, start.month, start.day);

    if (days != null) {
      final rangeStart = todayDate.subtract(Duration(days: days - 1));
      if (rangeStart.isAfter(startDate)) {
        startDate = rangeStart;
      }
    }

    final end = vision.endDate ?? todayDate;
    final endDate = DateTime(end.year, end.month, end.day);

    if (endDate.isBefore(startDate)) return 0.0;

    final descendants = getDescendants(vision.id, allItems);
    if (descendants.isEmpty) return 0.0;

    final leafTasks = descendants.where((item) =>
        item.type == NeuroItemType.task || item.type == NeuroItemType.routine).toList();

    if (leafTasks.isEmpty) return 0.0;

    int totalScheduled = 0;
    double totalCompleted = 0.0;
    double totalPenalties = 0.0;

    // 1. Process non-dated one-time tasks under this vision (counted once as macro deliverables)
    final nonDatedTasks = leafTasks.where((item) => item.type == NeuroItemType.task && item.targetDate == null);
    for (final item in nonDatedTasks) {
      final fraction = getItemCompletionFractionOnDate(item, todayDate);
      if (item.successContributesToProgress || item.failureContributesToProgress) {
        totalScheduled++;
      }
      if (item.successContributesToProgress) {
        totalCompleted += fraction;
      }
      if (item.failureContributesToProgress && !item.isCompleted) {
        final unfinished = (1.0 - fraction).clamp(0.0, 1.0);
        totalPenalties += unfinished;
      }
    }

    // 2. Process scheduled routines and dated tasks across the time window
    DateTime cursor = startDate;
    while (!cursor.isAfter(endDate)) {
      for (final item in leafTasks) {
        if (item.type == NeuroItemType.routine) {
          if (isItemScheduledOnDate(item, cursor)) {
            final fraction = getItemCompletionFractionOnDate(item, cursor);
            if (item.successContributesToProgress || item.failureContributesToProgress) {
              totalScheduled++;
            }
            if (item.successContributesToProgress) {
              totalCompleted += fraction;
            }
            if (item.failureContributesToProgress && item.isFailedOnDate(cursor)) {
              final unfinished = (1.0 - fraction).clamp(0.0, 1.0);
              totalPenalties += unfinished;
            }
          }
        } else if (item.type == NeuroItemType.task && item.targetDate != null) {
          final targetDay = DateTime(item.targetDate!.year, item.targetDate!.month, item.targetDate!.day);
          if (targetDay.isAtSameMomentAs(cursor)) {
            final fraction = getItemCompletionFractionOnDate(item, cursor);
            if (item.successContributesToProgress || item.failureContributesToProgress) {
              totalScheduled++;
            }
            if (item.successContributesToProgress) {
              totalCompleted += fraction;
            }
            if (item.failureContributesToProgress && item.isFailedOnDate(cursor)) {
              final unfinished = (1.0 - fraction).clamp(0.0, 1.0);
              totalPenalties += unfinished;
            }
          }
        }
      }
      cursor = cursor.add(const Duration(days: 1));
    }

    if (totalScheduled > 0) {
      final net = totalCompleted - totalPenalties;
      return (net / totalScheduled).clamp(-1.0, 1.0);
    }

    if (days != null) return 0.0;

    final contributing = leafTasks.where((t) => t.successContributesToProgress).toList();
    if (contributing.isEmpty) return 0.0;
    final completedCount = contributing.fold<double>(
      0.0,
      (sum, t) => sum + getItemCompletionFractionOnDate(t, todayDate),
    );
    return (completedCount / contributing.length).clamp(0.0, 1.0);
  }

  /// Calculates macro completion percentage for a Vision container
  static double calculateVisionProgress({
    required String rootVisionId,
    required List<NeuroItem> allItems,
    int? days,
    DateTime? referenceDate,
  }) {
    final root = allItems.firstWhere(
      (e) => e.id == rootVisionId,
      orElse: () => NeuroItem(id: rootVisionId, title: '', type: NeuroItemType.vision),
    );
    return calculateVisionNodeProgress(
      vision: root,
      allItems: allItems,
      days: days,
      referenceDate: referenceDate,
    );
  }

  /// Calculates routine consistency score over the last 7 days (percentage of days completed)
  static double calculateRoutineConsistency({
    required String routineId,
    required List<NeuroItem> allItems,
  }) {
    final item = allItems.firstWhere(
      (e) => e.id == routineId,
      orElse: () => NeuroItem(id: routineId, title: '', type: NeuroItemType.routine),
    );

    if (item.streakCount > 0) {
      return (item.streakCount / 7.0).clamp(0.0, 1.0);
    }
    return item.isCompleted ? 1.0 : 0.0;
  }

  /// Checks if a routine item is scheduled on a given DateTime
  static bool isItemScheduledOnDate(NeuroItem item, DateTime targetDay) {
    if (item.type != NeuroItemType.routine) return false;
    final day = DateTime(targetDay.year, targetDay.month, targetDay.day);
    if (item.startDate != null) {
      final startDay = DateTime(item.startDate!.year, item.startDate!.month, item.startDate!.day);
      if (day.isBefore(startDay)) return false;
    }

    switch (item.scheduleType) {
      case ScheduleType.everyday:
        return true;
      case ScheduleType.specificDaysOfWeek:
        return item.selectedDaysOfWeek.contains(day.weekday);
      case ScheduleType.specificDaysOfMonth:
        final dayStr = day.day.toString();
        if (item.selectedDaysOfMonth.contains(dayStr)) return true;
        if (day.day == 1 && item.selectedDaysOfMonth.contains('FIRST_DAY')) return true;
        final lastDayOfMonth = DateTime(day.year, day.month + 1, 0).day;
        if (day.day == lastDayOfMonth && item.selectedDaysOfMonth.contains('LAST_DAY')) return true;
        return false;
      case ScheduleType.specificDaysOfYear:
        final monthDayStr = '${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
        if (item.selectedDaysOfYear.contains(monthDayStr)) return true;
        if (day.month == 1 && day.day == 1 && item.selectedDaysOfYear.contains('FIRST_DAY')) return true;
        if (day.month == 12 && day.day == 31 && item.selectedDaysOfYear.contains('LAST_DAY')) return true;
        return false;
      case ScheduleType.someDaysPerPeriod:
        return true;
      case ScheduleType.repeatInterval:
        final diff = day.difference(DateTime(item.createdAt.year, item.createdAt.month, item.createdAt.day)).inDays;
        return diff >= 0 && (diff % (item.repeatIntervalDays > 0 ? item.repeatIntervalDays : 1)) == 0;
    }
  }

  /// Calculates routine folder progress over its time period (startDate to endDate ?? today)
  static double calculateRoutineFolderProgress({
    required NeuroItem folder,
    required List<NeuroItem> allItems,
    DateTime? referenceDate,
    int? days,
  }) {
    final now = referenceDate ?? DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);

    final start = folder.startDate ?? folder.createdAt;
    var startDate = DateTime(start.year, start.month, start.day);

    if (days != null) {
      final rangeStart = todayDate.subtract(Duration(days: days - 1));
      if (rangeStart.isAfter(startDate)) {
        startDate = rangeStart;
      }
    }

    final end = folder.endDate ?? todayDate;
    final endDate = DateTime(end.year, end.month, end.day);

    if (endDate.isBefore(startDate)) return 0.0;

    final descendants = getDescendants(folder.id, allItems);
    final tasks = descendants
        .where((item) => item.type == NeuroItemType.routine || item.type == NeuroItemType.task)
        .toList();

    if (tasks.isEmpty) return 0.0;

    int totalScheduled = 0;
    double totalCompleted = 0.0;
    double totalPenalties = 0.0;

    DateTime cursor = startDate;
    while (!cursor.isAfter(endDate)) {
      for (final task in tasks) {
        bool isScheduled = false;
        if (task.type == NeuroItemType.routine) {
          isScheduled = isItemScheduledOnDate(task, cursor);
        } else if (task.type == NeuroItemType.task && task.targetDate != null) {
          final tDay = DateTime(task.targetDate!.year, task.targetDate!.month, task.targetDate!.day);
          isScheduled = tDay.isAtSameMomentAs(cursor);
        }

        if (isScheduled) {
          final fraction = getItemCompletionFractionOnDate(task, cursor);
          if (task.successContributesToProgress || task.failureContributesToProgress) {
            totalScheduled++;
          }
          if (task.successContributesToProgress) {
            totalCompleted += fraction;
          }
          if (task.failureContributesToProgress && task.isFailedOnDate(cursor)) {
            final unfinished = (1.0 - fraction).clamp(0.0, 1.0);
            totalPenalties += unfinished;
          }
        }
      }
      cursor = cursor.add(const Duration(days: 1));
    }

    if (totalScheduled == 0) {
      if (days != null) return 0.0;
      if (tasks.isEmpty) return 0.0;
      final contributing = tasks.where((t) => t.successContributesToProgress).toList();
      if (contributing.isEmpty) return 0.0;
      final sum = contributing.fold<double>(0.0, (acc, t) => acc + getItemCompletionFractionOnDate(t, todayDate));
      return (sum / contributing.length).clamp(0.0, 1.0);
    }
    final net = totalCompleted - totalPenalties;
    return (net / totalScheduled).clamp(-1.0, 1.0);
  }

  /// Calculates overall routines progress across top-level routine folders for Button 2
  static double calculateOverallRoutinesProgress({
    required List<NeuroItem> allItems,
    DateTime? referenceDate,
  }) {
    final folders = allItems
        .where((item) => item.type == NeuroItemType.routineFolder && item.parentId == null)
        .toList();
    if (folders.isEmpty) return 0.0;

    double sumProgress = 0.0;
    for (final folder in folders) {
      sumProgress += calculateRoutineFolderProgress(
        folder: folder,
        allItems: allItems,
        referenceDate: referenceDate,
      );
    }
    return (sumProgress / folders.length).clamp(0.0, 1.0);
  }

  /// Calculates comprehensive statistics for an item or folder node
  static Map<String, dynamic> calculateItemInsights({
    required NeuroItem item,
    required List<NeuroItem> allItems,
    int lookbackDays = 90,
  }) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final itemStart = item.startDate ?? item.createdAt;
    final startDay = DateTime(itemStart.year, itemStart.month, itemStart.day);
    final createdDay = DateTime(item.createdAt.year, item.createdAt.month, item.createdAt.day);
    final earliestValid = createdDay.isAfter(startDay) ? createdDay : startDay;
    final lookbackStart = today.subtract(Duration(days: lookbackDays - 1));
    final effectiveStart = lookbackStart.isAfter(earliestValid) ? lookbackStart : earliestValid;

    // For folder/vision types, compute tree-level stats
    if (item.type == NeuroItemType.vision || item.type == NeuroItemType.routineFolder) {
      final progress = item.type == NeuroItemType.vision
          ? calculateVisionNodeProgress(vision: item, allItems: allItems)
          : calculateRoutineFolderProgress(folder: item, allItems: allItems);
      final descendants = getDescendants(item.id, allItems);
      final leafTasks = descendants.where((i) => i.type == NeuroItemType.task || i.type == NeuroItemType.routine).toList();
      final totalItems = leafTasks.length;
      final completedItems = leafTasks.where((t) => t.isCompleted || t.completedDates.isNotEmpty).length;
      return {
        'completionRate': progress,
        'totalItems': totalItems,
        'completedItems': completedItems,
        'activeItems': totalItems - completedItems,
        'isFolder': true,
      };
    }

    int totalScheduled = 0;
    double totalCompleted = 0.0;
    int totalFailed = 0;
    int currentStreak = 0;
    int bestStreak = 0;
    int tempStreak = 0;
    final Map<int, int> dayOfWeekCompletions = {}; // 1=Mon..7=Sun

    DateTime cursor = effectiveStart;
    while (!cursor.isAfter(today)) {
      bool scheduled = false;
      if (item.type == NeuroItemType.routine) {
        scheduled = isItemScheduledOnDate(item, cursor);
      } else if (item.type == NeuroItemType.task && item.targetDate != null) {
        final td = DateTime(item.targetDate!.year, item.targetDate!.month, item.targetDate!.day);
        scheduled = td.isAtSameMomentAs(cursor);
      }

      if (scheduled) {
        totalScheduled++;
        final fraction = getItemCompletionFractionOnDate(item, cursor);
        if (fraction >= 1.0) {
          totalCompleted += 1.0;
          tempStreak++;
          if (tempStreak > bestStreak) bestStreak = tempStreak;
          dayOfWeekCompletions[cursor.weekday] = (dayOfWeekCompletions[cursor.weekday] ?? 0) + 1;
        } else if (fraction > 0) {
          totalCompleted += fraction;
        } else if (item.isFailedOnDate(cursor)) {
          totalFailed++;
          tempStreak = 0;
        } else {
          // Today or future — not yet failed
          tempStreak = 0;
        }
      }
      cursor = cursor.add(const Duration(days: 1));
    }
    currentStreak = tempStreak;

    final completionRate = totalScheduled > 0 ? (totalCompleted / totalScheduled) : 0.0;
    final successRate = (totalCompleted + totalFailed) > 0
        ? (totalCompleted / (totalCompleted + totalFailed))
        : 0.0;
    final totalDays = today.difference(effectiveStart).inDays + 1;
    final weeksCount = totalDays / 7.0;
    final avgPerWeek = weeksCount > 0 ? totalCompleted / weeksCount : 0.0;

    return {
      'completionRate': completionRate.clamp(0.0, 1.0),
      'totalScheduled': totalScheduled,
      'totalCompleted': totalCompleted,
      'totalFailed': totalFailed,
      'currentStreak': currentStreak,
      'bestStreak': bestStreak,
      'successRate': successRate.clamp(0.0, 1.0),
      'avgPerWeek': avgPerWeek,
      'consistencyScore': completionRate.clamp(0.0, 1.0),
      'dayOfWeekCompletions': dayOfWeekCompletions,
      'totalDays': totalDays,
      'isFolder': false,
    };
  }

  /// Computes comprehensive past, today, and upcoming schedule information for an item.
  static ItemScheduleInfo getItemScheduleInfo(NeuroItem item, [DateTime? referenceDate]) {
    final now = referenceDate ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // 1. TODAY STATUS
    bool isScheduledToday = false;
    if (item.type == NeuroItemType.routine) {
      if (isItemScheduledOnDate(item, today)) {
        isScheduledToday = true;
      } else if ((item.isPendingCarryover || item.isFlexibleCarryover) &&
          item.scheduleType != ScheduleType.everyday) {
        // Routine carryover check
        final startDay = DateTime(
          (item.startDate ?? item.createdAt).year,
          (item.startDate ?? item.createdAt).month,
          (item.startDate ?? item.createdAt).day,
        );
        if (!today.isBefore(startDay)) {
          DateTime? lastScheduled;
          for (var d = today.subtract(const Duration(days: 1));
              !d.isBefore(startDay);
              d = d.subtract(const Duration(days: 1))) {
            if (isItemScheduledOnDate(item, d)) {
              lastScheduled = d;
              break;
            }
          }
          if (lastScheduled != null) {
            bool completedInCycle = false;
            bool failedInCycle = false;
            for (var d = lastScheduled; d.isBefore(today); d = d.add(const Duration(days: 1))) {
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
            if (!failedInCycle && (!completedInCycle || item.isCompletedOnDate(today))) {
              isScheduledToday = true;
            }
          }
        }
      }
    } else if (item.type == NeuroItemType.task) {
      if (item.targetDate != null) {
        final td = DateTime(item.targetDate!.year, item.targetDate!.month, item.targetDate!.day);
        if (td.isAtSameMomentAs(today)) {
          isScheduledToday = true;
        } else if ((item.isPendingCarryover || item.isFlexibleCarryover) && !item.isCompleted && td.isBefore(today)) {
          bool hasFailedPrior = false;
          for (var d = td; d.isBefore(today); d = d.add(const Duration(days: 1))) {
            final dKey = DateFormat('yyyy-MM-dd').format(d);
            if (item.failedDates.contains(dKey)) {
              hasFailedPrior = true;
              break;
            }
          }
          if (!hasFailedPrior) {
            isScheduledToday = true;
          }
        } else if (item.isCompleted && item.completedAt != null) {
          final cDay = DateTime(item.completedAt!.year, item.completedAt!.month, item.completedAt!.day);
          if (cDay.isAtSameMomentAs(today)) {
            isScheduledToday = true;
          }
        }
      }
    }

    final bool isCompletedToday = item.isCompletedOnDate(today) ||
        (item.type == NeuroItemType.task && item.isCompleted && isScheduledToday);
    final bool isFailedToday = item.failedDates.contains(DateFormat('yyyy-MM-dd').format(today));
    final double todayFraction = getItemCompletionFractionOnDate(item, today);

    String todaySummary;
    if (isCompletedToday) {
      todaySummary = 'Completed';
    } else if (isFailedToday) {
      todaySummary = 'Failed';
    } else if (todayFraction > 0) {
      todaySummary = '${(todayFraction * 100).toInt()}% Done';
    } else if (isScheduledToday) {
      todaySummary = 'Due Today';
    } else {
      todaySummary = 'Not Scheduled';
    }

    // 2. PAST SCHEDULES STATUS
    int pastScheduledCount = 0;
    int pastCompletedCount = 0;
    int pastFailedCount = 0;
    bool hasPastSchedules = false;
    String pastSummary = 'No past schedule';

    if (item.type == NeuroItemType.task) {
      if (item.targetDate != null) {
        final td = DateTime(item.targetDate!.year, item.targetDate!.month, item.targetDate!.day);
        if (td.isBefore(today)) {
          hasPastSchedules = true;
          pastScheduledCount = 1;
          final done = item.isCompleted || item.isCompletedOnDate(td);
          final failed = item.isFailedOnDate(td);
          if (done) pastCompletedCount = 1;
          if (failed) pastFailedCount = 1;
          pastSummary = done ? 'Done (${DateFormat('MMM d').format(td)})' : (failed ? 'Failed' : 'Pending');
        }
      }
    } else if (item.type == NeuroItemType.routine) {
      final start = item.startDate ?? item.createdAt;
      final startDay = DateTime(start.year, start.month, start.day);
      final lookbackStart = today.subtract(const Duration(days: 60));
      final effectiveStart = lookbackStart.isAfter(startDay) ? lookbackStart : startDay;

      DateTime cursor = effectiveStart;
      while (cursor.isBefore(today)) {
        if (isItemScheduledOnDate(item, cursor)) {
          pastScheduledCount++;
          if (item.isCompletedOnDate(cursor)) {
            pastCompletedCount++;
          } else if (item.isFailedOnDate(cursor)) {
            pastFailedCount++;
          }
        }
        cursor = cursor.add(const Duration(days: 1));
      }

      if (pastScheduledCount > 0) {
        hasPastSchedules = true;
        pastSummary = '$pastCompletedCount/$pastScheduledCount done${pastFailedCount > 0 ? ' • $pastFailedCount failed' : ''}';
      }
    }

    // 3. UPCOMING SCHEDULES
    bool hasUpcoming = false;
    DateTime? nextDate;
    String upcomingSummary = 'No upcoming schedule';

    if (item.type == NeuroItemType.task) {
      if (item.targetDate != null) {
        final td = DateTime(item.targetDate!.year, item.targetDate!.month, item.targetDate!.day);
        if (td.isAfter(today)) {
          hasUpcoming = true;
          nextDate = td;
          upcomingSummary = _formatScheduleDiff(today, td);
        }
      }
    } else if (item.type == NeuroItemType.routine) {
      bool isEnded = false;
      if (item.endDate != null) {
        final endDay = DateTime(item.endDate!.year, item.endDate!.month, item.endDate!.day);
        if (today.isAfter(endDay)) {
          isEnded = true;
          upcomingSummary = 'Ended on ${DateFormat('MMM d, yyyy').format(endDay)}';
        }
      }

      if (!isEnded) {
        if (item.scheduleType == ScheduleType.everyday) {
          hasUpcoming = true;
          nextDate = today.add(const Duration(days: 1));
          upcomingSummary = 'Everyday (Tomorrow)';
        } else {
          // Search forward up to 365 days
          for (int i = 1; i <= 365; i++) {
            final fDate = today.add(Duration(days: i));
            if (item.endDate != null) {
              final endDay = DateTime(item.endDate!.year, item.endDate!.month, item.endDate!.day);
              if (fDate.isAfter(endDay)) break;
            }
            if (isItemScheduledOnDate(item, fDate)) {
              hasUpcoming = true;
              nextDate = fDate;
              upcomingSummary = _formatScheduleDiff(today, fDate);
              break;
            }
          }
        }
      }
    }

    return ItemScheduleInfo(
      hasPastSchedules: hasPastSchedules,
      pastScheduledCount: pastScheduledCount,
      pastCompletedCount: pastCompletedCount,
      pastFailedCount: pastFailedCount,
      pastSummary: pastSummary,
      isScheduledToday: isScheduledToday,
      isCompletedToday: isCompletedToday,
      isFailedToday: isFailedToday,
      todayCompletionFraction: todayFraction,
      todaySummary: todaySummary,
      hasUpcoming: hasUpcoming,
      nextScheduledDate: nextDate,
      upcomingSummary: upcomingSummary,
    );
  }

  static String _formatScheduleDiff(DateTime today, DateTime target) {
    final diffDays = target.difference(today).inDays;
    if (diffDays == 1) return 'Tomorrow';
    if (diffDays < 7) return '${DateFormat('EEEE').format(target)} (in $diffDays days)';
    return DateFormat('MMM d, yyyy').format(target);
  }

  /// Returns true if an item matches the specified [ScheduleFilterOption].
  static bool matchesScheduleFilter(
    NeuroItem item,
    ScheduleFilterOption filter, [
    DateTime? referenceDate,
  ]) {
    if (filter == ScheduleFilterOption.all) return true;
    final info = getItemScheduleInfo(item, referenceDate);
    switch (filter) {
      case ScheduleFilterOption.all:
        return true;
      case ScheduleFilterOption.past:
        return info.hasPastSchedules;
      case ScheduleFilterOption.today:
        return info.isScheduledToday;
      case ScheduleFilterOption.upcoming:
        return info.hasUpcoming;
    }
  }
}
