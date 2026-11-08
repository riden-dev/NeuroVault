import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/neuro_item.dart';
import '../../providers/neuro_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/unified_options_bottom_sheet.dart';
import '../widgets/unified_stepper_dialog.dart';

class TodoListScreen extends ConsumerStatefulWidget {
  const TodoListScreen({super.key});

  @override
  ConsumerState<TodoListScreen> createState() => _TodoListScreenState();
}

class _TodoListScreenState extends ConsumerState<TodoListScreen> {
  late DateTime _today;
  DateTime? _selectedDate; // null means "F" (Flexible / No Date) tab is selected

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _today = DateTime(now.year, now.month, now.day);
    _selectedDate = _today;
  }

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(dateTasksProvider(_selectedDate));
    final notifier = ref.read(neuroItemsProvider.notifier);

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Daily To-Do List'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Rolling Calendar Header with Fixed "F" Tab
            _buildRollingCalendarHeader(),

            const SizedBox(height: 12),

            // Date / Tab Subtitle Indicator
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Row(
                children: [
                  Text(
                    _selectedDate == null
                        ? 'Flexible Tasks (No Date)'
                        : DateFormat('EEEE, MMM d, yyyy').format(_selectedDate!),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.secondaryAccent,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${tasks.length} tasks',
                    style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Reorderable Drag & Drop Task List
            Expanded(
              child: tasks.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _selectedDate == null
                                ? Icons.all_inclusive_rounded
                                : Icons.task_alt_rounded,
                            size: 48,
                            color: AppTheme.textSecondary.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _selectedDate == null
                                ? 'No flexible tasks.\nTap + to add a task with no deadline.'
                                : 'No tasks scheduled for this day.\nTap + to create a task.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    )
                  : ReorderableListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      itemCount: tasks.length,
                      onReorder: (oldIndex, newIndex) {
                        if (newIndex > oldIndex) newIndex -= 1;
                        final item = tasks.removeAt(oldIndex);
                        tasks.insert(newIndex, item);
                        notifier.reorderTasks(tasks, date: _selectedDate);
                      },
                      itemBuilder: (context, index) {
                        final task = tasks[index];
                        final isGreyedOut = task.isCompleted;

                        final completedSubCount =
                            task.checklist.where((sub) => sub.isCompleted).length;

                        return Container(
                          key: ValueKey(task.id),
                          margin: const EdgeInsets.only(bottom: 10.0),
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 250),
                            opacity: isGreyedOut ? 0.45 : 1.0,
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onLongPress: () {
                                  UnifiedOptionsBottomSheet.show(
                                    context: context,
                                    title: task.title,
                                    subtitle: 'Daily Task',
                                    onEdit: () {
                                      showDialog(
                                        context: context,
                                        builder: (context) => UnifiedStepperDialog(
                                          title: 'Edit Task',
                                          isFolder: false,
                                          existingItem: task,
                                          onSave: (updated) => notifier.updateItem(updated),
                                        ),
                                      );
                                    },
                                    onDelete: () => notifier.deleteItem(task.id),
                                  );
                                },
                                child: Ink(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: isGreyedOut
                                        ? AppTheme.surfaceColor.withValues(alpha: 0.5)
                                        : AppTheme.surfaceColor,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: isGreyedOut
                                          ? Colors.grey.withValues(alpha: 0.2)
                                          : AppTheme.secondaryAccent.withValues(alpha: 0.2),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Transform.scale(
                                            scale: 1.1,
                                            child: Checkbox(
                                              value: task.isCompleted,
                                              activeColor: AppTheme.secondaryAccent,
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              onChanged: (val) {
                                                notifier.toggleCompletion(task.id);
                                              },
                                            ),
                                          ),
                                          const SizedBox(width: 8),

                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: isGreyedOut
                                                  ? Colors.grey.withValues(alpha: 0.2)
                                                  : _getPriorityColor(task.priority)
                                                      .withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              'P${task.priority}',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: isGreyedOut
                                                    ? Colors.grey
                                                    : _getPriorityColor(task.priority),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),

                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  task.title,
                                                  style: TextStyle(
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w600,
                                                    color: isGreyedOut
                                                        ? AppTheme.textSecondary
                                                        : AppTheme.textPrimary,
                                                    decoration: isGreyedOut
                                                        ? TextDecoration.lineThrough
                                                        : null,
                                                  ),
                                                ),
                                                if (task.description != null &&
                                                    task.description!.isNotEmpty)
                                                  Padding(
                                                    padding: const EdgeInsets.only(top: 2.0),
                                                    child: Text(
                                                      task.description!,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: AppTheme.textSecondary
                                                            .withValues(alpha: 0.8),
                                                      ),
                                                    ),
                                                  ),
                                                const SizedBox(height: 4),
                                                Row(
                                                  children: [
                                                    if (task.targetTime != null) ...[
                                                      const Icon(Icons.access_time_rounded,
                                                          size: 12,
                                                          color: AppTheme.textSecondary),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        task.targetTime!,
                                                        style: const TextStyle(
                                                            fontSize: 11,
                                                            color: AppTheme.textSecondary),
                                                      ),
                                                      const SizedBox(width: 10),
                                                    ],
                                                    if (task.checklist.isNotEmpty) ...[
                                                      Icon(
                                                        Icons.checklist_rounded,
                                                        size: 13,
                                                        color: completedSubCount ==
                                                                task.checklist.length
                                                            ? AppTheme.routineAccent
                                                            : AppTheme.primaryAccent,
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        '$completedSubCount/${task.checklist.length} items',
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          fontWeight: FontWeight.w600,
                                                          color: completedSubCount ==
                                                                  task.checklist.length
                                                              ? AppTheme.routineAccent
                                                              : AppTheme.primaryAccent,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 10),
                                                    ],
                                                    if (task.hasReminder) ...[
                                                      const Icon(
                                                          Icons.notifications_active_outlined,
                                                          size: 12,
                                                          color: AppTheme.primaryAccent),
                                                      const SizedBox(width: 4),
                                                    ],
                                                    if (task.isPendingCarryover &&
                                                        !task.isCompleted) ...[
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(
                                                            horizontal: 6, vertical: 2),
                                                        decoration: BoxDecoration(
                                                          color:
                                                              Colors.purple.withValues(alpha: 0.15),
                                                          borderRadius: BorderRadius.circular(4),
                                                        ),
                                                        child: const Text(
                                                          'Carryover',
                                                          style: TextStyle(
                                                              fontSize: 10,
                                                              color: Colors.purpleAccent,
                                                              fontWeight: FontWeight.bold),
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),

                                          // Explicit Drag Start Handle Listener
                                          ReorderableDragStartListener(
                                            index: index,
                                            child: const Padding(
                                              padding: EdgeInsets.all(8.0),
                                              child: Icon(
                                                Icons.drag_indicator_rounded,
                                                color: AppTheme.textSecondary,
                                                size: 22,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),

                                      if (task.checklist.isNotEmpty) ...[
                                        const SizedBox(height: 8),
                                        const Divider(height: 1, color: Color(0xFF334155)),
                                        const SizedBox(height: 6),
                                        ...task.checklist.map((subItem) => Padding(
                                              padding: const EdgeInsets.only(left: 36.0, top: 2.0),
                                              child: InkWell(
                                                onTap: () {
                                                  notifier.toggleChecklistItem(
                                                      task.id, subItem.id);
                                                },
                                                borderRadius: BorderRadius.circular(8),
                                                child: Row(
                                                  children: [
                                                    SizedBox(
                                                      width: 24,
                                                      height: 24,
                                                      child: Checkbox(
                                                        value: subItem.isCompleted,
                                                        activeColor: AppTheme.primaryAccent,
                                                        shape: RoundedRectangleBorder(
                                                          borderRadius: BorderRadius.circular(4),
                                                        ),
                                                        onChanged: (val) {
                                                          notifier.toggleChecklistItem(
                                                              task.id, subItem.id);
                                                        },
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: Text(
                                                        subItem.title,
                                                        style: TextStyle(
                                                          fontSize: 13,
                                                          color: subItem.isCompleted
                                                              ? AppTheme.textSecondary
                                                              : AppTheme.textPrimary,
                                                          decoration: subItem.isCompleted
                                                              ? TextDecoration.lineThrough
                                                              : null,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            )),
                                      ],
                                    ],
                                  ),
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
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.secondaryAccent,
        icon: const Icon(Icons.add, color: AppTheme.backgroundColor),
        label: const Text(
          'New Task',
          style: TextStyle(color: AppTheme.backgroundColor, fontWeight: FontWeight.bold),
        ),
        onPressed: () {
          showDialog(
            context: context,
            builder: (context) => UnifiedStepperDialog(
              title: 'Create Daily Task',
              isFolder: false,
              initialDate: _selectedDate,
              onSave: (item) {
                notifier.addItem(
                  title: item.title,
                  description: item.description,
                  type: NeuroItemType.task,
                  targetDate: _selectedDate,
                  targetTime: item.targetTime,
                  hasReminder: item.hasReminder,
                  priority: item.priority,
                  isPendingCarryover: item.isPendingCarryover,
                  isFlexibleCarryover: item.isFlexibleCarryover,
                  checklist: item.checklist,
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildRollingCalendarHeader() {
    final dateList = List.generate(22, (i) => _today.add(Duration(days: i - 7)));

    return Container(
      height: 85,
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      decoration: const BoxDecoration(
        color: AppTheme.surfaceColor,
        border: Border(
          bottom: BorderSide(color: Color(0xFF334155), width: 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              itemCount: dateList.length,
              itemBuilder: (context, index) {
                final date = dateList[index];
                final isSelected = _selectedDate != null &&
                    date.year == _selectedDate!.year &&
                    date.month == _selectedDate!.month &&
                    date.day == _selectedDate!.day;
                final isToday = date.year == _today.year &&
                    date.month == _today.month &&
                    date.day == _today.day;

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedDate = date;
                    });
                  },
                  child: Container(
                    width: 54,
                    margin: const EdgeInsets.symmetric(horizontal: 4.0),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.secondaryAccent
                          : (isToday
                              ? AppTheme.secondaryAccent.withValues(alpha: 0.15)
                              : AppTheme.backgroundColor),
                      borderRadius: BorderRadius.circular(16),
                      border: isToday && !isSelected
                          ? Border.all(color: AppTheme.secondaryAccent, width: 1.5)
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
                            color: isSelected
                                ? AppTheme.backgroundColor
                                : AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          DateFormat('d').format(date),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isSelected
                                ? AppTheme.backgroundColor
                                : AppTheme.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          const VerticalDivider(width: 1, color: Color(0xFF334155)),

          GestureDetector(
            onTap: () {
              setState(() {
                _selectedDate = null;
              });
            },
            child: Container(
              width: 58,
              margin: const EdgeInsets.only(left: 8.0, right: 12.0),
              decoration: BoxDecoration(
                color: _selectedDate == null
                    ? AppTheme.primaryAccent
                    : AppTheme.backgroundColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppTheme.primaryAccent.withValues(alpha: 0.4),
                  width: 1.5,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'FLEX',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: _selectedDate == null
                          ? AppTheme.backgroundColor
                          : AppTheme.primaryAccent,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'F',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: _selectedDate == null
                          ? AppTheme.backgroundColor
                          : AppTheme.primaryAccent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getPriorityColor(int priority) {
    if (priority <= 30) return Colors.redAccent;
    if (priority <= 70) return Colors.orangeAccent;
    return AppTheme.routineAccent;
  }
}
