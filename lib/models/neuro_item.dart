import 'dart:convert';
import 'package:intl/intl.dart';

enum NeuroItemType {
  vision,          // Top-level Vision container
  goal,            // Goal under a vision
  routineFolder,   // Routine Folder Container (Button on Routine Track screen)
  routine,         // Habit / routine item (repetitive task)
  task,            // Single task
  list,            // Checklist / list container
}

extension NeuroItemTypeExtension on NeuroItemType {
  String get name {
    switch (this) {
      case NeuroItemType.vision:
        return 'Vision';
      case NeuroItemType.goal:
        return 'Goal';
      case NeuroItemType.routineFolder:
        return 'Routine Folder';
      case NeuroItemType.routine:
        return 'Routine';
      case NeuroItemType.task:
        return 'Task';
      case NeuroItemType.list:
        return 'List';
    }
  }

  static NeuroItemType fromString(String value) {
    return NeuroItemType.values.firstWhere(
      (e) => e.toString().split('.').last == value,
      orElse: () => NeuroItemType.task,
    );
  }
}

enum RoutineCategory { habit, repetitiveTask }
enum RoutineCompletionType { yesNo, numeric, timer, checklist }
enum ScheduleType { everyday, specificDaysOfWeek, specificDaysOfMonth, specificDaysOfYear, someDaysPerPeriod, repeatInterval }

class ChecklistItem {
  final String id;
  final String title;
  final bool isCompleted;

  ChecklistItem({
    required this.id,
    required this.title,
    this.isCompleted = false,
  });

  ChecklistItem copyWith({
    String? id,
    String? title,
    bool? isCompleted,
  }) {
    return ChecklistItem(
      id: id ?? this.id,
      title: title ?? this.title,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'isCompleted': isCompleted,
    };
  }

  factory ChecklistItem.fromMap(Map<String, dynamic> map) {
    return ChecklistItem(
      id: map['id'] as String,
      title: map['title'] as String,
      isCompleted: map['isCompleted'] as bool? ?? false,
    );
  }
}

class DailyCategory {
  final String id;
  final String name;
  final int? colorHex;
  final String? iconName;
  final int priority;

  DailyCategory({
    required this.id,
    required this.name,
    this.colorHex,
    this.iconName,
    this.priority = 50,
  });

  DailyCategory copyWith({
    String? id,
    String? name,
    int? colorHex,
    String? iconName,
    int? priority,
  }) {
    return DailyCategory(
      id: id ?? this.id,
      name: name ?? this.name,
      colorHex: colorHex ?? this.colorHex,
      iconName: iconName ?? this.iconName,
      priority: priority ?? this.priority,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'colorHex': colorHex,
    'iconName': iconName,
    'priority': priority,
  };

  factory DailyCategory.fromMap(Map<String, dynamic> map) => DailyCategory(
    id: map['id'] as String,
    name: map['name'] as String,
    colorHex: map['colorHex'] as int?,
    iconName: map['iconName'] as String?,
    priority: map['priority'] as int? ?? 50,
  );
}

/// Unified relational data model
class NeuroItem {
  final String id;
  final String title;
  final String? description;
  final NeuroItemType type;
  final String? parentId;        // Reference to parent container (Routine Folder or Vision)
  final String? rootVisionId;    // Pointer to top Vision container
  final bool isCompleted;
  final DateTime? completedAt;   // Timestamp written on completion
  final DateTime createdAt;
  final DateTime? targetDate;    // Specific date
  final String? targetTime;      // e.g. "14:30"
  final DateTime? startDate;     // Start date (default current date)
  final DateTime? endDate;       // Optional end date
  final bool hasReminder;
  final DateTime? reminderDateTime;
  final int priority;            // 1 (highest priority) to 100 (lowest priority)
  final bool isPendingCarryover; // Carryover task option
  final bool noVisionXpEnabled;  // Dataset Isolation Guard
  final int streakCount;         // Streak tracking for routines
  final String? targetFrequency; // e.g. 'daily', 'weekly'
  final int? colorHex;
  final String? category;
  final List<ChecklistItem> checklist;
  final List<String> completedDates; // Date strings ("YYYY-MM-DD") for date-scoped completion
  final List<String> failedDates;    // Date strings ("YYYY-MM-DD") for failed / incomplete status
  final List<String> unmarkedDates;  // Date strings ("YYYY-MM-DD") explicitly reset to unmarked by user
  final Map<String, double> dailyNumericValues; // Date-scoped numeric values ("YYYY-MM-DD" -> val)
  final Map<String, List<String>> dailyChecklistCompletions; // Date-scoped checklist completions ("YYYY-MM-DD" -> [itemId...])

  // Routine & Habit Specific Fields
  final RoutineCategory routineCategory;
  final RoutineCompletionType completionType;
  final double? targetNumericValue;
  final double currentNumericValue;
  final int? timerDurationSeconds;
  final ScheduleType scheduleType;
  final List<int> selectedDaysOfWeek;      // 1=Mon ... 7=Sun
  final List<String> selectedDaysOfMonth;  // "1", "15", "FIRST_DAY", "LAST_DAY"
  final List<String> selectedDaysOfYear;   // "02-14", "FIRST_DAY", "LAST_DAY"
  final int repeatIntervalDays;             // Repeat every X days (user input)
  final bool isFlexibleCarryover;           // Flexible option: shown each day until completed
  final bool successContributesToProgress;  // Toggle whether successes contribute to progress bar
  final bool failureContributesToProgress;  // Toggle whether failures/misses penalize progress bar
  final String? dailyCategoryId;            // Category in Daily Track

  bool get contributeToProgress => successContributesToProgress;

  NeuroItem({
    required this.id,
    required this.title,
    this.description,
    required this.type,
    this.parentId,
    this.rootVisionId,
    this.isCompleted = false,
    this.completedAt,
    DateTime? createdAt,
    this.targetDate,
    this.targetTime,
    this.startDate,
    this.endDate,
    this.hasReminder = false,
    this.reminderDateTime,
    this.priority = 50,
    this.isPendingCarryover = false,
    this.noVisionXpEnabled = false,
    this.streakCount = 0,
    this.targetFrequency,
    this.colorHex,
    this.category,
    this.checklist = const [],
    this.completedDates = const [],
    this.failedDates = const [],
    this.unmarkedDates = const [],
    this.dailyNumericValues = const {},
    this.dailyChecklistCompletions = const {},
    this.routineCategory = RoutineCategory.habit,
    this.completionType = RoutineCompletionType.yesNo,
    this.targetNumericValue,
    this.currentNumericValue = 0,
    this.timerDurationSeconds,
    this.scheduleType = ScheduleType.everyday,
    this.selectedDaysOfWeek = const [],
    this.selectedDaysOfMonth = const [],
    this.selectedDaysOfYear = const [],
    this.repeatIntervalDays = 1,
    this.isFlexibleCarryover = false,
    this.successContributesToProgress = true,
    this.failureContributesToProgress = false,
    this.dailyCategoryId,
    bool? contributeToProgress,
  })  : createdAt = createdAt ?? DateTime.now();

  /// Returns date-scoped numeric progress value (resets every day)
  double getNumericValueForDate(DateTime date) {
    final dateKey = DateFormat('yyyy-MM-dd').format(date);
    if (dailyNumericValues.containsKey(dateKey)) {
      return dailyNumericValues[dateKey]!;
    }
    final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
    if (dateKey == todayKey && currentNumericValue > 0 && dailyNumericValues.isEmpty) {
      return currentNumericValue;
    }
    return 0.0;
  }

  /// Returns the list of completed checklist item IDs for a specific date
  List<String> getChecklistCompletionsForDate(DateTime date) {
    final dateKey = DateFormat('yyyy-MM-dd').format(date);
    if (dailyChecklistCompletions.containsKey(dateKey)) {
      return dailyChecklistCompletions[dateKey]!;
    }

    // If carryover is enabled, carry forward previously completed sub-items in the current recurrence cycle
    if (isPendingCarryover || isFlexibleCarryover) {
      final queryDay = DateTime(date.year, date.month, date.day);

      DateTime cycleStart;
      if (type == NeuroItemType.routine && scheduleType != ScheduleType.everyday) {
        // If queryDay is itself a new scheduled recurrence day, it starts fresh
        if (_isScheduledOn(queryDay)) {
          return const [];
        }
        // Find the most recent scheduled date before queryDay
        DateTime? lastScheduled;
        final startBoundary = DateTime(
          (startDate ?? createdAt).year,
          (startDate ?? createdAt).month,
          (startDate ?? createdAt).day,
        );
        for (var d = queryDay.subtract(const Duration(days: 1));
            !d.isBefore(startBoundary);
            d = d.subtract(const Duration(days: 1))) {
          if (_isScheduledOn(d)) {
            lastScheduled = d;
            break;
          }
        }
        if (lastScheduled == null) return const [];
        cycleStart = lastScheduled;
      } else {
        // One-time task or flexible task: cycle starts on targetDate or createdAt
        final base = targetDate ?? startDate ?? createdAt;
        cycleStart = DateTime(base.year, base.month, base.day);
        if (queryDay.isBefore(cycleStart)) return const [];
      }

      // If the item was marked as failed on any day in the cycle prior to queryDay, do not carry forward
      for (var d = queryDay.subtract(const Duration(days: 1));
          !d.isBefore(cycleStart);
          d = d.subtract(const Duration(days: 1))) {
        final dKey = DateFormat('yyyy-MM-dd').format(d);
        if (failedDates.contains(dKey)) return const [];
      }

      // Search backwards from queryDay - 1 down to cycleStart for the latest recorded checklist completions
      for (var d = queryDay.subtract(const Duration(days: 1));
          !d.isBefore(cycleStart);
          d = d.subtract(const Duration(days: 1))) {
        final prevKey = DateFormat('yyyy-MM-dd').format(d);
        if (dailyChecklistCompletions.containsKey(prevKey)) {
          return dailyChecklistCompletions[prevKey]!;
        }
      }
    }

    return const [];
  }

  /// Checks if a specific checklist sub-item is completed on the given date
  bool isChecklistItemCompletedOnDate(String itemId, DateTime date) {
    return getChecklistCompletionsForDate(date).contains(itemId);
  }

  /// Returns the count of completed checklist items for a date
  int getChecklistCompletedCountForDate(DateTime date) {
    return getChecklistCompletionsForDate(date).length;
  }

  /// Check if item is completed on a specific DateTime
  bool isCompletedOnDate(DateTime date) {
    final dateKey = DateFormat('yyyy-MM-dd').format(date);
    if (unmarkedDates.contains(dateKey)) return false;
    if (completedDates.contains(dateKey)) return true;
    if (failedDates.contains(dateKey)) return false;
    if (isCompleted && completedAt != null) {
      final cDay = DateTime(completedAt!.year, completedAt!.month, completedAt!.day);
      final qDay = DateTime(date.year, date.month, date.day);
      if (cDay.isAtSameMomentAs(qDay)) return true;
    }
    if (type == NeuroItemType.task && isCompleted && targetDate == null) {
      return true;
    }
    return false;
  }

  /// Check if item is marked failed or automatically incomplete on a past DateTime
  bool isFailedOnDate(DateTime date) {
    final dateKey = DateFormat('yyyy-MM-dd').format(date);
    if (unmarkedDates.contains(dateKey)) return false;
    if (failedDates.contains(dateKey)) return true;

    final queryDay = DateTime(date.year, date.month, date.day);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Automatic incomplete marking if target date is in the past and not completed
    if (type == NeuroItemType.task && targetDate != null) {
      final taskDay = DateTime(targetDate!.year, targetDate!.month, targetDate!.day);
      if (taskDay.isAtSameMomentAs(queryDay) && queryDay.isBefore(today) && !isCompletedOnDate(date)) {
        if (isPendingCarryover || isFlexibleCarryover) {
          return false; // Items with carry forwarding enabled are not auto-marked as failed
        }
        return true;
      }
    } else if (type == NeuroItemType.routine) {
      if (startDate != null) {
        final startDay = DateTime(startDate!.year, startDate!.month, startDate!.day);
        if (queryDay.isBefore(startDay)) return false;
      }

      if (queryDay.isBefore(today) && !isCompletedOnDate(date)) {
        // Carry-forward + repeat: auto-fail when the next scheduled day arrives
        // without the user having completed it
        if ((isPendingCarryover || isFlexibleCarryover) && scheduleType != ScheduleType.everyday) {
          // Check if a newer scheduled date exists between queryDay+1 and today (inclusive)
          // If so, the queryDay instance is auto-failed because the next repetition arrived
          for (var d = queryDay.add(const Duration(days: 1));
              !d.isAfter(today);
              d = d.add(const Duration(days: 1))) {
            if (_isScheduledOn(d)) {
              return true; // Next repetition day reached; auto-fail the old carry-forward
            }
          }
          // No next scheduled date yet — still carrying forward, not failed
          return false;
        }
        return true;
      }
    }
    return false;
  }

  /// Private schedule-check (mirrors AggregationEngine.isItemScheduledOnDate)
  bool _isScheduledOn(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    if (startDate != null) {
      final startDay = DateTime(startDate!.year, startDate!.month, startDate!.day);
      if (d.isBefore(startDay)) return false;
    }

    switch (scheduleType) {
      case ScheduleType.everyday:
        return true;
      case ScheduleType.specificDaysOfWeek:
        return selectedDaysOfWeek.contains(d.weekday);
      case ScheduleType.specificDaysOfMonth:
        final dayStr = d.day.toString();
        if (selectedDaysOfMonth.contains(dayStr)) return true;
        if (d.day == 1 && selectedDaysOfMonth.contains('FIRST_DAY')) return true;
        final lastDay = DateTime(d.year, d.month + 1, 0).day;
        if (d.day == lastDay && selectedDaysOfMonth.contains('LAST_DAY')) return true;
        return false;
      case ScheduleType.specificDaysOfYear:
        final mds = '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        if (selectedDaysOfYear.contains(mds)) return true;
        if (d.month == 1 && d.day == 1 && selectedDaysOfYear.contains('FIRST_DAY')) return true;
        if (d.month == 12 && d.day == 31 && selectedDaysOfYear.contains('LAST_DAY')) return true;
        return false;
      case ScheduleType.someDaysPerPeriod:
        return true;
      case ScheduleType.repeatInterval:
        final diff = d.difference(DateTime(createdAt.year, createdAt.month, createdAt.day)).inDays;
        return diff >= 0 && (diff % (repeatIntervalDays > 0 ? repeatIntervalDays : 1)) == 0;
    }
  }

  NeuroItem copyWith({
    String? id,
    String? title,
    String? description,
    NeuroItemType? type,
    String? parentId,
    String? rootVisionId,
    bool? isCompleted,
    DateTime? completedAt,
    bool clearCompletedAt = false,
    DateTime? createdAt,
    DateTime? targetDate,
    bool clearTargetDate = false,
    String? targetTime,
    bool clearTargetTime = false,
    DateTime? startDate,
    DateTime? endDate,
    bool clearEndDate = false,
    bool? hasReminder,
    DateTime? reminderDateTime,
    int? priority,
    bool? isPendingCarryover,
    bool? noVisionXpEnabled,
    int? streakCount,
    String? targetFrequency,
    int? colorHex,
    String? category,
    List<ChecklistItem>? checklist,
    List<String>? completedDates,
    List<String>? failedDates,
    List<String>? unmarkedDates,
    Map<String, double>? dailyNumericValues,
    Map<String, List<String>>? dailyChecklistCompletions,
    RoutineCategory? routineCategory,
    RoutineCompletionType? completionType,
    double? targetNumericValue,
    double? currentNumericValue,
    int? timerDurationSeconds,
    ScheduleType? scheduleType,
    List<int>? selectedDaysOfWeek,
    List<String>? selectedDaysOfMonth,
    List<String>? selectedDaysOfYear,
    int? repeatIntervalDays,
    bool? isFlexibleCarryover,
    bool? contributeToProgress,
    bool? successContributesToProgress,
    bool? failureContributesToProgress,
    String? dailyCategoryId,
    bool clearDailyCategoryId = false,
    bool clearParentId = false,
  }) {
    return NeuroItem(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      type: type ?? this.type,
      parentId: clearParentId ? null : (parentId ?? this.parentId),
      rootVisionId: rootVisionId ?? this.rootVisionId,
      isCompleted: isCompleted ?? this.isCompleted,
      completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
      createdAt: createdAt ?? this.createdAt,
      targetDate: clearTargetDate ? null : (targetDate ?? this.targetDate),
      targetTime: clearTargetTime ? null : (targetTime ?? this.targetTime),
      startDate: startDate ?? this.startDate,
      endDate: clearEndDate ? null : (endDate ?? this.endDate),
      hasReminder: hasReminder ?? this.hasReminder,
      reminderDateTime: reminderDateTime ?? this.reminderDateTime,
      priority: priority ?? this.priority,
      isPendingCarryover: isPendingCarryover ?? this.isPendingCarryover,
      noVisionXpEnabled: noVisionXpEnabled ?? this.noVisionXpEnabled,
      streakCount: streakCount ?? this.streakCount,
      targetFrequency: targetFrequency ?? this.targetFrequency,
      colorHex: colorHex ?? this.colorHex,
      category: category ?? this.category,
      checklist: checklist ?? this.checklist,
      completedDates: completedDates ?? this.completedDates,
      failedDates: failedDates ?? this.failedDates,
      unmarkedDates: unmarkedDates ?? this.unmarkedDates,
      dailyNumericValues: dailyNumericValues ?? this.dailyNumericValues,
      dailyChecklistCompletions: dailyChecklistCompletions ?? this.dailyChecklistCompletions,
      routineCategory: routineCategory ?? this.routineCategory,
      completionType: completionType ?? this.completionType,
      targetNumericValue: targetNumericValue ?? this.targetNumericValue,
      currentNumericValue: currentNumericValue ?? this.currentNumericValue,
      timerDurationSeconds: timerDurationSeconds ?? this.timerDurationSeconds,
      scheduleType: scheduleType ?? this.scheduleType,
      selectedDaysOfWeek: selectedDaysOfWeek ?? this.selectedDaysOfWeek,
      selectedDaysOfMonth: selectedDaysOfMonth ?? this.selectedDaysOfMonth,
      selectedDaysOfYear: selectedDaysOfYear ?? this.selectedDaysOfYear,
      repeatIntervalDays: repeatIntervalDays ?? this.repeatIntervalDays,
      isFlexibleCarryover: isFlexibleCarryover ?? this.isFlexibleCarryover,
      successContributesToProgress: successContributesToProgress ?? contributeToProgress ?? this.successContributesToProgress,
      failureContributesToProgress: failureContributesToProgress ?? this.failureContributesToProgress,
      dailyCategoryId: clearDailyCategoryId ? null : (dailyCategoryId ?? this.dailyCategoryId),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'type': type.toString().split('.').last,
      'parentId': parentId,
      'rootVisionId': rootVisionId,
      'isCompleted': isCompleted,
      'completedAt': completedAt?.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'targetDate': targetDate?.toIso8601String(),
      'targetTime': targetTime,
      'startDate': startDate?.toIso8601String(),
      'endDate': endDate?.toIso8601String(),
      'hasReminder': hasReminder,
      'reminderDateTime': reminderDateTime?.toIso8601String(),
      'priority': priority,
      'isPendingCarryover': isPendingCarryover,
      'noVisionXpEnabled': noVisionXpEnabled,
      'streakCount': streakCount,
      'targetFrequency': targetFrequency,
      'colorHex': colorHex,
      'category': category,
      'checklist': checklist.map((e) => e.toMap()).toList(),
      'completedDates': completedDates,
      'failedDates': failedDates,
      'unmarkedDates': unmarkedDates,
      'dailyNumericValues': dailyNumericValues,
      'dailyChecklistCompletions': dailyChecklistCompletions.map((k, v) => MapEntry(k, v)),
      'routineCategory': routineCategory.toString().split('.').last,
      'completionType': completionType.toString().split('.').last,
      'targetNumericValue': targetNumericValue,
      'currentNumericValue': currentNumericValue,
      'timerDurationSeconds': timerDurationSeconds,
      'scheduleType': scheduleType.toString().split('.').last,
      'selectedDaysOfWeek': selectedDaysOfWeek,
      'selectedDaysOfMonth': selectedDaysOfMonth,
      'selectedDaysOfYear': selectedDaysOfYear,
      'repeatIntervalDays': repeatIntervalDays,
      'isFlexibleCarryover': isFlexibleCarryover,
      'contributeToProgress': successContributesToProgress,
      'successContributesToProgress': successContributesToProgress,
      'failureContributesToProgress': failureContributesToProgress,
      'dailyCategoryId': dailyCategoryId,
    };
  }

  factory NeuroItem.fromMap(Map<String, dynamic> map) {
    return NeuroItem(
      id: map['id'] as String,
      title: map['title'] as String,
      description: map['description'] as String?,
      type: NeuroItemTypeExtension.fromString(map['type'] as String),
      parentId: map['parentId'] as String?,
      rootVisionId: map['rootVisionId'] as String?,
      isCompleted: map['isCompleted'] as bool? ?? false,
      completedAt: map['completedAt'] != null
          ? DateTime.parse(map['completedAt'] as String)
          : null,
      createdAt: DateTime.parse(map['createdAt'] as String),
      targetDate: map['targetDate'] != null
          ? DateTime.parse(map['targetDate'] as String)
          : null,
      targetTime: map['targetTime'] as String?,
      startDate: map['startDate'] != null
          ? DateTime.parse(map['startDate'] as String)
          : null,
      endDate: map['endDate'] != null
          ? DateTime.parse(map['endDate'] as String)
          : null,
      hasReminder: map['hasReminder'] as bool? ?? false,
      reminderDateTime: map['reminderDateTime'] != null
          ? DateTime.parse(map['reminderDateTime'] as String)
          : null,
      priority: map['priority'] as int? ?? 50,
      isPendingCarryover: map['isPendingCarryover'] as bool? ?? false,
      noVisionXpEnabled: map['noVisionXpEnabled'] as bool? ?? false,
      streakCount: map['streakCount'] as int? ?? 0,
      targetFrequency: map['targetFrequency'] as String?,
      colorHex: map['colorHex'] as int?,
      category: map['category'] as String?,
      checklist: map['checklist'] != null
          ? (map['checklist'] as List)
              .map((e) => ChecklistItem.fromMap(Map<String, dynamic>.from(e as Map)))
              .toList()
          : const [],
      completedDates: map['completedDates'] != null
          ? List<String>.from(map['completedDates'] as List)
          : const [],
      failedDates: map['failedDates'] != null
          ? List<String>.from(map['failedDates'] as List)
          : const [],
      unmarkedDates: map['unmarkedDates'] != null
          ? List<String>.from(map['unmarkedDates'] as List)
          : const [],
      dailyNumericValues: map['dailyNumericValues'] != null
          ? Map<String, double>.from(
              (map['dailyNumericValues'] as Map).map(
                (k, v) => MapEntry(k.toString(), (v as num).toDouble()),
              ),
            )
          : const {},
      dailyChecklistCompletions: map['dailyChecklistCompletions'] != null
          ? (map['dailyChecklistCompletions'] as Map).map(
              (k, v) => MapEntry(k.toString(), List<String>.from(v as List)),
            )
          : const {},
      routineCategory: RoutineCategory.values.firstWhere(
        (e) => e.toString().split('.').last == map['routineCategory'],
        orElse: () => RoutineCategory.habit,
      ),
      completionType: RoutineCompletionType.values.firstWhere(
        (e) => e.toString().split('.').last == map['completionType'],
        orElse: () => RoutineCompletionType.yesNo,
      ),
      targetNumericValue: (map['targetNumericValue'] as num?)?.toDouble(),
      currentNumericValue: (map['currentNumericValue'] as num?)?.toDouble() ?? 0,
      timerDurationSeconds: map['timerDurationSeconds'] as int?,
      scheduleType: ScheduleType.values.firstWhere(
        (e) => e.toString().split('.').last == map['scheduleType'],
        orElse: () => ScheduleType.everyday,
      ),
      selectedDaysOfWeek: map['selectedDaysOfWeek'] != null
          ? List<int>.from(map['selectedDaysOfWeek'] as List)
          : const [],
      selectedDaysOfMonth: map['selectedDaysOfMonth'] != null
          ? List<String>.from(map['selectedDaysOfMonth'] as List)
          : const [],
      selectedDaysOfYear: map['selectedDaysOfYear'] != null
          ? List<String>.from(map['selectedDaysOfYear'] as List)
          : const [],
      repeatIntervalDays: map['repeatIntervalDays'] as int? ?? 1,
      isFlexibleCarryover: map['isFlexibleCarryover'] as bool? ?? false,
      successContributesToProgress: (map['successContributesToProgress'] ?? map['contributeToProgress']) as bool? ?? true,
      failureContributesToProgress: map['failureContributesToProgress'] as bool? ?? false,
      dailyCategoryId: map['dailyCategoryId'] as String?,
    );
  }

  String toJson() => json.encode(toMap());
  factory NeuroItem.fromJson(String source) => NeuroItem.fromMap(json.decode(source) as Map<String, dynamic>);
}
