import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../models/neuro_item.dart';
import '../../providers/neuro_providers.dart';
import '../../services/aggregation_engine.dart';
import '../theme/app_theme.dart';
import '../widgets/compile_folder_dialog.dart';
import '../widgets/unified_options_bottom_sheet.dart';
import '../widgets/unified_stepper_dialog.dart';
import '../widgets/item_insights_bottom_sheet.dart';

import 'dart:math' as math;

class VisionDetailScreen extends ConsumerStatefulWidget {
  final NeuroItem vision;

  const VisionDetailScreen({super.key, required this.vision});

  @override
  ConsumerState<VisionDetailScreen> createState() => _VisionDetailScreenState();
}

enum FolderViewFilter { all, habits, tasks }

class _VisionDetailScreenState extends ConsumerState<VisionDetailScreen> {
  ProgressTimeRange _selectedTimeRange = ProgressTimeRange.sevenDays;
  ScheduleFilterOption _scheduleFilter = ScheduleFilterOption.all;
  FolderViewFilter _itemTypeFilter = FolderViewFilter.all;
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
    final notifier = ref.read(neuroItemsProvider.notifier);

    final vision = widget.vision;

    final isCustom = _selectedTimeRange == ProgressTimeRange.custom && _customDateRange != null;
    final today = isCustom ? _customDateRange!.end : DateTime.now();
    final startDate = vision.startDate ?? vision.createdAt;
    final calculatedDays = isCustom
        ? (_customDateRange!.duration.inDays + 1)
        : (_selectedTimeRange.days ??
            math.max(7, DateTime(today.year, today.month, today.day)
                .difference(DateTime(startDate.year, startDate.month, startDate.day))
                .inDays + 1));

    // Calculate node progress using the time-period scheduled occurrences engine (Button 2 logic)
    final progress = AggregationEngine.calculateVisionNodeProgress(
      vision: vision,
      allItems: allItems,
      days: calculatedDays,
      referenceDate: today,
    );

    final series = AggregationEngine.computeRollingSeries(
      rootVisionId: vision.rootVisionId ?? vision.id,
      allItems: allItems,
      days: calculatedDays,
      referenceDate: today,
    );

    // Separate direct child folders/buttons from child tasks/routines (Tree Distribution System)
    final childFolders = allItems.where((item) =>
        item.parentId == vision.id &&
        (item.type == NeuroItemType.vision ||
            item.type == NeuroItemType.routineFolder ||
            item.type == NeuroItemType.goal)).toList();

    final childTasks = allItems.where((item) =>
        (item.parentId == vision.id || item.rootVisionId == vision.id) &&
        (item.type == NeuroItemType.task || item.type == NeuroItemType.routine)).toList();

    // Sort by priority
    childFolders.sort((a, b) => a.priority.compareTo(b.priority));
    childTasks.sort((a, b) => a.priority.compareTo(b.priority));

    final childHabits = childTasks.where((item) => item.type == NeuroItemType.routine).toList();
    final childOneTimeTasks = childTasks.where((item) => item.type == NeuroItemType.task).toList();

    final filteredChildTasks = childTasks.where((task) {
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

    final filteredHabits = filteredChildTasks.where((item) => item.type == NeuroItemType.routine).toList();
    final filteredOneTimeTasks = filteredChildTasks.where((item) => item.type == NeuroItemType.task).toList();

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: Text(vision.title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.insights_rounded, color: AppTheme.primaryAccent),
            tooltip: 'View Insights',
            onPressed: () => ItemInsightsBottomSheet.show(
              context,
              item: vision,
              allItems: allItems,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Macro Vision / Sub-Folder Header Card
              Container(
                padding: const EdgeInsets.all(18.0),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceColor,
                  borderRadius: BorderRadius.circular(20.0),
                  border: Border.all(
                    color: AppTheme.primaryAccent.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            vision.title,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryAccent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${(progress * 100).toInt()}%',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryAccent,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (vision.description != null && vision.description!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        vision.description!,
                        style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                      ),
                    ],
                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Text(
                          'Start: ${DateFormat('MMM d, yyyy').format(vision.startDate ?? vision.createdAt)}${vision.endDate != null ? ' • End: ${DateFormat('MMM d, yyyy').format(vision.endDate!)}' : ''}',
                          style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Time Range Selector Pill Bar
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
                                  fontSize: 11,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  color: isSelected ? AppTheme.primaryAccent : AppTheme.textSecondary,
                                ),
                              ),
                              selected: isSelected,
                              selectedColor: AppTheme.primaryAccent.withValues(alpha: 0.18),
                              backgroundColor: AppTheme.backgroundColor,
                              side: BorderSide(
                                color: isSelected
                                    ? AppTheme.primaryAccent
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
                                            primary: AppTheme.primaryAccent,
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
                    const SizedBox(height: 12),

                    if (vision.noVisionXpEnabled)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.shield_outlined, size: 14, color: Colors.orange),
                            SizedBox(width: 6),
                            Text(
                              'Isolation Guard Active (No XP)',
                              style: TextStyle(fontSize: 11, color: Colors.orange),
                            ),
                          ],
                        ),
                      ),

                    // Progress Bar
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Subtree Progress (${_getTimeRangeLabel()})',
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
                            color: progress < 0 ? Colors.redAccent : AppTheme.primaryAccent,
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
                          progress < 0 ? Colors.redAccent : AppTheme.primaryAccent,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Rolling Progress Sparkline
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
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '${_getTimeRangeLabel()} Rolling Sparkline (Tree Engine)',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                                if (hasNegative)
                                  Row(
                                    children: [
                                      const Icon(Icons.trending_down_rounded, size: 13, color: Colors.redAccent),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Negative dip: min ${minVal.toInt()}',
                                        style: const TextStyle(fontSize: 10, color: Colors.redAccent, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            SizedBox(
                              height: 60,
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
                                      color: vision.noVisionXpEnabled
                                          ? Colors.grey
                                          : (hasNegative && series.isNotEmpty && series.last < 0
                                              ? Colors.redAccent
                                              : AppTheme.primaryAccent),
                                      barWidth: 2.5,
                                      isStrokeCapRound: true,
                                      dotData: const FlDotData(show: false),
                                      belowBarData: BarAreaData(
                                        show: true,
                                        cutOffY: 0.0,
                                        applyCutOffY: hasNegative,
                                        color: (vision.noVisionXpEnabled
                                                ? Colors.grey
                                                : AppTheme.primaryAccent)
                                            .withValues(alpha: 0.12),
                                      ),
                                      aboveBarData: BarAreaData(
                                        show: hasNegative,
                                        cutOffY: 0.0,
                                        applyCutOffY: true,
                                        color: Colors.redAccent.withValues(alpha: 0.15),
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

              const SizedBox(height: 20),

              // SECTION 1: Sub-Folders / Buttons (Nested Loop System)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Sub-Folders & Buttons (${childFolders.length})',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.create_new_folder_outlined, size: 18, color: AppTheme.primaryAccent),
                    label: const Text('+ Sub-Folder', style: TextStyle(color: AppTheme.primaryAccent, fontSize: 12)),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) => UnifiedStepperDialog(
                          title: 'Create Sub-Folder',
                          isFolder: true,
                          parentId: vision.id,
                          onSave: (item) {
                            notifier.addItem(
                              title: item.title,
                              description: item.description,
                              type: NeuroItemType.vision,
                              parentId: vision.id,
                              rootVisionId: vision.rootVisionId ?? vision.id,
                              startDate: item.startDate,
                              endDate: item.endDate,
                              priority: item.priority,
                            );
                          },
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 6),

              if (childFolders.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceColor.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: const Text(
                    'No sub-folders yet. Tap "+ Sub-Folder" to create nested buttons inside this container!',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                )
              else
                ...childFolders.map((childFolder) {
                  final folderProg = AggregationEngine.calculateVisionNodeProgress(
                    vision: childFolder,
                    allItems: allItems,
                  );

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12.0),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          // Recursive navigation to nested sub-folder!
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => VisionDetailScreen(vision: childFolder),
                            ),
                          );
                        },
                        onLongPress: () {
                          UnifiedOptionsBottomSheet.show(
                            context: context,
                            title: childFolder.title,
                            subtitle: 'Sub-Folder Button',
                            onEdit: () {
                              showDialog(
                                context: context,
                                builder: (context) => UnifiedStepperDialog(
                                  title: 'Edit Sub-Folder',
                                  isFolder: true,
                                  existingItem: childFolder,
                                  onSave: (updated) => notifier.updateItem(updated),
                                ),
                              );
                            },
                            onDelete: () => notifier.deleteItem(childFolder.id),
                            onCompile: () {
                              CompileFolderHelper.showCompileDialog(
                                context: context,
                                sourceItem: childFolder,
                                availableFolders: allItems
                                    .where((i) => i.id != childFolder.id && (i.type == NeuroItemType.vision || i.type == NeuroItemType.routineFolder))
                                    .toList(),
                                allItems: allItems,
                                notifier: notifier,
                              );
                            },
                            onInsights: () => ItemInsightsBottomSheet.show(
                              context,
                              item: childFolder,
                              allItems: allItems,
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(16.0),
                        child: Ink(
                          padding: const EdgeInsets.all(16.0),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceColor,
                            borderRadius: BorderRadius.circular(16.0),
                            border: Border.all(
                              color: AppTheme.primaryAccent.withValues(alpha: 0.3),
                              width: 1.2,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10.0),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primaryAccent.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(12.0),
                                    ),
                                    child: const Icon(
                                      Icons.folder_special_rounded,
                                      color: AppTheme.primaryAccent,
                                      size: 22,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          childFolder.title,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.textPrimary,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'P${childFolder.priority} • Start: ${DateFormat('MMM d').format(childFolder.startDate ?? childFolder.createdAt)}',
                                          style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '${(folderProg * 100).toInt()}%',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.primaryAccent,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.chevron_right_rounded, color: AppTheme.textSecondary, size: 20),
                                ],
                              ),
                              const SizedBox(height: 10),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4.0),
                                child: LinearProgressIndicator(
                                  value: folderProg,
                                  minHeight: 4,
                                  backgroundColor: AppTheme.backgroundColor,
                                  valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryAccent),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),

              const SizedBox(height: 20),

              // SECTION 2: Master Tasks & Routines (Planning View)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Folder Items (${childTasks.length})',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  Row(
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.repeat_rounded, size: 16, color: AppTheme.primaryAccent),
                        label: const Text('+ Habit', style: TextStyle(color: AppTheme.primaryAccent, fontSize: 12)),
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (context) => UnifiedStepperDialog(
                              title: 'Add Habit / Routine',
                              isFolder: false,
                              parentId: vision.id,
                              initialType: NeuroItemType.routine,
                              onSave: (item) {
                                notifier.updateItem(
                                  item.copyWith(
                                    parentId: vision.id,
                                    rootVisionId: vision.rootVisionId ?? vision.id,
                                    type: NeuroItemType.routine,
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 4),
                      TextButton.icon(
                        icon: const Icon(Icons.add_task_rounded, size: 16, color: AppTheme.secondaryAccent),
                        label: const Text('+ Task', style: TextStyle(color: AppTheme.secondaryAccent, fontSize: 12)),
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (context) => UnifiedStepperDialog(
                              title: 'Add One-Time Task',
                              isFolder: false,
                              parentId: vision.id,
                              initialType: NeuroItemType.task,
                              onSave: (item) {
                                notifier.updateItem(
                                  item.copyWith(
                                    parentId: vision.id,
                                    rootVisionId: vision.rootVisionId ?? vision.id,
                                    type: NeuroItemType.task,
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Item Type Segmented Pill Bar
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildItemTypeChip(
                      label: 'All (${childTasks.length})',
                      isSelected: _itemTypeFilter == FolderViewFilter.all,
                      onTap: () => setState(() => _itemTypeFilter = FolderViewFilter.all),
                    ),
                    const SizedBox(width: 8),
                    _buildItemTypeChip(
                      label: 'Habits (${childHabits.length})',
                      isSelected: _itemTypeFilter == FolderViewFilter.habits,
                      color: AppTheme.primaryAccent,
                      onTap: () => setState(() => _itemTypeFilter = FolderViewFilter.habits),
                    ),
                    const SizedBox(width: 8),
                    _buildItemTypeChip(
                      label: 'One-Time Tasks (${childOneTimeTasks.length})',
                      isSelected: _itemTypeFilter == FolderViewFilter.tasks,
                      color: AppTheme.secondaryAccent,
                      onTap: () => setState(() => _itemTypeFilter = FolderViewFilter.tasks),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Schedule Filter Pill Bar
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
                                ? AppTheme.secondaryAccent.withValues(alpha: 0.2)
                                : AppTheme.surfaceColor,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected
                                  ? AppTheme.secondaryAccent
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
              const SizedBox(height: 10),

              if (childTasks.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceColor.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: const Text(
                    'No tasks or habits in this folder.\nTap "+ Habit" or "+ Task" to add items (they will appear in Daily Track on scheduled days)!',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                )
              else if (filteredChildTasks.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceColor.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: Text(
                    'No items match the "${_scheduleFilter.label}" schedule filter.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                )
              else ...[
                // HABITS SECTION
                if (_itemTypeFilter == FolderViewFilter.all || _itemTypeFilter == FolderViewFilter.habits) ...[
                  Row(
                    children: [
                      const Icon(Icons.repeat_rounded, size: 16, color: AppTheme.primaryAccent),
                      const SizedBox(width: 6),
                      Text(
                        'Habits & Routines (${childHabits.length})',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (childHabits.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceColor.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: const Text(
                        'No habits or routines set up yet. Tap "+ Habit" to build a habit.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                      ),
                    )
                  else if (filteredHabits.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceColor.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: Text(
                        'No habits match the "${_scheduleFilter.label}" schedule filter.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                      ),
                    )
                  else
                    ...filteredHabits.map((task) => _buildTaskItemCard(context, task, notifier, allItems)),
                  if (_itemTypeFilter == FolderViewFilter.all) const SizedBox(height: 16),
                ],

                // ONE-TIME TASKS SECTION
                if (_itemTypeFilter == FolderViewFilter.all || _itemTypeFilter == FolderViewFilter.tasks) ...[
                  Row(
                    children: [
                      const Icon(Icons.task_alt_rounded, size: 16, color: AppTheme.secondaryAccent),
                      const SizedBox(width: 6),
                      Text(
                        'One-Time Tasks (${childOneTimeTasks.length})',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (childOneTimeTasks.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceColor.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: const Text(
                        'No one-time tasks in this vision yet. Tap "+ Task" to create one.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                      ),
                    )
                  else if (filteredOneTimeTasks.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceColor.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: Text(
                        'No tasks match the "${_scheduleFilter.label}" schedule filter.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                      ),
                    )
                  else
                    ...filteredOneTimeTasks.map((task) => _buildTaskItemCard(context, task, notifier, allItems)),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildItemTypeChip({
    required String label,
    required bool isSelected,
    Color color = AppTheme.secondaryAccent,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.2) : AppTheme.surfaceColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? color : const Color(0xFF334155),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildTaskItemCard(
    BuildContext context,
    NeuroItem task,
    NeuroItemsNotifier notifier,
    List<NeuroItem> allItems,
  ) {
    final sched = AggregationEngine.getItemScheduleInfo(task);
    return GestureDetector(
      onLongPress: () {
        UnifiedOptionsBottomSheet.show(
          context: context,
          title: task.title,
          subtitle: task.type == NeuroItemType.routine ? 'Habit / Routine' : 'Daily Task',
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
      child: Container(
        margin: const EdgeInsets.only(bottom: 10.0),
        padding: const EdgeInsets.all(14.0),
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor,
          borderRadius: BorderRadius.circular(14.0),
          border: Border.all(
            color: (task.type == NeuroItemType.routine ? AppTheme.primaryAccent : AppTheme.secondaryAccent).withValues(alpha: 0.2),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: (task.type == NeuroItemType.routine ? AppTheme.primaryAccent : AppTheme.secondaryAccent).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    task.type == NeuroItemType.routine
                        ? (task.routineCategory == RoutineCategory.habit ? 'Habit' : 'Repetitive Task')
                        : 'One-Time Task',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: task.type == NeuroItemType.routine ? AppTheme.primaryAccent : AppTheme.secondaryAccent,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    task.type == NeuroItemType.routine
                        ? _formatScheduleString(task)
                        : (task.targetDate != null
                            ? DateFormat('MMM d, yyyy').format(task.targetDate!)
                            : 'Flexible (No Date)'),
                    style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _getPriorityColor(task.priority).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'P${task.priority}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: _getPriorityColor(task.priority),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            Text(
              task.title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            if (task.description != null && task.description!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                task.description!,
                style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
            ],
            const SizedBox(height: 8),

            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.backgroundColor,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: Text(
                    _getTrackerSummary(task),
                    style: const TextStyle(fontSize: 11, color: AppTheme.primaryAccent),
                  ),
                ),
                if (task.checklist.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    '${task.checklist.length} sub-items',
                    style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                  ),
                ],
                if (task.isPendingCarryover || task.isFlexibleCarryover) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.purple.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'CO',
                      style: TextStyle(
                        fontSize: 9,
                        color: Colors.purpleAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),

            // SCHEDULE STATUS BADGES (Past, Today, Upcoming)
            const SizedBox(height: 8),
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
                                    : AppTheme.primaryAccent.withValues(alpha: 0.15))),
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
                                        : AppTheme.primaryAccent)),
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
                                          : AppTheme.primaryAccent)),
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
                        const Icon(Icons.calendar_month_rounded, size: 11, color: AppTheme.secondaryAccent),
                        const SizedBox(width: 3),
                        Text(
                          'Next: ${sched.upcomingSummary}',
                          style: const TextStyle(fontSize: 10, color: AppTheme.secondaryAccent, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getPriorityColor(int priority) {
    if (priority <= 30) return Colors.redAccent;
    if (priority <= 70) return Colors.orangeAccent;
    return AppTheme.routineAccent;
  }

  String _getTrackerSummary(NeuroItem task) {
    switch (task.completionType) {
      case RoutineCompletionType.yesNo:
        return 'Checkoff Task';
      case RoutineCompletionType.numeric:
        return 'Target: ${(task.targetNumericValue ?? 1).toInt()} units';
      case RoutineCompletionType.timer:
        final mins = (task.timerDurationSeconds ?? 600) ~/ 60;
        return 'Timer: $mins mins';
      case RoutineCompletionType.checklist:
        return 'Checklist';
    }
  }

  String _formatScheduleString(NeuroItem item) {
    switch (item.scheduleType) {
      case ScheduleType.everyday:
        return 'Everyday';
      case ScheduleType.specificDaysOfWeek:
        return 'Specific days of week';
      case ScheduleType.specificDaysOfMonth:
        return 'Specific days of month (${item.selectedDaysOfMonth.join(', ')})';
      case ScheduleType.specificDaysOfYear:
        return 'Specific days of year (${item.selectedDaysOfYear.join(', ')})';
      case ScheduleType.someDaysPerPeriod:
        return 'Some days per period';
      case ScheduleType.repeatInterval:
        return 'Repeat every ${item.repeatIntervalDays} days';
    }
  }
}
