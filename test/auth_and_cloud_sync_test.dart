import 'package:flutter_test/flutter_test.dart';
import 'package:neurovault/models/app_user.dart';
import 'package:neurovault/models/neuro_item.dart';
import 'package:neurovault/services/auth_service.dart';
import 'package:neurovault/services/cloud_sync_service.dart';
import 'package:neurovault/services/hive_storage_service.dart';

class MockCloudHiveStorageService extends HiveStorageService {
  AppUser? _currentUser;
  final List<NeuroItem> _localItems = [];
  final List<DailyCategory> _localCategories = [];
  final Map<String, List<NeuroItem>> _cloudVaultItems = {};
  final Map<String, List<DailyCategory>> _cloudVaultCategories = {};
  final Map<String, List<Map<String, dynamic>>> _syncQueues = {};

  @override
  AppUser? getCurrentUser() => _currentUser;

  @override
  Future<void> saveCurrentUser(AppUser? user) async {
    _currentUser = user;
  }

  @override
  List<NeuroItem> getAllItems() => List.unmodifiable(_localItems);

  @override
  Future<void> saveAllItems(List<NeuroItem> items) async {
    _localItems.clear();
    _localItems.addAll(items);
  }

  @override
  Future<void> saveItem(NeuroItem item) async {
    final idx = _localItems.indexWhere((i) => i.id == item.id);
    if (idx >= 0) {
      _localItems[idx] = item;
    } else {
      _localItems.add(item);
    }
  }

  @override
  List<DailyCategory> getDailyCategories() => List.unmodifiable(_localCategories);

  @override
  Future<void> saveDailyCategories(List<DailyCategory> categories) async {
    _localCategories.clear();
    _localCategories.addAll(categories);
  }

  @override
  List<NeuroItem> getCloudVaultItems(String userId) {
    return List.unmodifiable(_cloudVaultItems[userId] ?? []);
  }

  @override
  Future<void> saveCloudVaultItems(String userId, List<NeuroItem> items) async {
    _cloudVaultItems[userId] = List.from(items);
  }

  @override
  List<DailyCategory> getCloudVaultCategories(String userId) {
    return List.unmodifiable(_cloudVaultCategories[userId] ?? []);
  }

  @override
  Future<void> saveCloudVaultCategories(String userId, List<DailyCategory> categories) async {
    _cloudVaultCategories[userId] = List.from(categories);
  }

  @override
  List<Map<String, dynamic>> getPendingSyncQueue(String userId) {
    return List.unmodifiable(_syncQueues[userId] ?? []);
  }

  @override
  Future<void> savePendingSyncQueue(String userId, List<Map<String, dynamic>> queue) async {
    _syncQueues[userId] = List.from(queue);
  }

  @override
  Future<void> deleteUserData(String userId) async {
    _cloudVaultItems.remove(userId);
    _cloudVaultCategories.remove(userId);
    _syncQueues.remove(userId);
    if (_currentUser?.id == userId) {
      _currentUser = null;
      _localItems.clear();
      _localCategories.clear();
    }
  }
}

void main() {
  group('AuthService Tests', () {
    late MockCloudHiveStorageService mockStorage;
    late AuthService authService;

    setUp(() {
      mockStorage = MockCloudHiveStorageService();
      authService = AuthService(mockStorage);
    });

    test('Google Sign-In creates stable user, stores in storage, and sets session', () async {
      expect(authService.currentUser, isNull);

      final user = await authService.signInWithGoogle(
        email: 'alex@example.com',
        displayName: 'Alex Rivera',
      );

      expect(user.email, 'alex@example.com');
      expect(user.displayName, 'Alex Rivera');
      expect(user.isGuest, false);
      expect(authService.currentUser, isNotNull);
      expect(mockStorage.getCurrentUser()?.email, 'alex@example.com');
    });

    test('Email Sign-Up and Sign-In validation and persistence', () async {
      final user = await authService.signUpWithEmail('alex@focus.space', 'secretPass123');
      expect(user.email, 'alex@focus.space');
      expect(user.isGuest, false);
      expect(mockStorage.getCurrentUser()?.email, 'alex@focus.space');

      // Invalid email throws Exception
      expect(
        () => authService.signInWithEmail('invalid-email', '123456'),
        throwsA(isA<Exception>()),
      );

      // Short password throws Exception
      expect(
        () => authService.signInWithEmail('test@gmail.com', '123'),
        throwsA(isA<Exception>()),
      );
    });

    test('Guest / Offline Mode signs in without credentials and persists', () async {
      final guest = await authService.signInAsGuest();
      expect(guest.isGuest, true);
      expect(guest.displayName, 'Guest User');
      expect(mockStorage.getCurrentUser()?.isGuest, true);
    });

    test('Sign Out clears user session from memory and storage', () async {
      await authService.signInWithGoogle(email: 'user@gmail.com');
      expect(authService.currentUser, isNotNull);

      await authService.signOut();
      expect(authService.currentUser, isNull);
      expect(mockStorage.getCurrentUser(), isNull);
    });

    test('Delete Account wipes user data locally and from cloud vault', () async {
      final user = await authService.signInWithGoogle(email: 'delete.me@gmail.com');
      mockStorage.saveCloudVaultItems(user.id, [
        NeuroItem(id: 'task_del', title: 'To be wiped', type: NeuroItemType.task),
      ]);
      expect(mockStorage.getCloudVaultItems(user.id).isNotEmpty, true);

      await authService.deleteAccount();
      expect(authService.currentUser, isNull);
      expect(mockStorage.getCurrentUser(), isNull);
      expect(mockStorage.getCloudVaultItems(user.id).isEmpty, true);
    });
  });

  group('CloudSyncService & Conflict-Free Merge Tests', () {
    late MockCloudHiveStorageService mockStorage;
    late CloudSyncService syncService;

    setUp(() {
      mockStorage = MockCloudHiveStorageService();
      syncService = CloudSyncService(mockStorage);
    });

    tearDown(() {
      syncService.dispose();
    });

    test('syncAction immediately mirrors items and categories to user cloud vault', () async {
      final user = AppUser(
        id: 'user_123',
        email: 'user@cloud.com',
        displayName: 'User 123',
        createdAt: DateTime.now(),
        lastLoginAt: DateTime.now(),
      );
      await mockStorage.saveCurrentUser(user);

      final task = NeuroItem(id: 't1', title: 'Daily Workout', type: NeuroItemType.routine);
      final category = DailyCategory(id: 'c1', name: 'Fitness');

      await syncService.syncAction(
        userId: user.id,
        actionType: 'item_add',
        payload: {'id': task.id},
        currentLocalItems: [task],
        currentLocalCategories: [category],
      );

      final cloudItems = mockStorage.getCloudVaultItems(user.id);
      final cloudCats = mockStorage.getCloudVaultCategories(user.id);

      expect(cloudItems.length, 1);
      expect(cloudItems.first.title, 'Daily Workout');
      expect(cloudCats.length, 1);
      expect(cloudCats.first.name, 'Fitness');
      expect(syncService.status, SyncStatus.synced);
    });

    test('pullAndMerge seamlessly integrates tasks from device A and device B without data loss', () async {
      const userId = 'user_cross_device';

      // Device A has Task 1
      final itemFromDeviceA = NeuroItem(
        id: 'task_device_a',
        title: 'Task Created on Phone A',
        type: NeuroItemType.task,
        isCompleted: false,
      );

      // Cloud (Device B) already uploaded Task 2
      final itemFromDeviceB = NeuroItem(
        id: 'task_device_b',
        title: 'Task Created on Tablet B',
        type: NeuroItemType.task,
        isCompleted: true,
      );

      await mockStorage.saveCloudVaultItems(userId, [itemFromDeviceB]);

      // When Device A pulls and merges:
      final result = await syncService.pullAndMerge(
        userId: userId,
        localItems: [itemFromDeviceA],
        localCategories: [],
      );

      // Result MUST contain BOTH tasks! Zero missing data!
      expect(result.mergedItems.length, 2);
      expect(result.mergedItems.any((i) => i.id == 'task_device_a'), true);
      expect(result.mergedItems.any((i) => i.id == 'task_device_b'), true);

      // Check that local storage now has both
      expect(mockStorage.getAllItems().length, 2);
      // Check that cloud vault also has both
      expect(mockStorage.getCloudVaultItems(userId).length, 2);
    });

    test('pullAndMerge resolves conflicts by uniting completed dates and highest streaks', () async {
      const userId = 'user_conflict_test';

      final localItem = NeuroItem(
        id: 'habit_1',
        title: 'Read 20 Pages',
        type: NeuroItemType.routine,
        completedDates: ['2026-10-01', '2026-10-02'],
        streakCount: 2,
        isCompleted: true,
      );

      final remoteItem = NeuroItem(
        id: 'habit_1',
        title: 'Read 20 Pages',
        type: NeuroItemType.routine,
        completedDates: ['2026-10-02', '2026-10-03'],
        streakCount: 3,
        isCompleted: true,
      );

      await mockStorage.saveCloudVaultItems(userId, [remoteItem]);

      final result = await syncService.pullAndMerge(
        userId: userId,
        localItems: [localItem],
        localCategories: [],
      );

      final merged = result.mergedItems.firstWhere((i) => i.id == 'habit_1');
      // Union of completed dates: 2026-10-01, 2026-10-02, 2026-10-03
      expect(merged.completedDates.length, 3);
      expect(merged.completedDates.contains('2026-10-01'), true);
      expect(merged.completedDates.contains('2026-10-02'), true);
      expect(merged.completedDates.contains('2026-10-03'), true);
      // Highest streak preserved
      expect(merged.streakCount, 3);
    });

    test('Multi-account isolation: User 1 cloud data is separate from User 2', () async {
      const user1 = 'user_alpha';
      const user2 = 'user_beta';

      await mockStorage.saveCurrentUser(AppUser(
        id: user1,
        email: 'alpha@cloud.com',
        displayName: 'Alpha',
        createdAt: DateTime.now(),
        lastLoginAt: DateTime.now(),
      ));

      await syncService.syncAction(
        userId: user1,
        actionType: 'item_add',
        payload: {},
        currentLocalItems: [NeuroItem(id: 'item_u1', title: 'User 1 Task', type: NeuroItemType.task)],
        currentLocalCategories: [],
      );

      await mockStorage.saveCurrentUser(AppUser(
        id: user2,
        email: 'beta@cloud.com',
        displayName: 'Beta',
        createdAt: DateTime.now(),
        lastLoginAt: DateTime.now(),
      ));

      await syncService.syncAction(
        userId: user2,
        actionType: 'item_add',
        payload: {},
        currentLocalItems: [NeuroItem(id: 'item_u2', title: 'User 2 Task', type: NeuroItemType.task)],
        currentLocalCategories: [],
      );

      final u1Items = mockStorage.getCloudVaultItems(user1);
      final u2Items = mockStorage.getCloudVaultItems(user2);

      expect(u1Items.length, 1);
      expect(u1Items.first.id, 'item_u1');

      expect(u2Items.length, 1);
      expect(u2Items.first.id, 'item_u2');
    });
  });
}
