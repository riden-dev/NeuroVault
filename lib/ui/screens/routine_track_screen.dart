import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;
import '../../models/neuro_item.dart';
import '../../providers/neuro_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/compile_folder_dialog.dart';
import '../widgets/unified_options_bottom_sheet.dart';
import '../widgets/unified_stepper_dialog.dart';
import '../../services/aggregation_engine.dart';
import '../widgets/item_insights_bottom_sheet.dart';
import 'routine_folder_tasks_screen.dart';

class RoutineTrackScreen extends ConsumerStatefulWidget {
  const RoutineTrackScreen({super.key});

  @override
  ConsumerState<RoutineTrackScreen> createState() => _RoutineTrackScreenState();
}

class _RoutineTrackScreenState extends ConsumerState<RoutineTrackScreen> {
  bool _showAllRoutines = false;
  ScheduleFilterOption _scheduleFilter = ScheduleFilterOption.all;
  ProgressTimeRange _selectedTimeRange = ProgressTimeRange.sevenDays;
  DateTimeRange? _customDateRange;

  String _getTimeRangeLabel() {
    if (_selectedTimeRange == ProgressTimeRange.custom && _customDateRange != null) {
      return 'Custom (${_customDateRange!.duration.inDays + 1}d)';
    }
    return _selectedTimeRange.label;
  }

  @override
  Widget build(BuildContext context) {
    final allItems = ref.watch(neuroItemsProvider);
    final folders = ref.watch(routineFoldersProvider);
    final notifier = ref.read(neuroItemsProvider.notifier);

    final allRoutineItems = allItems.where((item) =>
        item.type == NeuroItemType.routine ||
        (item.type == NeuroItemType.task && item.parentId != null &&
            allItems.any((p) => p.id == item.parentId && p.type == NeuroItemType.routineFolder))).toList();
    allRoutineItems.sort((a, b) => a.priority.compareTo(b.priority));

    final filteredRoutineItems = allRoutineItems.where((task) {
      if (_scheduleFilter == ScheduleFilterOption.all) return true;
      final info = AggregationEngine.getItemScheduleInfo(task);
      switch (_scheduleFilter) {
        case ScheduleFilterOption.all:
          return true;
        case ScheduleFilterOption.past:
          return info.hasPastSchedules;
        case ScheduleFilterOption.today:
          return info.isScheduledToday;
        case ScheduleFilterOption.upcoming:
          return info.hasUpcoming;
      }
    }).toList();

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Routines'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Mode Switcher: Folders vs All Routines
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceColor,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF334155), width: 0.8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => setState(() => _showAllRoutines = false),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            color: !_showAllRoutines
                                ? AppTheme.routineAccent.withValues(alpha: 0.25)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Folders (${folders.length})',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: !_showAllRoutines ? FontWeight.bold : FontWeight.normal,
                              color: !_showAllRoutines ? Colors.white : AppTheme.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: InkWell(
                        onTap: () => setState(() => _showAllRoutines = true),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            color: _showAllRoutines
                                ? AppTheme.routineAccent.withValues(alpha: 0.25)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'All Routines (${allRoutineItems.length})',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: _showAllRoutines ? FontWeight.bold : FontWeight.normal,
                              color: _showAllRoutines ? Colors.white : AppTheme.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              if (!_showAllRoutines) ...[
                const Text(
                  'Routine Folders',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Drag & drop to prioritize routine categories. Hold for options.',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 12),

                // Time Range Selector Pill Bar for Routine Folders
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: ProgressTimeRange.values.map((range) {
                      final isSelected = range == _selectedTimeRange;
                      final chipLabel = range == ProgressTimeRange.custom && _customDateRange != null
                          ? 'Custom (${_customDateRange!.duration.inDays + 1}d)'
                          : range.label;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: ChoiceChip(
                          label: Text(
                            chipLabel,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              color: isSelected ? AppTheme.routineAccent : AppTheme.textSecondary,
                            ),
                          ),
                          selected: isSelected,
                          selectedColor: AppTheme.routineAccent.withValues(alpha: 0.18),
                          backgroundColor: AppTheme.surfaceColor,
                          side: BorderSide(
                            color: isSelected
                                ? AppTheme.routineAccent
                                : AppTheme.textSecondary.withValues(alpha: 0.2),
                            width: isSelected ? 1.5 : 1.0,
                          ),
                          onSelected: (selected) async {
                            if (range == ProgressTimeRange.custom) {
                              final now = DateTime.now();
                              final picked = await showDateRangePicker(
                                context: context,
                                firstDate: DateTime(2020),
                                lastDate: now.add(const Duration(days: 365)),
                                initialDateRange: _customDateRange ?? DateTimeRange(
                                  start: now.subtract(const Duration(days: 13)),
                                  end: now,
                                ),
                                builder: (context, child) {
                                  return Theme(
                                    data: AppTheme.darkTheme.copyWith(
                                      colorScheme: AppTheme.darkTheme.colorScheme.copyWith(
                                        primary: AppTheme.routineAccent,
                                        onPrimary: Colors.black,
                                        surface: AppTheme.surfaceColor,
                                        onSurface: AppTheme.textPrimary,
                                      ),
                                    ),
                                    child: child!,
                                  );
                                },
                              );
                              if (picked != null) {
                                setState(() {
                                  _customDateRange = picked;
                                  _selectedTimeRange = ProgressTimeRange.custom;
                                });
                              }
                            } else {
                              if (selected) {
                                setState(() {
                                  _selectedTimeRange = range;
                                });
                              }
                            }
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 16),
              ] else ...[
                // Schedule Filter Pill Bar for All Routines
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: ScheduleFilterOption.values.map((option) {
                      final isSelected = _scheduleFilter == option;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              _scheduleFilter = option;
                            });
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppTheme.routineAccent.withValues(alpha: 0.2)
                                  : AppTheme.surfaceColor,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected
                                    ? AppTheme.routineAccent
                                    : const Color(0xFF334155),
                                width: 1,
                              ),
                            ),
                            child: Text(
                              option.label,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                color: isSelected ? Colors.white : AppTheme.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              Expanded(
                child: _showAllRoutines
                    ? _buildAllRoutinesView(filteredRoutineItems, allItems, notifier)
                    : (folders.isEmpty
                    ? Center(
                        child: Text(
                          'No routine folders created yet.\nTap + to create your first routine category button!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppTheme.textSecondary),
                        ),
                      )
                    : ReorderableListView.builder(
                        itemCount: folders.length,
                        onReorder: (oldIndex, newIndex) {
                          if (newIndex > oldIndex) newIndex -= 1;
                          final item = folders.removeAt(oldIndex);
                          folders.insert(newIndex, item);
                          notifier.reorderTasks(folders);
                        },
                        itemBuilder: (context, index) {
                          final folder = folders[index];
                          final isCustom = _selectedTimeRange == ProgressTimeRange.custom && _customDateRange != null;
                          final today = isCustom ? _customDateRange!.end : DateTime.now();
                          final startDate = folder.startDate ?? folder.createdAt;
                          final calculatedDays = isCustom
                              ? (_customDateRange!.duration.inDays + 1)
                              : (_selectedTimeRange.days ??
                                  math.max(7, DateTime(today.year, today.month, today.day)
                                      .difference(DateTime(startDate.year, startDate.month, startDate.day))
                                      .inDays + 1));

                          final progress = AggregationEngine.calculateRoutineFolderProgress(
                            folder: folder,
                            allItems: allItems,
                            days: calculatedDays,
                            referenceDate: isCustom ? _customDateRange!.end : null,
                          );

                          final series = AggregationEngine.computeRollingSeries(
                            rootVisionId: folder.id,
                            allItems: allItems,
                            days: calculatedDays,
                            referenceDate: isCustom ? _customDateRange!.end : null,
                          );

                          return Container(
                            key: ValueKey(folder.id),
                            margin: const EdgeInsets.only(bottom: 16.0),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          RoutineFolderTasksScreen(folder: folder),
                                    ),
                                  );
                                },
                                onLongPress: () {
                                  UnifiedOptionsBottomSheet.show(
                                    context: context,
                                    title: folder.title,
                                    subtitle: 'Routine Folder Button',
                                    onEdit: () {
                                      showDialog(
                                        context: context,
                                        builder: (context) => UnifiedStepperDialog(
                                          title: 'Edit Routine Folder',
                                          isFolder: true,
                                          existingItem: folder,
                                          onSave: (updated) => notifier.updateItem(updated),
                                        ),
                                      );
                                    },
                                    onDelete: () => notifier.deleteItem(folder.id),
                                    onCompile: () {
                                      CompileFolderHelper.showCompileDialog(
                                        context: context,
                                        sourceItem: folder,
                                        availableFolders: folders,
                                        allItems: allItems,
                                        notifier: notifier,
                                      );
                                    },
                                  );
                                },
                                borderRadius: BorderRadius.circular(20.0),
                                child: Ink(
                                  padding: const EdgeInsets.all(20.0),
                                  decoration: BoxDecoration(
                                    color: AppTheme.surfaceColor,
                                    borderRadius: BorderRadius.circular(20.0),
                                    border: Border.all(
                                      color: AppTheme.routineAccent.withValues(alpha: 0.3),
                                      width: 1.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppTheme.routineAccent.withValues(alpha: 0.05),
                                        blurRadius: 16,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(14.0),
                                            decoration: BoxDecoration(
                                              color: AppTheme.routineAccent
                                                  .withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(16.0),
                                            ),
                                            child: const Icon(
                                              Icons.folder_special_rounded,
                                              color: AppTheme.routineAccent,
                                              size: 28,
                                            ),
                                          ),
                                          const SizedBox(width: 14),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(
                                                          horizontal: 6, vertical: 2),
                                                      margin: const EdgeInsets.only(right: 8),
                                                      decoration: BoxDecoration(
                                                        color: _getPriorityColor(folder.priority)
                                                            .withValues(alpha: 0.15),
                                                        borderRadius: BorderRadius.circular(6),
                                                      ),
                                                      child: Text(
                                                        'P${folder.priority}',
                                                        style: TextStyle(
                                                          fontSize: 10,
                                                          fontWeight: FontWeight.bold,
                                                          color: _getPriorityColor(folder.priority),
                                                        ),
                                                      ),
                                                    ),
                                                    Expanded(
                                                      child: Text(
                                                        folder.title,
                                                        style: const TextStyle(
                                                          fontSize: 17,
                                                          fontWeight: FontWeight.bold,
                                                          color: AppTheme.textPrimary,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  'Start: ${DateFormat('MMM d, yyyy').format(folder.startDate ?? folder.createdAt)}${folder.endDate != null ? ' • End: ${DateFormat('MMM d, yyyy').format(folder.endDate!)}' : ''}',
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    color: AppTheme.textSecondary,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const Icon(
                                            Icons.drag_indicator_rounded,
                                            color: AppTheme.textSecondary,
                                            size: 20,
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 16),

                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            'Routine Completion (${_getTimeRangeLabel()})',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: AppTheme.textSecondary,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          Text(
                                            '${(progress * 100).toInt()}%',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: progress < 0 ? Colors.redAccent : AppTheme.routineAccent,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(6.0),
                                        child: LinearProgressIndicator(
                                          value: progress.clamp(0.0, 1.0),
                                          minHeight: 6,
                                          backgroundColor: AppTheme.backgroundColor,
                                          valueColor: AlwaysStoppedAnimation<Color>(
                                            progress < 0 ? Colors.redAccent : AppTheme.routineAccent,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 12),

                                      // Sparkline Graph
                                      Builder(
                                        builder: (context) {
                                          final minVal = series.isEmpty ? 0.0 : series.reduce(math.min);
                                          final maxVal = series.isEmpty ? 1.0 : series.reduce(math.max);
                                          final hasNegative = minVal < 0;
                                          final minY = hasNegative ? (minVal - 0.5) : 0.0;
                                          final maxY = math.max(1.0, maxVal + 0.5);

                                          return Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              if (hasNegative)
                                                Padding(
                                                  padding: const EdgeInsets.only(bottom: 4.0),
                                                  child: Row(
                                                    children: [
                                                      const Icon(Icons.trending_down_rounded, size: 13, color: Colors.redAccent),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        'Negative dip: min ${minVal.toInt()}',
                                                        style: const TextStyle(fontSize: 10, color: Colors.redAccent, fontWeight: FontWeight.bold),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              SizedBox(
                                                height: 50,
                                                child: LineChart(
                                                  LineChartData(
                                                    minY: minY,
                                                    maxY: maxY,
                                                    gridData: FlGridData(
                                                      show: hasNegative,
                                                      drawVerticalLine: false,
                                                      drawHorizontalLine: true,
                                                      checkToShowHorizontalLine: (value) => (value - 0.0).abs() < 0.01,
                                                      getDrawingHorizontalLine: (value) => const FlLine(
                                                        color: Color(0xFF64748B),
                                                        strokeWidth: 1.0,
                                                        dashArray: [4, 4],
                                                      ),
                                                    ),
                                                    titlesData: const FlTitlesData(show: false),
                                                    borderData: FlBorderData(show: false),
                                                    lineBarsData: [
                                                      LineChartBarData(
                                                        spots: List.generate(
                                                          series.length,
                                                          (i) => FlSpot(i.toDouble(), series[i]),
                                                        ),
                                                        isCurved: true,
                                                        color: (hasNegative && series.isNotEmpty && series.last < 0
                                                            ? Colors.redAccent
                                                            : AppTheme.routineAccent),
                                                        barWidth: 2.5,
                                                        isStrokeCapRound: true,
                                                        dotData: const FlDotData(show: false),
                                                        belowBarData: BarAreaData(
                                                          show: true,
                                                          cutOffY: 0.0,
                                                          applyCutOffY: hasNegative,
                                                          color: AppTheme.routineAccent.withValues(alpha: 0.12),
                                                        ),
                                                        aboveBarData: BarAreaData(
                                                          show: hasNegative,
                                                          cutOffY: 0.0,
                                                          applyCutOffY: true,
                                                          color: Colors.redAccent.withValues(alpha: 0.12),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ],
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      )),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.routineAccent,
        icon: const Icon(Icons.add, color: AppTheme.backgroundColor),
        label: Text(
          _showAllRoutines ? 'Add Routine / Task' : 'New Routine Folder',
          style: const TextStyle(color: AppTheme.backgroundColor, fontWeight: FontWeight.bold),
        ),
        onPressed: () {
          showDialog(
            context: context,
            builder: (context) => UnifiedStepperDialog(
              title: _showAllRoutines ? 'Add Routine / Task' : 'Create Routine Folder',
              isFolder: !_showAllRoutines,
              onSave: (item) {
                notifier.addItem(
                  title: item.title,
                  description: item.description,
                  type: _showAllRoutines ? item.type : NeuroItemType.routineFolder,
                  parentId: item.parentId,
                  startDate: item.startDate,
                  endDate: item.endDate,
                  priority: item.priority,
                  scheduleType: item.scheduleType,
                  selectedDaysOfWeek: item.selectedDaysOfWeek,
                  selectedDaysOfMonth: item.selectedDaysOfMonth,
                  selectedDaysOfYear: item.selectedDaysOfYear,
                  repeatIntervalDays: item.repeatIntervalDays,
                  completionType: item.completionType,
                  targetNumericValue: item.targetNumericValue,
                  timerDurationSeconds: item.timerDurationSeconds,
                  checklist: item.checklist,
                  isFlexibleCarryover: item.isFlexibleCarryover,
                  isPendingCarryover: item.isPendingCarryover,
                  successContributesToProgress: item.successContributesToProgress,
                  failureContributesToProgress: item.failureContributesToProgress,
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildAllRoutinesView(List<NeuroItem> items, List<NeuroItem> allItems, NeuroItemsNotifier notifier) {
    if (items.isEmpty) {
      return Center(
        child: Text(
          'No routine items match the "${_scheduleFilter.label}" schedule filter.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
      );
    }

    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        final task = items[index];
        final sched = AggregationEngine.getItemScheduleInfo(task);
        return GestureDetector(
          onLongPress: () {
            UnifiedOptionsBottomSheet.show(
              context: context,
              title: task.title,
              subtitle: task.type == NeuroItemType.task
                  ? 'One-Time Task'
                  : (task.routineCategory == RoutineCategory.habit ? 'Habit' : 'Repetitive Task'),
              onEdit: () {
                showDialog(
                  context: context,
                  builder: (context) => UnifiedStepperDialog(
                    title: 'Edit Item',
                    isFolder: false,
                    existingItem: task,
                    onSave: (updated) => notifier.updateItem(updated),
                  ),
                );
              },
              onDelete: () => notifier.deleteItem(task.id),
              onInsights: () => ItemInsightsBottomSheet.show(
                context,
                item: task,
                allItems: allItems,
              ),
            );
          },
          child: Card(
            margin: const EdgeInsets.only(bottom: 12.0),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: (task.type == NeuroItemType.task ? AppTheme.secondaryAccent : AppTheme.routineAccent).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          task.type == NeuroItemType.task
                              ? 'One-Time Task'
                              : (task.routineCategory == RoutineCategory.habit ? 'Habit' : 'Repetitive Task'),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: task.type == NeuroItemType.task ? AppTheme.secondaryAccent : AppTheme.routineAccent,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          task.title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),
                      Text(
                        'P${task.priority}',
                        style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                  if (task.description != null && task.description!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      task.description!,
                      style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        task.type == NeuroItemType.task ? Icons.calendar_today_rounded : Icons.repeat_rounded,
                        size: 14,
                        color: AppTheme.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        task.type == NeuroItemType.task
                            ? (task.targetDate != null
                                ? 'Due: ${DateFormat('MMM d, yyyy').format(task.targetDate!)}${(task.isPendingCarryover || task.isFlexibleCarryover) ? ' • CO' : ''}'
                                : 'Flexible (No Date)')
                            : 'Schedule: ${_getScheduleText(task)}',
                        style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                      ),
                      if (task.type == NeuroItemType.routine && task.endDate != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          '• End: ${DateFormat('MMM d').format(task.endDate!)}',
                          style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                        ),
                      ],
                    ],
                  ),

                  // SCHEDULE STATUS BADGES (Past, Today, Upcoming)
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppTheme.backgroundColor.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF334155), width: 0.8),
                    ),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (sched.isScheduledToday)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: sched.isCompletedToday
                                  ? Colors.green.withValues(alpha: 0.15)
                                  : (sched.isFailedToday
                                      ? Colors.redAccent.withValues(alpha: 0.15)
                                      : (sched.todayCompletionFraction > 0
                                          ? const Color(0xFFFACC15).withValues(alpha: 0.18)
                                          : AppTheme.routineAccent.withValues(alpha: 0.15))),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  sched.isCompletedToday
                                  ? Icons.check_circle_rounded
                                  : (sched.isFailedToday ? Icons.cancel_rounded : Icons.today_rounded),
                                  size: 11,
                                  color: sched.isCompletedToday
                                      ? Colors.green
                                      : (sched.isFailedToday
                                          ? Colors.redAccent
                                          : (sched.todayCompletionFraction > 0
                                              ? const Color(0xFFFACC15)
                                              : AppTheme.routineAccent)),
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  'Today: ${sched.todaySummary}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: sched.isCompletedToday
                                        ? Colors.green
                                        : (sched.isFailedToday
                                            ? Colors.redAccent
                                            : (sched.todayCompletionFraction > 0
                                                ? const Color(0xFFFACC15)
                                                : AppTheme.routineAccent)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (sched.hasPastSchedules)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.history_rounded, size: 11, color: AppTheme.textSecondary),
                              const SizedBox(width: 3),
                              Text(
                                'Past: ${sched.pastSummary}',
                                style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
                              ),
                            ],
                          ),
                        if (sched.hasUpcoming)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.calendar_month_rounded, size: 11, color: AppTheme.routineAccent),
                              const SizedBox(width: 3),
                              Text(
                                'Next: ${sched.upcomingSummary}',
                                style: const TextStyle(fontSize: 10, color: AppTheme.routineAccent, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _getScheduleText(NeuroItem item) {
    switch (item.scheduleType) {
      case ScheduleType.everyday:
        return 'Everyday';
      case ScheduleType.specificDaysOfWeek:
        return 'Days of week (${item.selectedDaysOfWeek.length} selected)';
      case ScheduleType.specificDaysOfMonth:
        return 'Days of month (${item.selectedDaysOfMonth.length} selected)';
      case ScheduleType.specificDaysOfYear:
        return 'Days of year (${item.selectedDaysOfYear.length} selected)';
      case ScheduleType.someDaysPerPeriod:
        return 'Periodic';
      case ScheduleType.repeatInterval:
        return 'Every ${item.repeatIntervalDays} days';
    }
  }

  Color _getPriorityColor(int priority) {
    if (priority <= 30) return Colors.redAccent;
    if (priority <= 70) return Colors.orangeAccent;
    return AppTheme.routineAccent;
  }
}
