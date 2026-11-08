import 'package:flutter_test/flutter_test.dart';
import 'package:neurovault/models/neuro_item.dart';
import 'package:neurovault/providers/neuro_providers.dart';
import 'package:neurovault/services/hive_storage_service.dart';

class MockHiveStorageService extends HiveStorageService {
  final List<DailyCategory> _categories = [];
  final List<NeuroItem> _items = [];
  String _customUngroupedName = 'Ungrouped Tasks';
  int? _customUngroupedColor;
  bool _isUngroupedDeleted = false;

  @override
  List<DailyCategory> getDailyCategories() => List.unmodifiable(_categories);

  @override
  Future<void> saveDailyCategories(List<DailyCategory> categories) async {
    _categories.clear();
    _categories.addAll(categories);
  }

  @override
  List<NeuroItem> getAllItems() => List.unmodifiable(_items);

  @override
  Future<void> saveAllItems(List<NeuroItem> items) async {
    _items.clear();
    _items.addAll(items);
  }

  @override
  String getCustomUngroupedName() => _customUngroupedName;

  @override
  Future<void> saveCustomUngroupedName(String name) async {
    _customUngroupedName = name;
  }

  @override
  int? getCustomUngroupedColor() => _customUngroupedColor;

  @override
  Future<void> saveCustomUngroupedColor(int? colorHex) async {
    _customUngroupedColor = colorHex;
  }

  @override
  bool getIsUngroupedCategoryDeleted() => _isUngroupedDeleted;

  int _dailyViewMode = 0;

  @override
  int getDailyViewMode() => _dailyViewMode;

  @override
  Future<void> saveDailyViewMode(int mode) async {
    _dailyViewMode = mode;
  }

  @override
  Future<void> saveIsUngroupedCategoryDeleted(bool deleted) async {
    _isUngroupedDeleted = deleted;
  }

  int _customUngroupedPriority = 50;

  @override
  int getCustomUngroupedPriority() => _customUngroupedPriority;

  @override
  Future<void> saveCustomUngroupedPriority(int priority) async {
    _customUngroupedPriority = priority;
  }
}

void main() {
  group('Daily Category & Task Priority Tests', () {
    late MockHiveStorageService mockStorage;

    setUp(() {
      mockStorage = MockHiveStorageService();
    });

    test('reorderCategories updates priorities sequentially from 1 to N', () {
      final notifier = DailyCategoriesNotifier(mockStorage);
      final cat1 = DailyCategory(id: 'c1', name: 'Work', priority: 50);
      final cat2 = DailyCategory(id: 'c2', name: 'Fitness', priority: 50);
      final cat3 = DailyCategory(id: 'c3', name: 'Study', priority: 50);

      notifier.addCategory(cat1);
      notifier.addCategory(cat2);
      notifier.addCategory(cat3);

      expect(notifier.state.length, 3);

      // Reorder in reverse: Fitness (index 0), Study (index 1), Work (index 2)
      notifier.reorderCategories([cat2, cat3, cat1]);

      expect(notifier.state[0].id, 'c2');
      expect(notifier.state[0].priority, 1);
      expect(notifier.state[1].id, 'c3');
      expect(notifier.state[1].priority, 2);
      expect(notifier.state[2].id, 'c1');
      expect(notifier.state[2].priority, 3);
    });

    test('deleteAllCategories clears state and persists', () {
      final notifier = DailyCategoriesNotifier(mockStorage);
      notifier.addCategory(DailyCategory(id: 'c1', name: 'Work'));
      notifier.addCategory(DailyCategory(id: 'c2', name: 'Personal'));

      expect(notifier.state.length, 2);

      notifier.deleteAllCategories();

      expect(notifier.state.isEmpty, true);
      expect(mockStorage.getDailyCategories().isEmpty, true);
    });

    test('reorderTasks updates item priority levels sequentially', () {
      final notifier = NeuroItemsNotifier(mockStorage);
      final item1 = NeuroItem(id: 't1', title: 'Task 1', type: NeuroItemType.task, priority: 10);
      final item2 = NeuroItem(id: 't2', title: 'Task 2', type: NeuroItemType.task, priority: 20);
      final item3 = NeuroItem(id: 't3', title: 'Task 3', type: NeuroItemType.task, priority: 30);

      mockStorage.saveAllItems([item1, item2, item3]);
      notifier.state = [item1, item2, item3];

      // Reorder to: Task 3, Task 1, Task 2
      notifier.reorderTasks([item3, item1, item2]);

      final updated3 = notifier.state.firstWhere((i) => i.id == 't3');
      final updated1 = notifier.state.firstWhere((i) => i.id == 't1');
      final updated2 = notifier.state.firstWhere((i) => i.id == 't2');

      expect(updated3.priority, 1);
      expect(updated1.priority, 2);
      expect(updated2.priority, 3);
    });

    test('reorderTasks preserves marked (completed/failed) item priority when pushed down', () {
      final notifier = NeuroItemsNotifier(mockStorage);
      final today = DateTime(2026, 10, 24);
      final todayKey = '2026-10-24';

      final item1 = NeuroItem(
        id: 't1',
        title: 'Task 1',
        type: NeuroItemType.task,
        priority: 1, // Originally P1
        completedDates: [todayKey],
        isCompleted: true,
      );
      final item2 = NeuroItem(
        id: 't2',
        title: 'Task 2',
        type: NeuroItemType.task,
        priority: 10,
      );
      final item3 = NeuroItem(
        id: 't3',
        title: 'Task 3',
        type: NeuroItemType.task,
        priority: 20,
      );

      mockStorage.saveAllItems([item1, item2, item3]);
      notifier.state = [item1, item2, item3];

      // In daily view, completed item1 is pushed down to bottom: [item3, item2, item1]
      notifier.reorderTasks([item3, item2, item1], date: today);

      final updated1 = notifier.state.firstWhere((i) => i.id == 't1');
      final updated2 = notifier.state.firstWhere((i) => i.id == 't2');
      final updated3 = notifier.state.firstWhere((i) => i.id == 't3');

      // Active items reordered sequentially
      expect(updated3.priority, 1);
      expect(updated2.priority, 2);
      // Completed item pushed to bottom keeps its original priority 1!
      expect(updated1.priority, 1);

      // Now unmark item 1
      notifier.resetItemForDate('t1', today);
      final unmarked1 = notifier.state.firstWhere((i) => i.id == 't1');
      expect(unmarked1.isCompleted, false);
      expect(unmarked1.completedDates.contains(todayKey), false);
      // Priority remains 1!
      expect(unmarked1.priority, 1);
    });

    test('toggleCompletionForDate and toggleFailedForDate never change task priority', () {
      final notifier = NeuroItemsNotifier(mockStorage);
      final today = DateTime(2026, 10, 24);

      final item = NeuroItem(
        id: 't1',
        title: 'Task 1',
        type: NeuroItemType.task,
        priority: 5,
      );
      mockStorage.saveAllItems([item]);
      notifier.state = [item];

      // Mark completed
      notifier.toggleCompletionForDate('t1', today);
      expect(notifier.state.first.isCompleted, true);
      expect(notifier.state.first.priority, 5);

      // Mark incomplete (toggle again)
      notifier.toggleCompletionForDate('t1', today);
      expect(notifier.state.first.isCompleted, false);
      expect(notifier.state.first.priority, 5);

      // Mark failed
      notifier.toggleFailedForDate('t1', today);
      expect(notifier.state.first.isFailedOnDate(today), true);
      expect(notifier.state.first.priority, 5);

      // Reset
      notifier.resetItemForDate('t1', today);
      expect(notifier.state.first.priority, 5);
    });

    test('ungrouped category name, color, and deleted state persistence', () async {
      expect(mockStorage.getCustomUngroupedName(), 'Ungrouped Tasks');
      expect(mockStorage.getIsUngroupedCategoryDeleted(), false);

      await mockStorage.saveCustomUngroupedName('General Tasks');
      await mockStorage.saveCustomUngroupedColor(0xFF69F0AE);
      await mockStorage.saveIsUngroupedCategoryDeleted(true);

      expect(mockStorage.getCustomUngroupedName(), 'General Tasks');
      expect(mockStorage.getCustomUngroupedColor(), 0xFF69F0AE);
      expect(mockStorage.getIsUngroupedCategoryDeleted(), true);

      // Reset upon creating new category
      await mockStorage.saveIsUngroupedCategoryDeleted(false);
      expect(mockStorage.getIsUngroupedCategoryDeleted(), false);
    });

    test('daily view mode persistence and 3-mode selection', () async {
      expect(mockStorage.getDailyViewMode(), 0); // Default categories

      await mockStorage.saveDailyViewMode(1);
      expect(mockStorage.getDailyViewMode(), 1); // Custom categories

      await mockStorage.saveDailyViewMode(2);
      expect(mockStorage.getDailyViewMode(), 2); // Priority list
    });

    test('ungrouped category priority persistence across reorders', () async {
      expect(mockStorage.getCustomUngroupedPriority(), 50);

      await mockStorage.saveCustomUngroupedPriority(3);
      expect(mockStorage.getCustomUngroupedPriority(), 3);

      await mockStorage.saveCustomUngroupedPriority(2);
      expect(mockStorage.getCustomUngroupedPriority(), 2);
    });
  });
}
