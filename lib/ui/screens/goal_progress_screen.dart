import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;
import '../../models/neuro_item.dart';
import '../../providers/neuro_providers.dart';
import '../../services/aggregation_engine.dart';
import '../theme/app_theme.dart';
import '../widgets/compile_folder_dialog.dart';
import '../widgets/unified_options_bottom_sheet.dart';
import '../widgets/unified_stepper_dialog.dart';
import 'vision_detail_screen.dart';

class GoalProgressScreen extends ConsumerStatefulWidget {
  const GoalProgressScreen({super.key});

  @override
  ConsumerState<GoalProgressScreen> createState() => _GoalProgressScreenState();
}

class _GoalProgressScreenState extends ConsumerState<GoalProgressScreen> {
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
    final visions = ref.watch(visionsProvider);
    final notifier = ref.read(neuroItemsProvider.notifier);

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Visions'),
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
              const Text(
                'Macro Vision Folders',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Tree Hierarchical Distribution System • Drag to prioritize',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
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
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? AppTheme.primaryAccent : AppTheme.textSecondary,
                          ),
                        ),
                        selected: isSelected,
                        selectedColor: AppTheme.primaryAccent.withValues(alpha: 0.18),
                        backgroundColor: AppTheme.surfaceColor,
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
              const SizedBox(height: 16),

              Expanded(
                child: visions.isEmpty
                    ? Center(
                        child: Text(
                          'No Macro Visions created yet.\nTap + to add your first Vision Folder button!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppTheme.textSecondary),
                        ),
                      )
                    : ReorderableListView.builder(
                        itemCount: visions.length,
                        onReorder: (oldIndex, newIndex) {
                          if (newIndex > oldIndex) newIndex -= 1;
                          final item = visions.removeAt(oldIndex);
                          visions.insert(newIndex, item);
                          notifier.reorderTasks(visions);
                        },
                        itemBuilder: (context, index) {
                          final vision = visions[index];
                          final isCustom = _selectedTimeRange == ProgressTimeRange.custom && _customDateRange != null;
                          final today = isCustom ? _customDateRange!.end : DateTime.now();
                          final startDate = vision.startDate ?? vision.createdAt;
                          final calculatedDays = isCustom
                              ? (_customDateRange!.duration.inDays + 1)
                              : (_selectedTimeRange.days ??
                                  math.max(7, DateTime(today.year, today.month, today.day)
                                      .difference(DateTime(startDate.year, startDate.month, startDate.day))
                                      .inDays + 1));

                          final progress = AggregationEngine.calculateVisionProgress(
                            rootVisionId: vision.id,
                            allItems: allItems,
                            days: calculatedDays,
                            referenceDate: today,
                          );

                          final series = AggregationEngine.computeRollingSeries(
                            rootVisionId: vision.id,
                            allItems: allItems,
                            days: calculatedDays,
                            referenceDate: today,
                          );

                          return Container(
                            key: ValueKey(vision.id),
                            margin: const EdgeInsets.only(bottom: 16.0),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => VisionDetailScreen(vision: vision),
                                    ),
                                  );
                                },
                                onLongPress: () {
                                  UnifiedOptionsBottomSheet.show(
                                    context: context,
                                    title: vision.title,
                                    subtitle: 'Macro Vision Folder',
                                    onEdit: () {
                                      showDialog(
                                        context: context,
                                        builder: (context) => UnifiedStepperDialog(
                                          title: 'Edit Vision Folder',
                                          isFolder: true,
                                          existingItem: vision,
                                          onSave: (updated) => notifier.updateItem(updated),
                                        ),
                                      );
                                    },
                                    onDelete: () => notifier.deleteItem(vision.id),
                                    onCompile: () {
                                      CompileFolderHelper.showCompileDialog(
                                        context: context,
                                        sourceItem: vision,
                                        availableFolders: visions,
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
                                      color: AppTheme.primaryAccent.withValues(alpha: 0.3),
                                      width: 1.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppTheme.primaryAccent.withValues(alpha: 0.05),
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
                                              color: AppTheme.primaryAccent
                                                  .withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(16.0),
                                            ),
                                            child: const Icon(
                                              Icons.account_tree_outlined,
                                              color: AppTheme.primaryAccent,
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
                                                        color: _getPriorityColor(vision.priority)
                                                            .withValues(alpha: 0.15),
                                                        borderRadius: BorderRadius.circular(6),
                                                      ),
                                                      child: Text(
                                                        'P${vision.priority}',
                                                        style: TextStyle(
                                                          fontSize: 10,
                                                          fontWeight: FontWeight.bold,
                                                          color: _getPriorityColor(vision.priority),
                                                        ),
                                                      ),
                                                    ),
                                                    Expanded(
                                                      child: Text(
                                                        vision.title,
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
                                                  'Start: ${DateFormat('MMM d, yyyy').format(vision.startDate ?? vision.createdAt)}${vision.endDate != null ? ' • End: ${DateFormat('MMM d, yyyy').format(vision.endDate!)}' : ''}',
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

                                      // Isolation Guard Indicator
                                      if (vision.noVisionXpEnabled)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 4),
                                          margin: const EdgeInsets.only(bottom: 10),
                                          decoration: BoxDecoration(
                                            color: Colors.orange.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.shield_outlined,
                                                  size: 14, color: Colors.orange),
                                              SizedBox(width: 6),
                                              Text(
                                                'Isolation Guard Active (No XP)',
                                                style: TextStyle(
                                                    fontSize: 11, color: Colors.orange),
                                              ),
                                            ],
                                          ),
                                        ),

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
                                      const SizedBox(height: 12),

                                      // Progress Bar
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            'Macro Vision Progress (${_getTimeRangeLabel()})',
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
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primaryAccent,
        icon: const Icon(Icons.add, color: AppTheme.backgroundColor),
        label: const Text(
          'New Vision Folder',
          style: TextStyle(color: AppTheme.backgroundColor, fontWeight: FontWeight.bold),
        ),
        onPressed: () {
          showDialog(
            context: context,
            builder: (context) => UnifiedStepperDialog(
              title: 'Create Vision Folder',
              isFolder: true,
              onSave: (item) {
                notifier.addItem(
                  title: item.title,
                  description: item.description,
                  type: NeuroItemType.vision,
                  startDate: item.startDate,
                  endDate: item.endDate,
                  priority: item.priority,
                );
              },
            ),
          );
        },
      ),
    );
  }

  Color _getPriorityColor(int priority) {
    if (priority <= 30) return Colors.redAccent;
    if (priority <= 70) return Colors.orangeAccent;
    return AppTheme.routineAccent;
  }
}
