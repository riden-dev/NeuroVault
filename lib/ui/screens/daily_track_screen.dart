import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/neuro_item.dart';
import '../../providers/neuro_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/unified_options_bottom_sheet.dart';
import '../widgets/unified_stepper_dialog.dart';
import '../widgets/item_insights_bottom_sheet.dart';
import '../widgets/account_sync_dialog.dart';
import '../../providers/auth_provider.dart';
import '../../services/cloud_sync_service.dart';
import '../../services/aggregation_engine.dart';
import 'home_screen.dart';

enum DailyViewMode {
  defaultCategories,
  customCategories,
  priorityList,
}

class DailyTrackScreen extends ConsumerStatefulWidget {
  const DailyTrackScreen({super.key});

  @override
  ConsumerState<DailyTrackScreen> createState() => _DailyTrackScreenState();
}

class _DailyTrackScreenState extends ConsumerState<DailyTrackScreen> {
  late DateTime _today;
  late DateTime _selectedDate;
  late final ScrollController _calendarScrollController;
  final Map<String, bool> _collapsedGroups = {};
  final Set<String> _expandedChecklistItems = {};
  final List<String> _categoryKeysOrder = [];
  DailyViewMode _viewMode = DailyViewMode.defaultCategories;
  String? _activeCategoryActionId;
  bool _isUngroupedCategoryDeleted = false;
  String _customUngroupedName = 'Ungrouped Tasks';
  int? _customUngroupedColor;
  int _customUngroupedPriority = 50;
  final Map<String, String> _categoryItemTypeFilters = {};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _today = DateTime(now.year, now.month, now.day);
    _selectedDate = _today;
    _calendarScrollController = ScrollController();

    // Load persisted category order & visibility preferences
    final storage = ref.read(storageServiceProvider);
    _categoryKeysOrder.addAll(storage.getDailyCategoryOrder());
    final modeIdx = storage.getDailyViewMode();
    _viewMode = DailyViewMode.values[modeIdx.clamp(0, 2)];
    _isUngroupedCategoryDeleted = storage.getIsUngroupedCategoryDeleted();
    _customUngroupedName = storage.getCustomUngroupedName();
    _customUngroupedColor = storage.getCustomUngroupedColor();
    _customUngroupedPriority = storage.getCustomUngroupedPriority();

    // Load persisted collapsed categories (so they stay closed until changed)
    final collapsedList = storage.getCollapsedCategoryIds();
    for (final id in collapsedList) {
      _collapsedGroups[id] = true;
    }
    _expandedChecklistItems.addAll(storage.getExpandedChecklistItemIds());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _centerTodayInCalendar();
    });
  }

  void _toggleChecklistExpanded(String itemId) {
    setState(() {
      if (_expandedChecklistItems.contains(itemId)) {
        _expandedChecklistItems.remove(itemId);
      } else {
        _expandedChecklistItems.add(itemId);
      }
      final storage = ref.read(storageServiceProvider);
      storage.saveExpandedChecklistItemIds(_expandedChecklistItems.toList());
    });
  }

  void _setViewMode(DailyViewMode mode) {
    setState(() {
      _viewMode = mode;
      final storage = ref.read(storageServiceProvider);
      storage.saveDailyViewMode(mode.index);
    });
  }

  void _cycleViewMode() {
    DailyViewMode next;
    switch (_viewMode) {
      case DailyViewMode.defaultCategories:
        next = DailyViewMode.customCategories;
        break;
      case DailyViewMode.customCategories:
        next = DailyViewMode.priorityList;
        break;
      case DailyViewMode.priorityList:
        next = DailyViewMode.defaultCategories;
        break;
    }
    _setViewMode(next);

    String label;
    switch (next) {
      case DailyViewMode.defaultCategories:
        label = 'Default Folders';
        break;
      case DailyViewMode.customCategories:
        label = 'Custom Categories';
        break;
      case DailyViewMode.priorityList:
        label = 'Priority List';
        break;
    }
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Switched to: $label'),
        duration: const Duration(milliseconds: 1500),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    _calendarScrollController.dispose();
    super.dispose();
  }

  static const int _kCalendarCenterIndex = 10000;
  static const int _kCalendarTotalDays = 20001;
  static const double _kCalendarItemWidth = 62.0;

  void _centerDateInCalendar(DateTime targetDate, {bool animate = false}) {
    if (!_calendarScrollController.hasClients) return;
    final dayDiff = DateTime(targetDate.year, targetDate.month, targetDate.day)
        .difference(_today)
        .inDays;
    final targetIndex = _kCalendarCenterIndex + dayDiff;
    final screenWidth = MediaQuery.of(context).size.width;
    final targetOffset = 43.0 + (targetIndex * _kCalendarItemWidth) - (screenWidth / 2);
    final clampedOffset = targetOffset.clamp(
      0.0,
      _calendarScrollController.position.maxScrollExtent,
    );

    if (animate) {
      _calendarScrollController.animateTo(
        clampedOffset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _calendarScrollController.jumpTo(clampedOffset);
    }
  }

  void _centerTodayInCalendar() {
    _centerDateInCalendar(_today, animate: false);
  }

  Future<void> _pickCustomDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.primaryAccent,
              onPrimary: AppTheme.backgroundColor,
              surface: AppTheme.surfaceColor,
              onSurface: AppTheme.textPrimary,
            ),
            dialogTheme: const DialogThemeData(backgroundColor: AppTheme.surfaceColor),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      final normalizedPicked = DateTime(picked.year, picked.month, picked.day);
      setState(() {
        _selectedDate = normalizedPicked;
      });
      _centerDateInCalendar(normalizedPicked, animate: true);
    }
  }

  int _getCategoryPriority(String key, List<DailyCategory> dailyCats, List<NeuroItem> allItems) {
    if (key == 'UNGROUPED_TODOS') {
      return _customUngroupedPriority;
    }
    final dCat = dailyCats.where((c) => c.id == key).firstOrNull;
    if (dCat != null) return dCat.priority;

    final item = allItems.where((i) => i.id == key).firstOrNull;
    if (item != null) return item.priority;

    final savedIdx = _categoryKeysOrder.indexOf(key);
    return savedIdx >= 0 ? savedIdx + 1 : 50;
  }

  Color _getPriorityColor(int priority) {
    if (priority <= 30) return Colors.redAccent;
    if (priority <= 70) return Colors.orangeAccent;
    return AppTheme.routineAccent;
  }

  @override
  Widget build(BuildContext context) {
    final allItems = ref.watch(neuroItemsProvider);
    final dailyCategories = ref.watch(dailyCategoriesProvider);
    final dailyItems = ref.watch(dailyTrackItemsProvider(_selectedDate));
    final notifier = ref.read(neuroItemsProvider.notifier);
    final storage = ref.read(storageServiceProvider);

    // Group daily items according to active view mode:
    // Mode 0: Default folder-based categories (as per folders/routines/visions)
    // Mode 1: Custom user-created categories (labels only)
    // Mode 2: Priority list (flat list, does not use groupedItems)
    final Map<String, List<NeuroItem>> groupedItems = {};
    if (_viewMode == DailyViewMode.defaultCategories) {
      for (final item in dailyItems) {
        final parentKey = item.parentId ?? 'UNGROUPED_TODOS';
        groupedItems.putIfAbsent(parentKey, () => []).add(item);
      }
    } else if (_viewMode == DailyViewMode.customCategories) {
      for (final item in dailyItems) {
        final catKey = item.dailyCategoryId ?? 'UNGROUPED_TODOS';
        groupedItems.putIfAbsent(catKey, () => []).add(item);
      }
      for (final cat in dailyCategories) {
        groupedItems.putIfAbsent(cat.id, () => []);
      }
      if (_isUngroupedCategoryDeleted) {
        groupedItems.remove('UNGROUPED_TODOS');
      }
    }

    // Maintain category keys order for reordering & persistence
    for (final key in groupedItems.keys) {
      if (!_categoryKeysOrder.contains(key)) {
        _categoryKeysOrder.add(key);
      }
    }
    _categoryKeysOrder.removeWhere((key) => !groupedItems.containsKey(key));

    // Create a display-only copy of category keys for rendering on _selectedDate
    // Incomplete categories first, 100% completed/failed categories pushed to bottom for _selectedDate
    // The master _categoryKeysOrder is NEVER mutated in build() so default priorities and orders are preserved
    _customUngroupedPriority = storage.getCustomUngroupedPriority();
    final displayCategoryKeys = List<String>.from(_categoryKeysOrder);
    final initialIndices = {for (var i = 0; i < displayCategoryKeys.length; i++) displayCategoryKeys[i]: i};
    displayCategoryKeys.sort((a, b) {
      final tasksA = groupedItems[a] ?? [];
      final tasksB = groupedItems[b] ?? [];
      final aAllDone = tasksA.isNotEmpty && tasksA.every((t) => t.isCompletedOnDate(_selectedDate) || t.isFailedOnDate(_selectedDate));
      final bAllDone = tasksB.isNotEmpty && tasksB.every((t) => t.isCompletedOnDate(_selectedDate) || t.isFailedOnDate(_selectedDate));
      if (aAllDone != bAllDone) {
        return aAllDone ? 1 : -1;
      }
      return (initialIndices[a] ?? 0).compareTo(initialIndices[b] ?? 0);
    });

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Daily Track'),
        leading: IconButton(
          icon: Icon(
            Navigator.canPop(context)
                ? Icons.arrow_back_ios_new_rounded
                : Icons.home_rounded,
          ),
          tooltip: Navigator.canPop(context) ? 'Back' : 'Home',
          onPressed: () {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => HomeScreen()),
              );
            }
          },
        ),
        actions: [
          if (_viewMode == DailyViewMode.customCategories) ...[
            if (dailyCategories.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.delete_sweep_outlined, color: Colors.redAccent),
                tooltip: 'Delete All Categories',
                onPressed: () => _showDeleteAllCategoriesDialog(context, notifier),
              ),
            IconButton(
              icon: const Icon(Icons.create_new_folder_outlined, color: AppTheme.routineAccent),
              tooltip: 'New Category',
              onPressed: () => _showCreateCategoryDialog(context),
            ),
          ],
          IconButton(
            icon: Icon(
              _viewMode == DailyViewMode.defaultCategories
                  ? Icons.view_agenda_rounded
                  : (_viewMode == DailyViewMode.customCategories
                      ? Icons.label_outline_rounded
                      : Icons.format_list_numbered_rounded),
              color: _viewMode == DailyViewMode.defaultCategories
                  ? AppTheme.primaryAccent
                  : (_viewMode == DailyViewMode.customCategories
                      ? AppTheme.secondaryAccent
                      : AppTheme.routineAccent),
            ),
            tooltip: _viewMode == DailyViewMode.defaultCategories
                ? 'Default Folders Mode (Tap to cycle)'
                : (_viewMode == DailyViewMode.customCategories
                    ? 'Custom Categories Mode (Tap to cycle)'
                    : 'Priority List Mode (Tap to cycle)'),
            onPressed: _cycleViewMode,
          ),
          _buildAccountSyncButton(context),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Rolling Calendar Header (Current Day Centered by Default)
            _buildRollingCalendarHeader(),

            const SizedBox(height: 12),

            // Subtitle Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Row(
                children: [
                  InkWell(
                    onTap: () => _pickCustomDate(context),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 2.0),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            DateFormat('EEEE, MMM d, yyyy').format(_selectedDate),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryAccent,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.calendar_month_rounded,
                            size: 16,
                            color: AppTheme.primaryAccent,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${dailyItems.length} items scheduled',
                    style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Central Aggregated Daily Execution List
            Expanded(
              child: dailyItems.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.track_changes_rounded,
                            size: 48,
                            color: AppTheme.textSecondary.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'No habits or tasks scheduled for this day.\nAdd tasks in Visions, Routines, or To-Do List!',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    )
                  : (_viewMode == DailyViewMode.priorityList)
                      ? _buildFlatTaskList(context, dailyItems, notifier, allItems, dailyCategories, isPriorityListMode: true)
                      : (_viewMode == DailyViewMode.customCategories && _isUngroupedCategoryDeleted && dailyCategories.isEmpty)
                          ? _buildFlatTaskList(context, dailyItems, notifier, allItems, dailyCategories, isPriorityListMode: false)
                          : ReorderableListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                              itemCount: displayCategoryKeys.length,
                              footer: _viewMode == DailyViewMode.customCategories ? _buildCreateCategoryDropTarget(context) : null,
                          onReorder: (oldIndex, newIndex) {
                            setState(() {
                              if (newIndex > oldIndex) newIndex -= 1;
                              final movedKey = displayCategoryKeys.removeAt(oldIndex);
                              displayCategoryKeys.insert(newIndex, movedKey);

                              // Sync master _categoryKeysOrder based on the move
                              _categoryKeysOrder.remove(movedKey);
                              final targetIdx = newIndex < displayCategoryKeys.length - 1
                                  ? _categoryKeysOrder.indexOf(displayCategoryKeys[newIndex + 1])
                                  : _categoryKeysOrder.length;
                              if (targetIdx >= 0 && targetIdx <= _categoryKeysOrder.length) {
                                _categoryKeysOrder.insert(targetIdx, movedKey);
                              } else {
                                _categoryKeysOrder.add(movedKey);
                              }
                              storage.saveDailyCategoryOrder(_categoryKeysOrder);

                              // Update priority for active categories based on new ordering
                              // Completed categories preserve their current user-set priority!
                              final updatedDailyCats = <DailyCategory>[];
                              int activeCatCounter = 1;

                              for (int i = 0; i < _categoryKeysOrder.length; i++) {
                                final catKey = _categoryKeysOrder[i];
                                final tasks = groupedItems[catKey] ?? [];
                                final isCatDone = tasks.isNotEmpty && tasks.every((t) => t.isCompletedOnDate(_selectedDate) || t.isFailedOnDate(_selectedDate));

                                final matchingCat = dailyCategories.where((c) => c.id == catKey).firstOrNull;
                                if (matchingCat != null) {
                                  if (isCatDone) {
                                    // Retain existing category and priority
                                    updatedDailyCats.add(matchingCat);
                                  } else {
                                    updatedDailyCats.add(matchingCat.copyWith(priority: activeCatCounter));
                                    activeCatCounter++;
                                  }
                                } else if (catKey == 'UNGROUPED_TODOS') {
                                  if (!isCatDone) {
                                    _customUngroupedPriority = activeCatCounter;
                                    storage.saveCustomUngroupedPriority(activeCatCounter);
                                    activeCatCounter++;
                                  }
                                } else {
                                  final folderItem = allItems.where((it) => it.id == catKey).firstOrNull;
                                  if (folderItem != null && !isCatDone) {
                                    notifier.updateItem(folderItem.copyWith(priority: activeCatCounter));
                                    activeCatCounter++;
                                  }
                                }
                              }
                              if (updatedDailyCats.isNotEmpty) {
                                ref.read(dailyCategoriesProvider.notifier).reorderCategories(updatedDailyCats);
                              }
                            });
                          },
                          itemBuilder: (context, index) {
                            final parentId = displayCategoryKeys[index];
                            final groupTasks = List<NeuroItem>.from(groupedItems[parentId] ?? []);
                            final isCollapsed = _collapsedGroups[parentId] ?? false;

                            // Sort tasks: incomplete first, completed/failed pushed to bottom
                            groupTasks.sort((a, b) {
                              final aDone = a.isCompletedOnDate(_selectedDate) || a.isFailedOnDate(_selectedDate);
                              final bDone = b.isCompletedOnDate(_selectedDate) || b.isFailedOnDate(_selectedDate);
                              if (aDone != bDone) {
                                return aDone ? 1 : -1;
                              }
                              return a.priority.compareTo(b.priority);
                            });

                            // Find Parent Folder Title or DailyCategory
                            String groupTitle = (_viewMode == DailyViewMode.defaultCategories) ? 'Daily To-Dos' : _customUngroupedName;
                            Color groupColor = (_viewMode == DailyViewMode.defaultCategories || _customUngroupedColor == null)
                                ? AppTheme.secondaryAccent
                                : Color(_customUngroupedColor!);
                            IconData groupIcon = Icons.check_circle_outline;
                            final matchingDailyCat = dailyCategories.where((c) => c.id == parentId).firstOrNull;

                            if (matchingDailyCat != null) {
                              groupTitle = matchingDailyCat.name;
                              groupColor = matchingDailyCat.colorHex != null ? Color(matchingDailyCat.colorHex!) : AppTheme.secondaryAccent;
                              groupIcon = Icons.label_rounded;
                            } else if (parentId != 'UNGROUPED_TODOS') {
                              final parentItem = allItems.where((e) => e.id == parentId).firstOrNull;
                              if (parentItem != null) {
                                groupTitle = parentItem.title;
                                if (parentItem.type == NeuroItemType.vision) {
                                  groupColor = AppTheme.primaryAccent;
                                  groupIcon = Icons.account_tree_outlined;
                                } else {
                                  groupColor = AppTheme.routineAccent;
                                  groupIcon = Icons.folder_special_rounded;
                                }
                              } else {
                                groupTitle = 'Category';
                                groupColor = AppTheme.secondaryAccent;
                                groupIcon = Icons.label_rounded;
                              }
                            }

                            final completedCount = groupTasks.where((t) => t.isCompletedOnDate(_selectedDate)).length;
                            final doneOrFailedCount = groupTasks.where((t) => t.isCompletedOnDate(_selectedDate) || t.isFailedOnDate(_selectedDate)).length;
                            final isAllCompleted = groupTasks.isNotEmpty && doneOrFailedCount == groupTasks.length;

                            final categoryPriority = _getCategoryPriority(parentId, dailyCategories, allItems);
                            final isActionActive = _activeCategoryActionId == parentId;

                            Widget categoryCardContent(bool isHovered) => Container(
                              key: ValueKey(parentId),
                              margin: const EdgeInsets.only(bottom: 18.0),
                              padding: const EdgeInsets.all(16.0),
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceColor,
                                borderRadius: BorderRadius.circular(20.0),
                                border: Border.all(
                                  color: isActionActive
                                      ? AppTheme.routineAccent
                                      : (isHovered
                                          ? AppTheme.primaryAccent
                                          : (isAllCompleted
                                              ? Colors.green.withValues(alpha: 0.3)
                                              : groupColor.withValues(alpha: 0.3))),
                                  width: isActionActive || isHovered ? 2.2 : 1.5,
                                ),
                                boxShadow: (isActionActive || isHovered)
                                    ? [
                                        BoxShadow(
                                          color: (isActionActive ? AppTheme.routineAccent : AppTheme.primaryAccent).withValues(alpha: 0.25),
                                          blurRadius: 10,
                                          offset: const Offset(0, 3),
                                        )
                                      ]
                                    : null,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Group Header (Clickable to Expand / Collapse, Long-press to reveal Edit/Delete)
                                  InkWell(
                                    onTap: () {
                                      setState(() {
                                        final newCollapsed = !isCollapsed;
                                        _collapsedGroups[parentId] = newCollapsed;
                                        final storage = ref.read(storageServiceProvider);
                                        final collapsedKeys = _collapsedGroups.entries.where((e) => e.value).map((e) => e.key).toList();
                                        storage.saveCollapsedCategoryIds(collapsedKeys);
                                      });
                                    },
                                    onLongPress: _viewMode == DailyViewMode.customCategories
                                        ? () {
                                            setState(() {
                                              _activeCategoryActionId = (_activeCategoryActionId == parentId ? null : parentId);
                                            });
                                          }
                                        : null,
                                    borderRadius: BorderRadius.circular(12),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                                      child: Row(
                                        children: [
                                          // Category Priority Badge (P1, P2...)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            margin: const EdgeInsets.only(right: 6),
                                            decoration: BoxDecoration(
                                              color: _getPriorityColor(categoryPriority).withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              'P$categoryPriority',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: _getPriorityColor(categoryPriority),
                                              ),
                                            ),
                                          ),
                                          Icon(groupIcon, color: isAllCompleted ? Colors.green : groupColor, size: 20),
                                          const SizedBox(width: 8),
                                          // Category Name - Maximized space, up to 2 lines
                                          Expanded(
                                            child: Text(
                                              groupTitle,
                                              style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.bold,
                                                color: isAllCompleted ? Colors.green : groupColor,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          // Add task directly to this category (Compact)
                                          IconButton(
                                            icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
                                            color: groupColor,
                                            tooltip: 'Add Task to $groupTitle',
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                                            onPressed: () => _addTaskToCategory(context, parentId, notifier),
                                          ),

                                          // Edit & Delete buttons: ONLY displayed when category is pressed and held!
                                          if (isActionActive && _viewMode == DailyViewMode.customCategories) ...[
                                            IconButton(
                                              icon: const Icon(Icons.edit_outlined, size: 18),
                                              color: groupColor,
                                              tooltip: 'Rename Category',
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                              onPressed: () {
                                                if (matchingDailyCat != null) {
                                                  _showRenameCategoryDialog(context, matchingDailyCat);
                                                } else if (parentId == 'UNGROUPED_TODOS') {
                                                  _showRenameUngroupedDialog(context);
                                                }
                                              },
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.delete_outline_rounded, size: 18),
                                              color: Colors.redAccent.withValues(alpha: 0.9),
                                              tooltip: 'Delete Category',
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                              onPressed: () {
                                                if (matchingDailyCat != null) {
                                                  _showDeleteSingleCategoryConfirmDialog(
                                                    context,
                                                    matchingDailyCat,
                                                    groupTasks,
                                                    notifier,
                                                  );
                                                } else if (parentId == 'UNGROUPED_TODOS') {
                                                  _showDeleteUngroupedConfirmDialog(context);
                                                }
                                              },
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                                              color: AppTheme.textSecondary,
                                              tooltip: 'Done',
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                              onPressed: () {
                                                setState(() => _activeCategoryActionId = null);
                                              },
                                            ),
                                          ],

                                          const SizedBox(width: 4),
                                          Text(
                                            '$completedCount/${groupTasks.length}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: isAllCompleted ? Colors.green : AppTheme.textSecondary,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Icon(
                                            isCollapsed
                                                ? Icons.keyboard_arrow_right_rounded
                                                : Icons.keyboard_arrow_down_rounded,
                                            color: isAllCompleted ? Colors.green : groupColor,
                                            size: 22,
                                          ),
                                          const SizedBox(width: 8),
                                          ReorderableDragStartListener(
                                            index: index,
                                            child: const Tooltip(
                                              message: 'Drag to reorder category priority',
                                              child: Icon(
                                                Icons.drag_indicator_rounded,
                                                color: AppTheme.textSecondary,
                                                size: 20,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),

                              if (!isCollapsed) ...[
                                const SizedBox(height: 12),
                                const Divider(height: 1, color: Color(0xFF334155)),
                                const SizedBox(height: 12),

                                if (groupTasks.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Text(
                                          'No tasks in this category today',
                                          style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                                        ),
                                        const SizedBox(width: 8),
                                        TextButton.icon(
                                          icon: const Icon(Icons.add, size: 16),
                                          label: const Text('Add Task', style: TextStyle(fontSize: 12)),
                                          onPressed: () => _addTaskToCategory(context, parentId, notifier),
                                        ),
                                      ],
                                    ),
                                  )
                                else ...[
                                  () {
                                    final habitsCount = groupTasks.where((i) => i.type == NeuroItemType.routine).length;
                                    final tasksCount = groupTasks.where((i) => i.type == NeuroItemType.task).length;
                                    if (habitsCount > 0 && tasksCount > 0) {
                                      final currentFilter = _categoryItemTypeFilters[parentId] ?? 'all';
                                      return Padding(
                                        padding: const EdgeInsets.only(bottom: 8.0),
                                        child: SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          child: Row(
                                            children: [
                                              _buildCategoryTypeChip(
                                                label: 'All (${groupTasks.length})',
                                                isSelected: currentFilter == 'all',
                                                onTap: () => setState(() => _categoryItemTypeFilters[parentId] = 'all'),
                                              ),
                                              const SizedBox(width: 6),
                                              _buildCategoryTypeChip(
                                                label: 'Habits ($habitsCount)',
                                                isSelected: currentFilter == 'habits',
                                                color: AppTheme.routineAccent,
                                                onTap: () => setState(() => _categoryItemTypeFilters[parentId] = 'habits'),
                                              ),
                                              const SizedBox(width: 6),
                                              _buildCategoryTypeChip(
                                                label: 'Tasks ($tasksCount)',
                                                isSelected: currentFilter == 'tasks',
                                                color: AppTheme.secondaryAccent,
                                                onTap: () => setState(() => _categoryItemTypeFilters[parentId] = 'tasks'),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    }
                                    return const SizedBox.shrink();
                                  }(),
                                  () {
                                    final currentFilter = _categoryItemTypeFilters[parentId] ?? 'all';
                                    final displayTasks = groupTasks.where((item) {
                                      if (currentFilter == 'habits') return item.type == NeuroItemType.routine;
                                      if (currentFilter == 'tasks') return item.type == NeuroItemType.task;
                                      return true;
                                    }).toList();

                                    return ReorderableListView.builder(
                                      shrinkWrap: true,
                                      physics: const NeverScrollableScrollPhysics(),
                                      buildDefaultDragHandles: false,
                                      itemCount: displayTasks.length,
                                      onReorder: (oldItemIndex, newItemIndex) {
                                        setState(() {
                                          if (newItemIndex > oldItemIndex) newItemIndex -= 1;
                                          final moved = displayTasks.removeAt(oldItemIndex);
                                          displayTasks.insert(newItemIndex, moved);
                                          notifier.reorderTasks(displayTasks, date: _selectedDate);
                                        });
                                      },
                                      itemBuilder: (context, itemIndex) {
                                        final item = displayTasks[itemIndex];
                                        return _DailyTrackItemTile(
                                          key: ValueKey('group_${parentId}_item_${item.id}'),
                                          item: item,
                                          itemIndex: itemIndex,
                                          selectedDate: _selectedDate,
                                          notifier: notifier,
                                          allItems: allItems,
                                          dailyCategories: dailyCategories,
                                          isCustomCategoryMode: _viewMode == DailyViewMode.customCategories,
                                          isChecklistExpanded: _expandedChecklistItems.contains(item.id),
                                          onToggleChecklistExpanded: () => _toggleChecklistExpanded(item.id),
                                        );
                                      },
                                    );
                                  }(),
                                ],
                              ],
                            ],
                          ),
                        );

                        if (_viewMode == DailyViewMode.customCategories) {
                          return DragTarget<NeuroItem>(
                            key: ValueKey('drag_target_$parentId'),
                            onWillAcceptWithDetails: (details) => true,
                            onAcceptWithDetails: (details) {
                              final droppedItem = details.data;
                              if (matchingDailyCat != null) {
                                notifier.updateItem(droppedItem.copyWith(dailyCategoryId: matchingDailyCat.id));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Moved "${droppedItem.title}" to ${matchingDailyCat.name}'),
                                    duration: const Duration(seconds: 1),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              } else if (parentId == 'UNGROUPED_TODOS') {
                                notifier.updateItem(droppedItem.copyWith(clearDailyCategoryId: true));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Moved "${droppedItem.title}" to Ungrouped Tasks'),
                                    duration: const Duration(seconds: 1),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            },
                            builder: (context, candidateData, rejectedData) {
                              return categoryCardContent(candidateData.isNotEmpty);
                            },
                          );
                        }

                        return categoryCardContent(false);
                      },
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_viewMode == DailyViewMode.customCategories) ...[
            FloatingActionButton.extended(
              heroTag: 'add_category_btn',
              backgroundColor: AppTheme.routineAccent,
              icon: const Icon(Icons.create_new_folder_outlined, color: AppTheme.backgroundColor, size: 20),
              label: const Text(
                '+ Category',
                style: TextStyle(color: AppTheme.backgroundColor, fontWeight: FontWeight.bold),
              ),
              onPressed: () => _showCreateCategoryDialog(context),
            ),
            const SizedBox(width: 10),
          ],
          FloatingActionButton.extended(
            heroTag: 'add_task_btn',
            backgroundColor: AppTheme.primaryAccent,
            icon: const Icon(Icons.add, color: AppTheme.backgroundColor),
            label: const Text(
              'Add Task',
              style: TextStyle(color: AppTheme.backgroundColor, fontWeight: FontWeight.bold),
            ),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => UnifiedStepperDialog(
                  title: 'Add Daily Task',
                  isFolder: false,
                  initialDate: _selectedDate,
                  onSave: (newItem) {
                    notifier.addItem(
                      title: newItem.title,
                      description: newItem.description,
                      type: newItem.type,
                      parentId: null, // Defaults to To-Do List
                      rootVisionId: null,
                      targetDate: newItem.targetDate ?? _selectedDate,
                      targetTime: newItem.targetTime,
                      routineCategory: newItem.routineCategory,
                      completionType: newItem.completionType,
                      targetNumericValue: newItem.targetNumericValue,
                      timerDurationSeconds: newItem.timerDurationSeconds,
                      scheduleType: newItem.scheduleType,
                      selectedDaysOfWeek: newItem.selectedDaysOfWeek,
                      selectedDaysOfMonth: newItem.selectedDaysOfMonth,
                      selectedDaysOfYear: newItem.selectedDaysOfYear,
                      repeatIntervalDays: newItem.repeatIntervalDays,
                      isFlexibleCarryover: newItem.isFlexibleCarryover,
                      isPendingCarryover: newItem.isPendingCarryover,
                      priority: newItem.priority,
                      checklist: newItem.checklist,
                      successContributesToProgress: newItem.successContributesToProgress,
                      failureContributesToProgress: newItem.failureContributesToProgress,
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showCreateCategoryDialog(BuildContext context, {NeuroItem? initialItem}) {
    final nameController = TextEditingController();
    int selectedColor = 0xFF38BDF8;
    final colors = [
      0xFF38BDF8,
      0xFF4ADE80,
      0xFFFBBF24,
      0xFFF472B6,
      0xFFA78BFA,
      0xFF2DD4BF,
    ];

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppTheme.surfaceColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text(
                initialItem != null
                    ? 'Create Category for "${initialItem.title}"'
                    : 'Create Category',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Category Name',
                      hintText: 'e.g. Work, Wellness, Study...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Category Color', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: colors.map((c) {
                      final isSelected = selectedColor == c;
                      return GestureDetector(
                        onTap: () => setDialogState(() => selectedColor = c),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Color(c),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected ? Colors.white : Colors.transparent,
                              width: 2.5,
                            ),
                          ),
                          child: isSelected ? const Icon(Icons.check, size: 16, color: Colors.black87) : null,
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Color(selectedColor)),
                  onPressed: () {
                    final name = nameController.text.trim();
                    if (name.isNotEmpty) {
                      final newCat = DailyCategory(
                        id: DateTime.now().millisecondsSinceEpoch.toString(),
                        name: name,
                        colorHex: selectedColor,
                      );
                      ref.read(dailyCategoriesProvider.notifier).addCategory(newCat);
                      if (initialItem != null) {
                        ref.read(neuroItemsProvider.notifier).updateItem(
                          initialItem.copyWith(dailyCategoryId: newCat.id),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Created category "$name" and added "${initialItem.title}"'),
                            duration: const Duration(seconds: 2),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                      if (_isUngroupedCategoryDeleted) {
                        ref.read(storageServiceProvider).saveIsUngroupedCategoryDeleted(false);
                      }
                      setState(() {
                        _isUngroupedCategoryDeleted = false;
                        if (!_categoryKeysOrder.contains(newCat.id)) {
                          _categoryKeysOrder.insert(0, newCat.id);
                        }
                      });
                      Navigator.pop(context);
                    }
                  },
                  child: const Text('Create', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildCreateCategoryDropTarget(BuildContext context) {
    return DragTarget<NeuroItem>(
      key: const ValueKey('CREATE_CATEGORY_DROP_TARGET_KEY'),
      onWillAcceptWithDetails: (details) => true,
      onAcceptWithDetails: (details) {
        final droppedItem = details.data;
        _showCreateCategoryDialog(context, initialItem: droppedItem);
      },
      builder: (context, candidateData, rejectedData) {
        final isHovered = candidateData.isNotEmpty;
        return Container(
          margin: const EdgeInsets.only(bottom: 24.0, top: 4.0),
          child: InkWell(
            onTap: () => _showCreateCategoryDialog(context),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              decoration: BoxDecoration(
                color: isHovered
                    ? AppTheme.routineAccent.withValues(alpha: 0.2)
                    : AppTheme.surfaceColor.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isHovered
                      ? AppTheme.routineAccent
                      : const Color(0xFF334155),
                  width: isHovered ? 2.0 : 1.2,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.create_new_folder_outlined,
                    color: isHovered ? Colors.white : AppTheme.routineAccent,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isHovered
                        ? 'Drop here to create category with this task'
                        : '+ Drag item here to create category • or tap to add',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isHovered ? Colors.white : AppTheme.textSecondary,
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

  void _addTaskToCategory(BuildContext context, String categoryKey, NeuroItemsNotifier notifier) {
    final allItems = ref.read(neuroItemsProvider);
    final isDailyCat = ref.read(dailyCategoriesProvider).any((c) => c.id == categoryKey);
    final parentItem = isDailyCat ? null : allItems.where((c) => c.id == categoryKey).firstOrNull;

    final resolvedParentId = isDailyCat ? null : (categoryKey == 'UNGROUPED_TODOS' ? null : categoryKey);
    final resolvedRootVisionId = parentItem != null
        ? (parentItem.rootVisionId ?? (parentItem.type == NeuroItemType.vision ? parentItem.id : null))
        : null;

    showDialog(
      context: context,
      builder: (context) => UnifiedStepperDialog(
        title: parentItem != null ? 'Add to ${parentItem.title}' : 'Add Task to Category',
        isFolder: false,
        initialDate: _selectedDate,
        onSave: (newItem) {
          notifier.addItem(
            title: newItem.title,
            description: newItem.description,
            type: (parentItem != null && parentItem.type == NeuroItemType.routineFolder && newItem.type == NeuroItemType.task)
                ? NeuroItemType.routine
                : newItem.type,
            parentId: resolvedParentId,
            dailyCategoryId: isDailyCat ? categoryKey : null,
            rootVisionId: resolvedRootVisionId,
            targetDate: newItem.targetDate ?? _selectedDate,
            targetTime: newItem.targetTime,
            routineCategory: newItem.routineCategory,
            completionType: newItem.completionType,
            targetNumericValue: newItem.targetNumericValue,
            timerDurationSeconds: newItem.timerDurationSeconds,
            scheduleType: newItem.scheduleType,
            selectedDaysOfWeek: newItem.selectedDaysOfWeek,
            selectedDaysOfMonth: newItem.selectedDaysOfMonth,
            selectedDaysOfYear: newItem.selectedDaysOfYear,
            repeatIntervalDays: newItem.repeatIntervalDays,
            isFlexibleCarryover: newItem.isFlexibleCarryover,
            isPendingCarryover: newItem.isPendingCarryover,
            priority: newItem.priority,
            checklist: newItem.checklist,
            successContributesToProgress: newItem.successContributesToProgress,
            failureContributesToProgress: newItem.failureContributesToProgress,
          );
        },
      ),
    );
  }

  void _showRenameCategoryDialog(BuildContext context, DailyCategory category) {
    final nameController = TextEditingController(text: category.name);
    int selectedColor = category.colorHex ?? 0xFF00E5FF;
    final colors = [
      0xFF00E5FF,
      0xFFB388FF,
      0xFF69F0AE,
      0xFFFFD740,
      0xFFFF5252,
      0xFFFF4081,
      0xFF448AFF,
      0xFFA78BFA,
      0xFF2DD4BF,
    ];

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppTheme.surfaceColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text('Rename Category', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Category Name',
                      hintText: 'e.g. Work, Wellness, Study...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Category Color', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: colors.map((c) {
                      final isSelected = selectedColor == c;
                      return GestureDetector(
                        onTap: () => setDialogState(() => selectedColor = c),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Color(c),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected ? Colors.white : Colors.transparent,
                              width: 2.5,
                            ),
                          ),
                          child: isSelected ? const Icon(Icons.check, size: 16, color: Colors.black87) : null,
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Color(selectedColor)),
                  onPressed: () {
                    final name = nameController.text.trim();
                    if (name.isNotEmpty) {
                      ref.read(dailyCategoriesProvider.notifier).updateCategory(
                            category.copyWith(name: name, colorHex: selectedColor),
                          );
                      Navigator.pop(context);
                    }
                  },
                  child: const Text('Save', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showDeleteSingleCategoryConfirmDialog(
    BuildContext context,
    DailyCategory category,
    List<NeuroItem> groupTasks,
    NeuroItemsNotifier notifier,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete "${category.name}"?', style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(
          'Are you sure you want to delete this category? The ${groupTasks.length} task(s) inside will become ungrouped, but will NOT be deleted.',
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              for (final item in groupTasks) {
                notifier.updateItem(item.copyWith(clearDailyCategoryId: true));
              }
              ref.read(dailyCategoriesProvider.notifier).deleteCategory(category.id);
              setState(() {
                _categoryKeysOrder.remove(category.id);
              });
              Navigator.pop(context);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showDeleteAllCategoriesDialog(BuildContext context, NeuroItemsNotifier notifier) {
    final dailyCategories = ref.read(dailyCategoriesProvider);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete All Categories?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text(
          'Are you sure you want to delete all ${dailyCategories.length} custom categories? All tasks will become ungrouped, but no tasks or habits will be deleted.',
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              final allItems = ref.read(neuroItemsProvider);
              for (final item in allItems.where((i) => i.dailyCategoryId != null)) {
                notifier.updateItem(item.copyWith(clearDailyCategoryId: true));
              }
              ref.read(dailyCategoriesProvider.notifier).deleteAllCategories();
              setState(() {
                _categoryKeysOrder.removeWhere((k) => k != 'UNGROUPED_TODOS');
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('All custom categories deleted. Tasks ungrouped.'),
                  duration: Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: const Text('Delete All', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showRenameUngroupedDialog(BuildContext context) {
    final nameController = TextEditingController(text: _customUngroupedName);
    int selectedColor = _customUngroupedColor ?? 0xFF00E5FF;
    final colors = [
      0xFF00E5FF,
      0xFFB388FF,
      0xFF69F0AE,
      0xFFFFD740,
      0xFFFF5252,
      0xFFFF4081,
      0xFF448AFF,
      0xFFA78BFA,
      0xFF2DD4BF,
    ];

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppTheme.surfaceColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text('Rename Ungrouped Tasks', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Category Name',
                      hintText: 'e.g. Inbox, General, Quick Tasks...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Category Color', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: colors.map((c) {
                      final isSelected = selectedColor == c;
                      return GestureDetector(
                        onTap: () => setDialogState(() => selectedColor = c),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Color(c),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected ? Colors.white : Colors.transparent,
                              width: 2.5,
                            ),
                          ),
                          child: isSelected ? const Icon(Icons.check, size: 16, color: Colors.black87) : null,
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Color(selectedColor)),
                  onPressed: () {
                    final name = nameController.text.trim();
                    if (name.isNotEmpty) {
                      final storage = ref.read(storageServiceProvider);
                      storage.saveCustomUngroupedName(name);
                      storage.saveCustomUngroupedColor(selectedColor);
                      setState(() {
                        _customUngroupedName = name;
                        _customUngroupedColor = selectedColor;
                        _activeCategoryActionId = null;
                      });
                      Navigator.pop(context);
                    }
                  },
                  child: const Text('Save', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showDeleteUngroupedConfirmDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Ungrouped Category?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text(
          'Tasks will not be deleted. All items will be displayed directly as a list until you create custom categories.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              final storage = ref.read(storageServiceProvider);
              storage.saveIsUngroupedCategoryDeleted(true);
              setState(() {
                _isUngroupedCategoryDeleted = true;
                _activeCategoryActionId = null;
                _categoryKeysOrder.remove('UNGROUPED_TODOS');
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Ungrouped category deleted. Items displayed as a list.'),
                  duration: Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildFlatTaskList(
    BuildContext context,
    List<NeuroItem> dailyItems,
    NeuroItemsNotifier notifier,
    List<NeuroItem> allItems,
    List<DailyCategory> dailyCategories, {
    bool isPriorityListMode = false,
  }) {
    final sortedItems = List<NeuroItem>.from(dailyItems);
    sortedItems.sort((a, b) {
      final aDone = a.isCompletedOnDate(_selectedDate) || a.isFailedOnDate(_selectedDate);
      final bDone = b.isCompletedOnDate(_selectedDate) || b.isFailedOnDate(_selectedDate);
      if (aDone != bDone) {
        return aDone ? 1 : -1;
      }
      return a.priority.compareTo(b.priority);
    });

    return ReorderableListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      buildDefaultDragHandles: false,
      itemCount: sortedItems.length,
      footer: (!isPriorityListMode && _viewMode == DailyViewMode.customCategories)
          ? _buildCreateCategoryDropTarget(context)
          : null,
      onReorder: (oldIndex, newIndex) {
        setState(() {
          if (newIndex > oldIndex) newIndex -= 1;
          final moved = sortedItems.removeAt(oldIndex);
          sortedItems.insert(newIndex, moved);
          notifier.reorderTasks(sortedItems, date: _selectedDate);
        });
      },
      itemBuilder: (context, index) {
        final item = sortedItems[index];
        return _DailyTrackItemTile(
          key: ValueKey('flat_item_${item.id}'),
          item: item,
          itemIndex: index,
          selectedDate: _selectedDate,
          notifier: notifier,
          allItems: allItems,
          dailyCategories: dailyCategories,
          isCustomCategoryMode: !isPriorityListMode && _viewMode == DailyViewMode.customCategories,
          isChecklistExpanded: _expandedChecklistItems.contains(item.id),
          onToggleChecklistExpanded: () => _toggleChecklistExpanded(item.id),
        );
      },
    );
  }

  Widget _buildCategoryTypeChip({
    required String label,
    required bool isSelected,
    Color color = AppTheme.primaryAccent,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.2) : AppTheme.surfaceColor,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? color : const Color(0xFF334155),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildAccountSyncButton(BuildContext context) {
    final user = ref.watch(authNotifierProvider);
    final syncStatusAsync = ref.watch(syncStatusProvider);
    final syncStatus = syncStatusAsync.value ?? SyncStatus.synced;

    Color badgeColor;
    switch (syncStatus) {
      case SyncStatus.synced:
        badgeColor = const Color(0xFF4ADE80);
        break;
      case SyncStatus.syncing:
        badgeColor = AppTheme.primaryAccent;
        break;
      case SyncStatus.offline:
        badgeColor = const Color(0xFFFBBF24);
        break;
      case SyncStatus.error:
        badgeColor = Colors.orangeAccent;
        break;
    }

    final isGuest = user == null || user.isGuest;
    final initials = user != null && user.displayName.isNotEmpty
        ? user.displayName[0].toUpperCase()
        : 'G';

    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: InkWell(
        onTap: () => AccountSyncDialog.show(context),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(6.0),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: isGuest
                    ? AppTheme.textSecondary.withValues(alpha: 0.25)
                    : AppTheme.primaryAccent.withValues(alpha: 0.25),
                child: isGuest
                    ? const Icon(Icons.person_outline_rounded, size: 16, color: AppTheme.textSecondary)
                    : Text(
                        initials,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryAccent,
                        ),
                      ),
              ),
              Positioned(
                right: -1,
                bottom: -1,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: badgeColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.surfaceColor, width: 1.5),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRollingCalendarHeader() {
    return Container(
      height: 85,
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      decoration: const BoxDecoration(
        color: AppTheme.surfaceColor,
        border: Border(
          bottom: BorderSide(color: Color(0xFF334155), width: 1),
        ),
      ),
      child: ListView.builder(
        controller: _calendarScrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12.0),
        itemCount: _kCalendarTotalDays,
        itemBuilder: (context, index) {
          final date = _today.add(Duration(days: index - _kCalendarCenterIndex));
          final isSelected = date.year == _selectedDate.year &&
              date.month == _selectedDate.month &&
              date.day == _selectedDate.day;
          final isToday = date.year == _today.year &&
              date.month == _today.month &&
              date.day == _today.day;

          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedDate = date;
              });
              _centerDateInCalendar(date, animate: true);
            },
            child: Container(
              width: 54,
              margin: const EdgeInsets.symmetric(horizontal: 4.0),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppTheme.primaryAccent
                    : (isToday
                        ? AppTheme.primaryAccent.withValues(alpha: 0.15)
                        : AppTheme.backgroundColor),
                borderRadius: BorderRadius.circular(16),
                border: isToday && !isSelected
                    ? Border.all(color: AppTheme.primaryAccent, width: 1.5)
                    : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    DateFormat('E').format(date).toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? AppTheme.backgroundColor : AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('d').format(date),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? AppTheme.backgroundColor : AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Ultra-Compact Daily Execution Item Tile with Date-Scoped Controls & Sub-Checklist Progress
class _DailyTrackItemTile extends StatefulWidget {
  final NeuroItem item;
  final int itemIndex;
  final DateTime selectedDate;
  final NeuroItemsNotifier notifier;
  final List<NeuroItem> allItems;
  final List<DailyCategory> dailyCategories;
  final bool isCustomCategoryMode;
  final bool isChecklistExpanded;
  final VoidCallback? onToggleChecklistExpanded;

  const _DailyTrackItemTile({
    super.key,
    required this.item,
    required this.itemIndex,
    required this.selectedDate,
    required this.notifier,
    required this.allItems,
    required this.dailyCategories,
    this.isCustomCategoryMode = false,
    this.isChecklistExpanded = false,
    this.onToggleChecklistExpanded,
  });

  @override
  State<_DailyTrackItemTile> createState() => _DailyTrackItemTileState();
}

class _DailyTrackItemTileState extends State<_DailyTrackItemTile> {
  Timer? _timer;
  int _elapsedSeconds = 0;
  bool _isTimerRunning = false;

  @override
  void initState() {
    super.initState();
    if (widget.item.completionType == RoutineCompletionType.timer) {
      _elapsedSeconds = widget.item.getNumericValueForDate(widget.selectedDate).toInt();
    }
  }

  @override
  void didUpdateWidget(covariant _DailyTrackItemTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isTimerRunning && widget.item.completionType == RoutineCompletionType.timer) {
      _elapsedSeconds = widget.item.getNumericValueForDate(widget.selectedDate).toInt();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_isTimerRunning && widget.item.completionType == RoutineCompletionType.timer) {
      widget.notifier.updateNumericProgress(widget.item.id, _elapsedSeconds.toDouble(), date: widget.selectedDate);
    }
    super.dispose();
  }

  void _toggleTimer() {
    if (_isTimerRunning) {
      _timer?.cancel();
      setState(() => _isTimerRunning = false);
      widget.notifier.updateNumericProgress(widget.item.id, _elapsedSeconds.toDouble(), date: widget.selectedDate);
    } else {
      setState(() => _isTimerRunning = true);
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() {
          _elapsedSeconds++;
          final targetSeconds = widget.item.timerDurationSeconds ?? 600;
          if (_elapsedSeconds >= targetSeconds) {
            _timer?.cancel();
            _isTimerRunning = false;
            widget.notifier.updateNumericProgress(widget.item.id, targetSeconds.toDouble(), date: widget.selectedDate);
            widget.notifier.toggleCompletionForDate(widget.item.id, widget.selectedDate);
          } else if (_elapsedSeconds % 5 == 0) {
            widget.notifier.updateNumericProgress(widget.item.id, _elapsedSeconds.toDouble(), date: widget.selectedDate);
          }
        });
      });
    }
  }

  void _showDirectNumericInputPrompt(double currentVal) {
    final controller = TextEditingController(text: currentVal.toInt().toString());
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: Text('Enter Value for "${widget.item.title}"', style: const TextStyle(fontSize: 15)),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Numeric Value',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryAccent),
            onPressed: () {
              final val = double.tryParse(controller.text.trim());
              if (val != null) {
                widget.notifier.updateNumericProgress(widget.item.id, val, date: widget.selectedDate);
              }
              Navigator.pop(context);
            },
            child: const Text('Set'),
          ),
        ],
      ),
    );
  }

  void _showAssignCategoryDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppTheme.surfaceColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Assign to Category', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                ListTile(
                  leading: const Icon(Icons.clear_all_rounded, color: AppTheme.textSecondary),
                  title: const Text('None (Daily To-Dos)'),
                  trailing: (widget.item.dailyCategoryId == null && widget.item.parentId == null)
                      ? const Icon(Icons.check, color: AppTheme.primaryAccent)
                      : null,
                  onTap: () {
                    widget.notifier.updateItem(widget.item.copyWith(
                      clearDailyCategoryId: true,
                      clearParentId: true,
                    ));
                    Navigator.pop(context);
                  },
                ),
                if (widget.dailyCategories.isNotEmpty) ...[
                  const Divider(color: Color(0xFF334155)),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4.0, horizontal: 16.0),
                    child: Text('Daily Categories', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary, fontWeight: FontWeight.bold)),
                  ),
                  ...widget.dailyCategories.map((cat) {
                    final isSelected = widget.item.dailyCategoryId == cat.id;
                    return ListTile(
                      leading: Icon(Icons.label_rounded, color: cat.colorHex != null ? Color(cat.colorHex!) : AppTheme.secondaryAccent),
                      title: Text(cat.name),
                      trailing: isSelected ? const Icon(Icons.check, color: AppTheme.primaryAccent) : null,
                      onTap: () {
                        widget.notifier.updateItem(widget.item.copyWith(
                          dailyCategoryId: cat.id,
                        ));
                        Navigator.pop(context);
                      },
                    );
                  }),
                ],
                const Divider(color: Color(0xFF334155)),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4.0, horizontal: 16.0),
                  child: Text('Folders / Visions', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary, fontWeight: FontWeight.bold)),
                ),
                ...widget.allItems
                    .where((i) => i.type == NeuroItemType.routineFolder || i.type == NeuroItemType.vision)
                    .map((folder) {
                  final isSelected = widget.item.parentId == folder.id && widget.item.dailyCategoryId == null;
                  return ListTile(
                    leading: Icon(
                      folder.type == NeuroItemType.vision ? Icons.account_tree_outlined : Icons.folder_special_rounded,
                      color: folder.type == NeuroItemType.vision ? AppTheme.primaryAccent : AppTheme.routineAccent,
                    ),
                    title: Text(folder.title),
                    trailing: isSelected ? const Icon(Icons.check, color: AppTheme.primaryAccent) : null,
                    onTap: () {
                      widget.notifier.updateItem(widget.item.copyWith(
                        parentId: folder.id,
                        clearDailyCategoryId: true,
                      ));
                      Navigator.pop(context);
                    },
                  );
                }),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final eval = AggregationEngine.evaluateItemStatusOnDate(item, widget.selectedDate);
    final isCompleted = eval.status == TaskEvaluationStatus.success;
    final isFailed = eval.status == TaskEvaluationStatus.failure && item.isFailedOnDate(widget.selectedDate);
    final isPartiallyCompleted = eval.status == TaskEvaluationStatus.partiallyCompleted;
    final partialFraction = eval.progressFraction;
    final isGreyedOut = isCompleted || isFailed;

    // Sub-checklist stats (date-scoped)
    final hasChecklist = item.checklist.isNotEmpty;
    final completedSubCount = item.getChecklistCompletedCountForDate(widget.selectedDate);
    final totalSubCount = item.checklist.length;

    final hasSecondaryRow = hasChecklist ||
        item.completionType == RoutineCompletionType.numeric ||
        item.completionType == RoutineCompletionType.timer ||
        isFailed ||
        item.isPendingCarryover ||
        item.isFlexibleCarryover ||
        isPartiallyCompleted;

    return GestureDetector(
      onTap: hasChecklist
          ? () {
              widget.onToggleChecklistExpanded?.call();
            }
          : null,
      onLongPress: () {
        UnifiedOptionsBottomSheet.show(
          context: context,
          title: item.title,
          subtitle: 'Daily Tracked Item',
          onEdit: () {
            showDialog(
              context: context,
              builder: (context) => UnifiedStepperDialog(
                title: 'Edit Item',
                isFolder: false,
                existingItem: item,
                onSave: (updated) => widget.notifier.updateItem(updated),
              ),
            );
          },
          onDelete: () => widget.notifier.deleteItem(item.id),
          onToggleFailed: () => widget.notifier.toggleFailedForDate(item.id, widget.selectedDate),
          onResetToUnmarked: () {
            widget.notifier.resetItemForDate(item.id, widget.selectedDate);
            ScaffoldMessenger.of(context).removeCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('"${item.title}" reset to unmarked'),
                duration: const Duration(seconds: 1),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
          onInsights: () => ItemInsightsBottomSheet.show(
            context,
            item: item,
            allItems: widget.allItems,
          ),
          onMoveToCategory: () => _showAssignCategoryDialog(context),
          isFailed: isFailed,
        );
      },
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 250),
        opacity: isGreyedOut ? 0.55 : 1.0,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10.0),
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
          decoration: BoxDecoration(
            color: AppTheme.backgroundColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isCompleted
                  ? Colors.green.withValues(alpha: 0.35)
                  : (isFailed
                      ? Colors.redAccent.withValues(alpha: 0.45)
                      : (isPartiallyCompleted
                          ? const Color(0xFFFACC15).withValues(alpha: 0.5)
                          : AppTheme.primaryAccent.withValues(alpha: 0.2))),
              width: isFailed || isCompleted || isPartiallyCompleted ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // PRIMARY ROW: Priority Pill, Title (Full Space), Reset, Action Button, Drag Handle
              Row(
                children: [
                  // Priority Pill
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isGreyedOut
                          ? Colors.grey.withValues(alpha: 0.2)
                          : _getPriorityColor(item.priority).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'P${item.priority}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isGreyedOut ? Colors.grey : _getPriorityColor(item.priority),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),

                  // Type Pill (Habit vs Task)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: isGreyedOut
                          ? Colors.grey.withValues(alpha: 0.12)
                          : (item.type == NeuroItemType.routine
                                  ? AppTheme.routineAccent
                                  : AppTheme.secondaryAccent)
                              .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      item.type == NeuroItemType.routine ? 'Habit' : 'Task',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: isGreyedOut
                            ? Colors.grey
                            : (item.type == NeuroItemType.routine
                                ? AppTheme.routineAccent
                                : AppTheme.secondaryAccent),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Title & Target Time (Takes full available width)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isFailed
                                ? Colors.redAccent
                                : (isCompleted ? AppTheme.textSecondary : AppTheme.textPrimary),
                            decoration: isGreyedOut ? TextDecoration.lineThrough : null,
                          ),
                        ),
                        if (item.targetTime != null)
                          Text(
                            item.targetTime!,
                            style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),

                  // RESET TO UNMARKED BUTTON (Visible when Completed, Failed, or Partially Completed)
                  if (isCompleted || isFailed || isPartiallyCompleted) ...[
                    Tooltip(
                      message: 'Reset to Unmarked',
                      child: InkWell(
                        onTap: () {
                          widget.notifier.resetItemForDate(item.id, widget.selectedDate);
                          ScaffoldMessenger.of(context).removeCurrentSnackBar();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('"${item.title}" reset to unmarked'),
                              duration: const Duration(seconds: 1),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.all(4.0),
                          child: Icon(
                            Icons.restart_alt_rounded,
                            size: 19,
                            color: isFailed
                                ? Colors.redAccent.withValues(alpha: 0.85)
                                : (isCompleted
                                    ? Colors.green.withValues(alpha: 0.85)
                                    : const Color(0xFFFACC15).withValues(alpha: 0.85)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],

                  // SINGLE COMPILED ACTION BUTTON (Green = Success, Red = Failure, Yellow = Partial)
                  Tooltip(
                    message: isCompleted
                        ? 'Completed (Tap to Reset to Unmarked)'
                        : (isFailed
                            ? 'Failed (Tap to Reset to Unmarked)'
                            : (isPartiallyCompleted
                                ? '${(partialFraction * 100).toInt()}% Done (Tap: Complete • Hold: Fail)'
                                : 'Tap: Complete • Hold: Mark Failed')),
                    child: GestureDetector(
                      onTap: () {
                        if (isCompleted || isFailed) {
                          widget.notifier.resetItemForDate(item.id, widget.selectedDate);
                        } else {
                          widget.notifier.toggleCompletionForDate(item.id, widget.selectedDate);
                        }
                      },
                      onLongPress: () {
                        if (isFailed) {
                          widget.notifier.resetItemForDate(item.id, widget.selectedDate);
                        } else {
                          widget.notifier.toggleFailedForDate(item.id, widget.selectedDate);
                        }
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isCompleted
                              ? Colors.green
                              : (isFailed
                                  ? Colors.redAccent
                                  : (isPartiallyCompleted
                                      ? const Color(0xFFEAB308)
                                      : AppTheme.surfaceColor)),
                          border: Border.all(
                            color: isCompleted
                                ? Colors.green
                                : (isFailed
                                    ? Colors.redAccent
                                    : (isPartiallyCompleted
                                        ? const Color(0xFFFACC15)
                                        : AppTheme.primaryAccent.withValues(alpha: 0.5))),
                            width: 1.8,
                          ),
                          boxShadow: (isCompleted || isFailed || isPartiallyCompleted)
                              ? [
                                  BoxShadow(
                                    color: (isCompleted
                                            ? Colors.green
                                            : (isFailed ? Colors.redAccent : const Color(0xFFFACC15)))
                                        .withValues(alpha: 0.35),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  )
                                ]
                              : null,
                        ),
                        child: isCompleted
                            ? const Icon(Icons.check_rounded, size: 18, color: Colors.white)
                            : (isFailed
                                ? const Icon(Icons.close_rounded, size: 18, color: Colors.white)
                                : (isPartiallyCompleted
                                    ? Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              value: partialFraction,
                                              strokeWidth: 2.2,
                                              backgroundColor: Colors.white.withValues(alpha: 0.25),
                                              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                                            ),
                                          ),
                                          FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: Text(
                                              '${(partialFraction * 100).toInt()}',
                                              style: const TextStyle(
                                                fontSize: 8,
                                                fontWeight: FontWeight.w900,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ],
                                      )
                                    : const Icon(Icons.circle_outlined, size: 18, color: AppTheme.primaryAccent))),
                      ),
                    ),
                  ),

                  // Combined Priority Reorder & Move to Category handle
                  const SizedBox(width: 4),
                  ReorderableDragStartListener(
                    index: widget.itemIndex,
                    child: Tooltip(
                      message: widget.isCustomCategoryMode
                          ? 'Drag to change priority • Tap to move category'
                          : 'Drag to change priority',
                      child: InkWell(
                        onTap: widget.isCustomCategoryMode
                            ? () => _showAssignCategoryDialog(context)
                            : null,
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2.0, vertical: 4.0),
                          child: Icon(
                            Icons.drag_indicator_rounded,
                            color: widget.isCustomCategoryMode
                                ? AppTheme.routineAccent
                                : AppTheme.textSecondary,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              // SECONDARY ROW: Badges, Sub-checklist Expand/Collapse Chip, Numeric & Timer Controls
              if (hasSecondaryRow) ...[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(left: 32.0),
                  child: Row(
                    children: [
                      // Badges and Checklist Toggle Chip
                      Expanded(
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (isFailed)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.redAccent.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4), width: 0.8),
                                ),
                                child: const Text(
                                  'Failed',
                                  style: TextStyle(fontSize: 9, color: Colors.redAccent, fontWeight: FontWeight.bold),
                                ),
                              ),

                            if (item.isPendingCarryover || item.isFlexibleCarryover)
                              Tooltip(
                                message: 'Carryover Task',
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.purple.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'CO',
                                    style: TextStyle(fontSize: 9, color: Colors.purpleAccent, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),

                            if (isPartiallyCompleted && !hasChecklist)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFACC15).withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: const Color(0xFFFACC15).withValues(alpha: 0.5), width: 0.8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.pie_chart_rounded, size: 10, color: Color(0xFFFACC15)),
                                    const SizedBox(width: 3),
                                    Text(
                                      item.completionType == RoutineCompletionType.numeric && item.targetNumericValue != null
                                          ? '${item.getNumericValueForDate(widget.selectedDate).toInt()}/${item.targetNumericValue!.toInt()} (${(partialFraction * 100).toInt()}%)'
                                          : '${(partialFraction * 100).toInt()}% Done',
                                      style: const TextStyle(
                                        fontSize: 9,
                                        color: Color(0xFFFACC15),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                            // Sub-checklist chip with expand/collapse chevron
                            if (hasChecklist)
                              InkWell(
                                onTap: () {
                                  widget.onToggleChecklistExpanded?.call();
                                },
                                borderRadius: BorderRadius.circular(6),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isPartiallyCompleted
                                        ? const Color(0xFFFACC15).withValues(alpha: 0.18)
                                        : (isCompleted
                                            ? Colors.green.withValues(alpha: 0.15)
                                            : AppTheme.surfaceColor),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: isPartiallyCompleted
                                          ? const Color(0xFFFACC15).withValues(alpha: 0.5)
                                          : (isCompleted ? Colors.green.withValues(alpha: 0.4) : const Color(0xFF334155)),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.checklist_rounded,
                                        size: 11,
                                        color: isPartiallyCompleted
                                            ? const Color(0xFFFACC15)
                                            : (isCompleted ? Colors.greenAccent : AppTheme.textSecondary),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '$completedSubCount/$totalSubCount${isPartiallyCompleted ? ' (${(partialFraction * 100).toInt()}%)' : ''}',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: isPartiallyCompleted
                                              ? const Color(0xFFFACC15)
                                              : (isCompleted ? Colors.greenAccent : AppTheme.textSecondary),
                                        ),
                                      ),
                                      const SizedBox(width: 2),
                                      Icon(
                                        widget.isChecklistExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                                        size: 14,
                                        color: isPartiallyCompleted
                                            ? const Color(0xFFFACC15)
                                            : (isCompleted ? Colors.greenAccent : AppTheme.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),

                      // Right side: Interactive Controls (Numeric stepper or Timer)
                      if (item.completionType == RoutineCompletionType.numeric) ...[
                        const SizedBox(width: 6),
                        _buildCompactNumericControl(item),
                      ],

                      if (item.completionType == RoutineCompletionType.timer) ...[
                        const SizedBox(width: 6),
                        _buildCompactTimerControl(item),
                      ],
                    ],
                  ),
                ),
              ],

              // SUB-CHECKLIST VIEW (Only shown when expanded by user)
              if (hasChecklist && widget.isChecklistExpanded) ...[
                const SizedBox(height: 8),
                const Divider(height: 1, color: Color(0xFF334155)),
                const SizedBox(height: 4),
                ...item.checklist.map((subItem) {
                  final isSubCompleted = item.isChecklistItemCompletedOnDate(subItem.id, widget.selectedDate);
                  return Padding(
                    padding: const EdgeInsets.only(left: 20.0, top: 2.0),
                    child: InkWell(
                      onTap: () {
                        widget.notifier.toggleChecklistItem(item.id, subItem.id, date: widget.selectedDate);
                      },
                      child: Row(
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: Checkbox(
                              value: isSubCompleted,
                              activeColor: AppTheme.primaryAccent,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                              onChanged: (val) {
                                widget.notifier.toggleChecklistItem(item.id, subItem.id, date: widget.selectedDate);
                              },
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              subItem.title,
                              style: TextStyle(
                                fontSize: 11,
                                color: isSubCompleted ? AppTheme.textSecondary : AppTheme.textPrimary,
                                decoration: isSubCompleted ? TextDecoration.lineThrough : null,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Compact Right-Aligned Numeric Control (Date-Scoped & Long-Press to Type Custom Value)
  Widget _buildCompactNumericControl(NeuroItem item) {
    final isBadHabitTracker = (item.targetNumericValue ?? 10) == 0;
    final dateValue = item.getNumericValueForDate(widget.selectedDate);

    return InkWell(
      onLongPress: () => _showDirectNumericInputPrompt(dateValue),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF334155)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: () {
                if (dateValue > 0) {
                  widget.notifier.updateNumericProgress(
                    item.id,
                    dateValue - 1,
                    date: widget.selectedDate,
                  );
                }
              },
              borderRadius: BorderRadius.circular(6),
              child: const Padding(
                padding: EdgeInsets.all(2.0),
                child: Icon(Icons.remove, size: 14, color: AppTheme.textSecondary),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: Text(
                isBadHabitTracker
                    ? '${dateValue.toInt()} times'
                    : '${dateValue.toInt()}/${item.targetNumericValue!.toInt()}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isBadHabitTracker && dateValue > 0
                      ? Colors.orangeAccent
                      : AppTheme.primaryAccent,
                ),
              ),
            ),
            InkWell(
              onTap: () {
                widget.notifier.updateNumericProgress(
                  item.id,
                  dateValue + 1,
                  date: widget.selectedDate,
                );
              },
              borderRadius: BorderRadius.circular(6),
              child: const Padding(
                padding: EdgeInsets.all(2.0),
                child: Icon(Icons.add, size: 14, color: AppTheme.primaryAccent),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Compact Right-Aligned Timer Control
  Widget _buildCompactTimerControl(NeuroItem item) {
    final targetSeconds = item.timerDurationSeconds ?? 600;

    return InkWell(
      onTap: _toggleTimer,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: _isTimerRunning
              ? Colors.orangeAccent.withValues(alpha: 0.15)
              : AppTheme.primaryAccent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _isTimerRunning ? Colors.orangeAccent : AppTheme.primaryAccent,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isTimerRunning ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 14,
              color: _isTimerRunning ? Colors.orangeAccent : AppTheme.primaryAccent,
            ),
            const SizedBox(width: 4),
            Text(
              '${_formatSeconds(_elapsedSeconds)}/${_formatSeconds(targetSeconds)}',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: _isTimerRunning ? Colors.orangeAccent : AppTheme.primaryAccent,
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

  String _formatSeconds(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }
}
