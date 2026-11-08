import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../models/neuro_item.dart';
import '../theme/app_theme.dart';

class UnifiedStepperDialog extends StatefulWidget {
  final String title;
  final bool isFolder; // true = Folder/Vision, false = Task/Habit/Routine
  final NeuroItem? existingItem;
  final String? parentId;
  final DateTime? initialDate;
  final NeuroItemType? initialType;
  final Function(NeuroItem) onSave;

  const UnifiedStepperDialog({
    super.key,
    required this.title,
    this.isFolder = false,
    this.existingItem,
    this.parentId,
    this.initialDate,
    this.initialType,
    required this.onSave,
  });

  @override
  State<UnifiedStepperDialog> createState() => _UnifiedStepperDialogState();
}

class _UnifiedStepperDialogState extends State<UnifiedStepperDialog> {
  int _currentStep = 0;

  // Controllers & Form State
  late TextEditingController _titleController;
  late TextEditingController _descController;
  late TextEditingController _numericTargetController;
  late TextEditingController _timerMinutesController;
  late TextEditingController _repeatIntervalController;

  late NeuroItemType _type;
  late RoutineCompletionType _completionType;
  late ScheduleType _scheduleType;
  late DateTime? _targetDate;
  late bool _isFlexibleNoDate; // True if Flexible "F" tab task (No Date)
  late TimeOfDay? _targetTime;
  late DateTime _startDate;
  late DateTime? _endDate;
  late double _priority;
  late bool _isPendingCarryover;
  late bool _noVisionXpEnabled;
  late List<int> _selectedDaysOfWeek;
  late List<String> _selectedDaysOfMonth;
  late List<String> _selectedDaysOfYear;
  late List<ChecklistItem> _checklist;
  late bool _successContributesToProgress;
  late bool _failureContributesToProgress;

  @override
  void initState() {
    super.initState();
    final item = widget.existingItem;

    _titleController = TextEditingController(text: item?.title ?? '');
    _descController = TextEditingController(text: item?.description ?? '');
    _numericTargetController = TextEditingController(
        text: (item?.targetNumericValue ?? 10).toInt().toString());
    _timerMinutesController = TextEditingController(
        text: ((item?.timerDurationSeconds ?? 600) ~/ 60).toString());
    _repeatIntervalController = TextEditingController(
        text: (item?.repeatIntervalDays ?? 2).toString());

    _type = item?.type ?? (widget.initialType ?? (widget.isFolder ? NeuroItemType.routineFolder : NeuroItemType.task));
    _completionType = item?.completionType ?? RoutineCompletionType.yesNo;
    _scheduleType = item?.scheduleType ?? ScheduleType.everyday;

    if (_type == NeuroItemType.routine) {
      _isFlexibleNoDate = false;
      _targetDate = null;
      _startDate = item?.startDate ?? DateTime.now();
    } else {
      if (item != null) {
        _targetDate = item.targetDate;
        _isFlexibleNoDate = item.targetDate == null;
      } else {
        _targetDate = widget.initialDate;
        _isFlexibleNoDate = widget.initialDate == null;
      }
      _startDate = item?.startDate ?? (_targetDate ?? DateTime.now());
    }

    _targetTime = _parseTime(item?.targetTime);
    _endDate = item?.endDate;
    _priority = (item?.priority ?? 50).toDouble();
    _isPendingCarryover = (item?.isPendingCarryover ?? false) || (item?.isFlexibleCarryover ?? false);
    _noVisionXpEnabled = item?.noVisionXpEnabled ?? false;
    _selectedDaysOfWeek = item != null ? List<int>.from(item.selectedDaysOfWeek) : [];
    _selectedDaysOfMonth = item != null ? List<String>.from(item.selectedDaysOfMonth) : [];
    _selectedDaysOfYear = item != null ? List<String>.from(item.selectedDaysOfYear) : [];
    _checklist = item != null ? List<ChecklistItem>.from(item.checklist) : [];
    _successContributesToProgress = item?.successContributesToProgress ?? true;
    _failureContributesToProgress = item?.failureContributesToProgress ?? false;
  }

  int get _totalSteps {
    if (widget.isFolder) return 2;
    return 3;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surfaceColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Column(
        children: [
          Text(widget.title, textAlign: TextAlign.center),
          const SizedBox(height: 10),
          // Step Progress Indicator Dots
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              _totalSteps,
              (index) => Container(
                width: index == _currentStep ? 24 : 8,
                height: 8,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: index <= _currentStep
                      ? AppTheme.primaryAccent
                      : AppTheme.textSecondary.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: double.maxFinite,
          child: _buildCurrentStepContent(),
        ),
      ),
      actions: [
        if (_currentStep > 0)
          TextButton(
            onPressed: () => setState(() => _currentStep--),
            child: const Text('Back'),
          ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryAccent,
          ),
          onPressed: () {
            if (_currentStep < _totalSteps - 1) {
              if (_titleController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a title')),
                );
                return;
              }
              setState(() => _currentStep++);
            } else {
              _saveAndSubmit();
            }
          },
          child: Text(_currentStep < _totalSteps - 1 ? 'Next Step' : 'Save'),
        ),
      ],
    );
  }

  Widget _buildCurrentStepContent() {
    if (widget.isFolder) {
      if (_currentStep == 0) return _buildFolderStep1();
      return _buildFolderStep2();
    } else {
      if (_currentStep == 0) return _buildItemStep1();
      if (_currentStep == 1) return _buildItemStep2();
      return _buildItemStep3();
    }
  }

  // --- Folder Creation Steps ---
  Widget _buildFolderStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Step 1: Folder Basics',
            style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textSecondary, fontSize: 12)),
        const SizedBox(height: 12),
        TextField(
          controller: _titleController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Name (e.g. Morning Routine)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _descController,
          decoration: const InputDecoration(
            labelText: 'Description (optional)',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  Widget _buildFolderStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Step 2: Dates & Priority',
            style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textSecondary, fontSize: 12)),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.calendar_today_rounded, color: AppTheme.primaryAccent),
          title: Text('Start Date: ${DateFormat('MMM d, yyyy').format(_startDate)}',
              style: const TextStyle(fontSize: 13)),
          trailing: TextButton(
            child: const Text('Change'),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _startDate,
                firstDate: DateTime(2020),
                lastDate: DateTime(2030),
              );
              if (picked != null) setState(() => _startDate = picked);
            },
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event_busy_rounded, color: AppTheme.secondaryAccent),
          title: Text(
            _endDate == null
                ? 'End Date: Ongoing'
                : 'End Date: ${DateFormat('MMM d, yyyy').format(_endDate!)}',
            style: const TextStyle(fontSize: 13),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_endDate != null)
                IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () => setState(() => _endDate = null),
                ),
              TextButton(
                child: const Text('Set End'),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _endDate ?? _startDate.add(const Duration(days: 30)),
                    firstDate: _startDate,
                    lastDate: DateTime(2030),
                  );
                  if (picked != null) setState(() => _endDate = picked);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Priority Level:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            Text('P${_priority.toInt()}',
                style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryAccent)),
          ],
        ),
        Slider(
          value: _priority,
          min: 1,
          max: 100,
          divisions: 99,
          activeColor: AppTheme.primaryAccent,
          onChanged: (val) => setState(() => _priority = val),
        ),
      ],
    );
  }

  // --- Item Creation Steps ---
  Widget _buildItemStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Step 1: Item Details',
            style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textSecondary, fontSize: 12)),
        const SizedBox(height: 12),
        TextField(
          controller: _titleController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Title',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _descController,
          decoration: const InputDecoration(
            labelText: 'Description (optional)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 14),

        // Type selection (Task vs Habit/Routine)
        DropdownButtonFormField<NeuroItemType>(
          initialValue: _type == NeuroItemType.routine ? NeuroItemType.routine : NeuroItemType.task,
          decoration: const InputDecoration(labelText: 'Item Type'),
          items: const [
            DropdownMenuItem(value: NeuroItemType.task, child: Text('One-Time Task')),
            DropdownMenuItem(value: NeuroItemType.routine, child: Text('Habit / Routine')),
          ],
          onChanged: (val) {
            if (val != null) {
              setState(() {
                _type = val;
                if (_type == NeuroItemType.routine) {
                  _isFlexibleNoDate = false;
                }
              });
            }
          },
        ),
        const SizedBox(height: 12),

        // Completion Mechanism
        DropdownButtonFormField<RoutineCompletionType>(
          initialValue: _completionType,
          decoration: const InputDecoration(labelText: 'Type of Tracker'),
          items: const [
            DropdownMenuItem(value: RoutineCompletionType.yesNo, child: Text('Yes / No Checkoff')),
            DropdownMenuItem(value: RoutineCompletionType.numeric, child: Text('Numeric Target Counter')),
            DropdownMenuItem(value: RoutineCompletionType.timer, child: Text('Timer')),
            DropdownMenuItem(value: RoutineCompletionType.checklist, child: Text('Sub-Checklist')),
          ],
          onChanged: (val) => setState(() => _completionType = val!),
        ),

        if (_completionType == RoutineCompletionType.numeric) ...[
          const SizedBox(height: 10),
          TextField(
            controller: _numericTargetController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Target Value (Set 0 for Bad Habit / Count-up)',
              helperText: 'Set 0 to track bad habits / count occurrences done',
              border: OutlineInputBorder(),
            ),
          ),
        ],

        if (_completionType == RoutineCompletionType.timer) ...[
          const SizedBox(height: 10),
          TextField(
            controller: _timerMinutesController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Timer (Minutes)',
              border: OutlineInputBorder(),
            ),
          ),
        ],

        const SizedBox(height: 12),
        SwitchListTile(
          title: const Text('Success contributes to progress', style: TextStyle(fontSize: 13)),
          subtitle: const Text('Completions count toward the progress bar', style: TextStyle(fontSize: 11)),
          value: _successContributesToProgress,
          activeThumbColor: AppTheme.routineAccent,
          contentPadding: EdgeInsets.zero,
          onChanged: (val) => setState(() => _successContributesToProgress = val),
        ),
        SwitchListTile(
          title: const Text('Failure affects progress', style: TextStyle(fontSize: 13)),
          subtitle: const Text('Missed/failed instances penalize the progress bar', style: TextStyle(fontSize: 11)),
          value: _failureContributesToProgress,
          activeThumbColor: const Color(0xFFF87171),
          contentPadding: EdgeInsets.zero,
          onChanged: (val) => setState(() => _failureContributesToProgress = val),
        ),
      ],
    );
  }

  Widget _buildItemStep2() {
    final isOneTimeTask = _type == NeuroItemType.task;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Step 2: Schedule & Timing',
          style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 12),

        if (isOneTimeTask) ...[
          // Schedule Mode Toggle (Scheduled Date vs Flexible No-Date Task)
          Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  label: const Text('Scheduled Date', style: TextStyle(fontSize: 12)),
                  selected: !_isFlexibleNoDate,
                  selectedColor: AppTheme.primaryAccent.withValues(alpha: 0.2),
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _isFlexibleNoDate = false;
                        _targetDate ??= DateTime.now();
                      });
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ChoiceChip(
                  label: const Text('Flexible (No Date)', style: TextStyle(fontSize: 12)),
                  selected: _isFlexibleNoDate,
                  selectedColor: AppTheme.secondaryAccent.withValues(alpha: 0.2),
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _isFlexibleNoDate = true;
                      });
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (_isFlexibleNoDate)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.backgroundColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.secondaryAccent.withValues(alpha: 0.3)),
              ),
              child: const Text(
                'Flexible Task: Appears daily in the To-Do List Flex tab until marked completed.',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
            ),
        ],

        if (!isOneTimeTask || !_isFlexibleNoDate) ...[
          // For Routines / Habits: show recurring schedule frequency options
          if (!isOneTimeTask) ...[
            DropdownButtonFormField<ScheduleType>(
              initialValue: _scheduleType,
              decoration: const InputDecoration(labelText: 'Schedule Frequency'),
              items: const [
                DropdownMenuItem(value: ScheduleType.everyday, child: Text('Everyday')),
                DropdownMenuItem(value: ScheduleType.specificDaysOfWeek, child: Text('Days of Week')),
                DropdownMenuItem(value: ScheduleType.specificDaysOfMonth, child: Text('Days of Month')),
                DropdownMenuItem(value: ScheduleType.specificDaysOfYear, child: Text('Days of Year')),
                DropdownMenuItem(value: ScheduleType.repeatInterval, child: Text('Repeat Every X Days')),
              ],
              onChanged: (val) => setState(() => _scheduleType = val!),
            ),
            const SizedBox(height: 12),

            if (_scheduleType == ScheduleType.specificDaysOfWeek) ...[
              Wrap(
                spacing: 6,
                children: [
                  _dayChip(1, 'Mon', _selectedDaysOfWeek),
                  _dayChip(2, 'Tue', _selectedDaysOfWeek),
                  _dayChip(3, 'Wed', _selectedDaysOfWeek),
                  _dayChip(4, 'Thu', _selectedDaysOfWeek),
                  _dayChip(5, 'Fri', _selectedDaysOfWeek),
                  _dayChip(6, 'Sat', _selectedDaysOfWeek),
                  _dayChip(7, 'Sun', _selectedDaysOfWeek),
                ],
              ),
              const SizedBox(height: 12),
            ],

            if (_scheduleType == ScheduleType.specificDaysOfMonth) ...[
              const Text('Select Days of Month:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textSecondary)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _dayStringChip('FIRST_DAY', 'First Day', _selectedDaysOfMonth),
                  _dayStringChip('LAST_DAY', 'Last Day', _selectedDaysOfMonth),
                  for (int i = 1; i <= 31; i++)
                    _dayStringChip(i.toString(), i.toString(), _selectedDaysOfMonth),
                ],
              ),
              const SizedBox(height: 12),
            ],

            if (_scheduleType == ScheduleType.specificDaysOfYear) ...[
              const Text('Select Days of Year:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textSecondary)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _dayStringChip('FIRST_DAY', 'First Day of Year', _selectedDaysOfYear),
                  _dayStringChip('LAST_DAY', 'Last Day of Year', _selectedDaysOfYear),
                  for (final dateStr in _selectedDaysOfYear.where((s) => s != 'FIRST_DAY' && s != 'LAST_DAY'))
                    Chip(
                      label: Text(dateStr, style: const TextStyle(fontSize: 11)),
                      onDeleted: () {
                        setState(() => _selectedDaysOfYear.remove(dateStr));
                      },
                    ),
                ],
              ),
              const SizedBox(height: 6),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.surfaceColor),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Date of Year (MM-DD)', style: TextStyle(fontSize: 11)),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2030),
                  );
                  if (picked != null) {
                    final mmdd = DateFormat('MM-dd').format(picked);
                    if (!_selectedDaysOfYear.contains(mmdd)) {
                      setState(() => _selectedDaysOfYear.add(mmdd));
                    }
                  }
                },
              ),
              const SizedBox(height: 12),
            ],

            if (_scheduleType == ScheduleType.repeatInterval) ...[
              TextField(
                controller: _repeatIntervalController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Repeat Interval (Every X Days)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ],

          // Start / Target Date Picker
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.calendar_today_rounded, color: AppTheme.secondaryAccent),
            title: Text(
              isOneTimeTask
                  ? (_targetDate == null
                      ? 'Pick Target Date'
                      : 'Target Date: ${DateFormat('EEE, MMM d, yyyy').format(_targetDate!)}')
                  : 'Start Date: ${DateFormat('EEE, MMM d, yyyy').format(_startDate)}',
              style: const TextStyle(fontSize: 13),
            ),
            trailing: TextButton(
              child: const Text('Change Date'),
              onPressed: () async {
                final initial = isOneTimeTask ? (_targetDate ?? DateTime.now()) : _startDate;
                final picked = await showDatePicker(
                  context: context,
                  initialDate: initial,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2030),
                );
                if (picked != null) {
                  setState(() {
                    if (isOneTimeTask) {
                      _targetDate = picked;
                      _isFlexibleNoDate = false;
                    } else {
                      _startDate = picked;
                    }
                  });
                }
              },
            ),
          ),

          // End Date Picker for Items
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_busy_rounded, color: AppTheme.routineAccent),
            title: Text(
              _endDate == null
                  ? 'End Date: Ongoing / No End Date'
                  : 'End Date: ${DateFormat('MMM d, yyyy').format(_endDate!)}',
              style: const TextStyle(fontSize: 13),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_endDate != null)
                  IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () => setState(() => _endDate = null),
                  ),
                TextButton(
                  child: const Text('Set End'),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _endDate ?? (_targetDate ?? DateTime.now()).add(const Duration(days: 30)),
                      firstDate: _targetDate ?? DateTime.now(),
                      lastDate: DateTime(2030),
                    );
                    if (picked != null) setState(() => _endDate = picked);
                  },
                ),
              ],
            ),
          ),

          // Target Time Picker
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.access_time_rounded, color: AppTheme.primaryAccent),
            title: Text(_targetTime == null ? 'Set Target Time (Optional)' : _targetTime!.format(context)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_targetTime != null)
                  IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () => setState(() => _targetTime = null),
                  ),
                TextButton(
                  child: const Text('Pick Time'),
                  onPressed: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: _targetTime ?? TimeOfDay.now(),
                    );
                    if (picked != null) setState(() => _targetTime = picked);
                  },
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildItemStep3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Step 3: Priority & Sub-Items',
            style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textSecondary, fontSize: 12)),
        const SizedBox(height: 12),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Priority Level:', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('P${_priority.toInt()}',
                style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryAccent)),
          ],
        ),
        Slider(
          value: _priority,
          min: 1,
          max: 100,
          divisions: 99,
          activeColor: AppTheme.primaryAccent,
          onChanged: (val) => setState(() => _priority = val),
        ),

        if (!_isFlexibleNoDate)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Pending Carryover', style: TextStyle(fontSize: 13)),
            subtitle: const Text('Show each day until completed', style: TextStyle(fontSize: 11)),
            value: _isPendingCarryover,
            activeThumbColor: AppTheme.primaryAccent,
            onChanged: (val) => setState(() => _isPendingCarryover = val),
          ),

        const Divider(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Sub-checklist Items', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            TextButton.icon(
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Sub-item', style: TextStyle(fontSize: 12)),
              onPressed: _addSubItemDialog,
            ),
          ],
        ),
        if (_checklist.isNotEmpty)
          Column(
            children: _checklist.asMap().entries.map((entry) {
              final idx = entry.key;
              final item = entry.value;
              return Row(
                children: [
                  const Icon(Icons.check, size: 14, color: AppTheme.primaryAccent),
                  const SizedBox(width: 8),
                  Expanded(child: Text(item.title, style: const TextStyle(fontSize: 12))),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16, color: Colors.redAccent),
                    onPressed: () => setState(() => _checklist.removeAt(idx)),
                  ),
                ],
              );
            }).toList(),
          ),
      ],
    );
  }

  Widget _dayChip(int dayVal, String label, List<int> list) {
    final isSelected = list.contains(dayVal);
    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      selected: isSelected,
      onSelected: (val) {
        setState(() {
          val ? list.add(dayVal) : list.remove(dayVal);
        });
      },
    );
  }

  Widget _dayStringChip(String valKey, String label, List<String> list) {
    final isSelected = list.contains(valKey);
    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      selected: isSelected,
      selectedColor: AppTheme.primaryAccent.withValues(alpha: 0.2),
      onSelected: (val) {
        setState(() {
          val ? list.add(valKey) : list.remove(valKey);
        });
      },
    );
  }

  void _addSubItemDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: const Text('Add Sub-item', style: TextStyle(fontSize: 15)),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                setState(() {
                  _checklist.add(ChecklistItem(
                    id: const Uuid().v4(),
                    title: controller.text.trim(),
                  ));
                });
                Navigator.pop(context);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _saveAndSubmit() {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    final numericTarget = double.tryParse(_numericTargetController.text.trim()) ?? 10;
    final timerMinutes = int.tryParse(_timerMinutesController.text.trim()) ?? 10;
    final repeatInterval = int.tryParse(_repeatIntervalController.text.trim()) ?? 1;
    final timeStr = (_targetTime != null && !_isFlexibleNoDate)
        ? '${_targetTime!.hour.toString().padLeft(2, '0')}:${_targetTime!.minute.toString().padLeft(2, '0')}'
        : null;

    final item = (widget.existingItem ?? NeuroItem(
      id: const Uuid().v4(),
      title: title,
      type: _type,
    )).copyWith(
      title: title,
      description: _descController.text.trim().isEmpty ? null : _descController.text.trim(),
      type: _type,
      parentId: widget.parentId ?? widget.existingItem?.parentId,
      targetDate: (_type == NeuroItemType.task && _isFlexibleNoDate)
          ? null
          : (_type == NeuroItemType.task ? _targetDate : null),
      clearTargetDate: (_type == NeuroItemType.task && _isFlexibleNoDate) || (_type == NeuroItemType.routine),
      targetTime: timeStr,
      clearTargetTime: timeStr == null,
      startDate: _startDate,
      endDate: _endDate,
      clearEndDate: _endDate == null,
      priority: _priority.toInt(),
      isPendingCarryover: (_type == NeuroItemType.task && _isFlexibleNoDate) ? false : _isPendingCarryover,
      isFlexibleCarryover: (_type == NeuroItemType.task && _isFlexibleNoDate) ? false : _isPendingCarryover,
      noVisionXpEnabled: _noVisionXpEnabled,
      completionType: _completionType,
      targetNumericValue: numericTarget,
      timerDurationSeconds: timerMinutes * 60,
      scheduleType: _scheduleType,
      selectedDaysOfWeek: _selectedDaysOfWeek,
      selectedDaysOfMonth: _selectedDaysOfMonth,
      selectedDaysOfYear: _selectedDaysOfYear,
      repeatIntervalDays: repeatInterval,
      checklist: _checklist,
      successContributesToProgress: _successContributesToProgress,
      failureContributesToProgress: _failureContributesToProgress,
    );

    widget.onSave(item);
    Navigator.pop(context);
  }

  TimeOfDay? _parseTime(String? timeStr) {
    if (timeStr == null || timeStr.trim().isEmpty) return null;
    final str = timeStr.trim();
    try {
      final parts = str.split(':');
      if (parts.length >= 2) {
        final hourStr = parts[0];
        final minPart = parts[1].trim();
        final minStr = minPart.split(' ')[0];
        int hour = int.parse(hourStr);
        int minute = int.parse(minStr);

        final lower = str.toLowerCase();
        if (lower.contains('pm') && hour < 12) hour += 12;
        if (lower.contains('am') && hour == 12) hour = 0;

        return TimeOfDay(hour: hour, minute: minute);
      }
    } catch (_) {}
    try {
      final dt = DateFormat.jm().parse(str);
      return TimeOfDay(hour: dt.hour, minute: dt.minute);
    } catch (_) {}
    return null;
  }
}
