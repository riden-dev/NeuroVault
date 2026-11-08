import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/neuro_item.dart';
import 'cloud_sync_config.dart';
import 'hive_storage_service.dart';

enum SyncStatus {
  synced,   // All changes saved to cloud
  syncing,  // Uploading / downloading changes
  offline,  // Offline or guest mode
  error,    // Cloud request failed, queued for retry
}

class CloudSyncResult {
  final List<NeuroItem> mergedItems;
  final List<DailyCategory> mergedCategories;
  final bool hasChanges;

  CloudSyncResult({
    required this.mergedItems,
    required this.mergedCategories,
    required this.hasChanges,
  });
}

/// Robust Cloud Synchronization Engine for seamless cross-platform & cross-device updates.
class CloudSyncService {
  final HiveStorageService _storage;
  final _statusController = StreamController<SyncStatus>.broadcast();
  SyncStatus _currentStatus = SyncStatus.synced;
  Timer? _periodicSyncTimer;
  DateTime? _lastSyncedAt;

  // Callback to inform notifiers when background cloud updates arrive from another device
  void Function(List<NeuroItem> items, List<DailyCategory> categories)? onRemoteDataUpdated;

  CloudSyncService(this._storage) {
    _statusController.add(_currentStatus);
    _startPeriodicSync();
  }

  Stream<SyncStatus> get statusStream => _statusController.stream;
  SyncStatus get status => _currentStatus;
  DateTime? get lastSyncedAt => _lastSyncedAt;

  void _setStatus(SyncStatus newStatus) {
    _currentStatus = newStatus;
    _statusController.add(newStatus);
  }

  /// Start background sync polling to pull changes made on other devices
  void _startPeriodicSync() {
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = Timer.periodic(CloudSyncConfig.backgroundSyncInterval, (_) async {
      final user = _storage.getCurrentUser();
      if (user != null && !user.isGuest) {
        await checkRemoteUpdates(user.id);
      }
    });
  }

  /// Sync a specific action immediately to the cloud
  Future<void> syncAction({
    required String userId,
    required String actionType, // 'item_update', 'item_delete', 'category_update', etc.
    required Map<String, dynamic> payload,
    required List<NeuroItem> currentLocalItems,
    required List<DailyCategory> currentLocalCategories,
  }) async {
    final user = _storage.getCurrentUser();
    if (user == null || user.isGuest) {
      _setStatus(SyncStatus.offline);
      return;
    }

    _setStatus(SyncStatus.syncing);

    try {
      // 1. Immediately mirror to user's isolated cloud vault
      await _storage.saveCloudVaultItems(userId, currentLocalItems);
      await _storage.saveCloudVaultCategories(userId, currentLocalCategories);

      // 2. If an external cloud endpoint is configured (Firestore / REST server), push HTTP mutation
      if (CloudSyncConfig.isExternalCloudConfigured) {
        final endpoint = '${CloudSyncConfig.cloudApiEndpoint}/users/$userId/sync';
        final response = await http.post(
          Uri.parse(endpoint),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'action': actionType,
            'timestamp': DateTime.now().toIso8601String(),
            'payload': payload,
            'items': currentLocalItems.map((e) => e.toMap()).toList(),
            'categories': currentLocalCategories.map((e) => e.toMap()).toList(),
          }),
        ).timeout(const Duration(seconds: 8));

        if (response.statusCode >= 400) {
          throw Exception('Cloud server error: ${response.statusCode}');
        }
      }

      _lastSyncedAt = DateTime.now();
      _setStatus(SyncStatus.synced);
    } catch (e) {
      // Enqueue mutation for guaranteed retry
      final queue = _storage.getPendingSyncQueue(userId);
      queue.add({
        'action': actionType,
        'timestamp': DateTime.now().toIso8601String(),
        'payload': payload,
      });
      await _storage.savePendingSyncQueue(userId, queue);
      _setStatus(SyncStatus.error);
    }
  }

  /// Reconcile and merge cloud data with local data without losing any items
  Future<CloudSyncResult> pullAndMerge({
    required String userId,
    required List<NeuroItem> localItems,
    required List<DailyCategory> localCategories,
  }) async {
    _setStatus(SyncStatus.syncing);

    try {
      List<NeuroItem> remoteItems = [];
      List<DailyCategory> remoteCategories = [];

      // Check external server if configured
      if (CloudSyncConfig.isExternalCloudConfigured) {
        try {
          final endpoint = '${CloudSyncConfig.cloudApiEndpoint}/users/$userId/data';
          final response = await http.get(Uri.parse(endpoint)).timeout(const Duration(seconds: 8));
          if (response.statusCode == 200) {
            final data = json.decode(response.body) as Map<String, dynamic>;
            if (data['items'] is List) {
              remoteItems = (data['items'] as List)
                  .map((e) => NeuroItem.fromMap(Map<String, dynamic>.from(e as Map)))
                  .toList();
            }
            if (data['categories'] is List) {
              remoteCategories = (data['categories'] as List)
                  .map((e) => DailyCategory.fromMap(Map<String, dynamic>.from(e as Map)))
                  .toList();
            }
          }
        } catch (_) {
          // Fall back to cloud vault snapshot if external server unreachable
        }
      }

      // If remote list empty from network, use Cloud Vault snapshot
      if (remoteItems.isEmpty) {
        remoteItems = _storage.getCloudVaultItems(userId);
      }
      if (remoteCategories.isEmpty) {
        remoteCategories = _storage.getCloudVaultCategories(userId);
      }

      // --- Conflict-Free Merge Algorithm for Items ---
      // Union of all items: preserve every unique item from both local and cloud
      final Map<String, NeuroItem> mergedItemMap = {};

      for (final local in localItems) {
        mergedItemMap[local.id] = local;
      }

      for (final remote in remoteItems) {
        if (!mergedItemMap.containsKey(remote.id)) {
          // Item added on another device: include it!
          mergedItemMap[remote.id] = remote;
        } else {
          // Item exists on both devices: resolve conflicts by taking the most up-to-date state
          final local = mergedItemMap[remote.id]!;
          final localDates = local.completedDates.toSet();
          final remoteDates = remote.completedDates.toSet();
          final unionCompletedDates = localDates.union(remoteDates).toList();

          final localFailed = local.failedDates.toSet();
          final remoteFailed = remote.failedDates.toSet();
          final unionFailedDates = localFailed.union(remoteFailed).toList();

          final mergedDailyNumeric = Map<String, double>.from(remote.dailyNumericValues)
            ..addAll(local.dailyNumericValues);

          final isNowCompleted = local.isCompleted || remote.isCompleted;
          final maxStreak = local.streakCount > remote.streakCount ? local.streakCount : remote.streakCount;

          mergedItemMap[remote.id] = local.copyWith(
            completedDates: unionCompletedDates,
            failedDates: unionFailedDates,
            dailyNumericValues: mergedDailyNumeric,
            isCompleted: isNowCompleted,
            streakCount: maxStreak,
          );
        }
      }

      final reconciledItems = mergedItemMap.values.toList();

      // --- Reconcile Categories ---
      final Map<String, DailyCategory> mergedCategoryMap = {};
      for (final local in localCategories) {
        mergedCategoryMap[local.id] = local;
      }
      for (final remote in remoteCategories) {
        if (!mergedCategoryMap.containsKey(remote.id)) {
          mergedCategoryMap[remote.id] = remote;
        }
      }
      final reconciledCategories = mergedCategoryMap.values.toList();

      // Save reconciled data back to local and cloud vault
      await _storage.saveAllItems(reconciledItems);
      await _storage.saveDailyCategories(reconciledCategories);
      await _storage.saveCloudVaultItems(userId, reconciledItems);
      await _storage.saveCloudVaultCategories(userId, reconciledCategories);

      _lastSyncedAt = DateTime.now();
      _setStatus(SyncStatus.synced);

      return CloudSyncResult(
        mergedItems: reconciledItems,
        mergedCategories: reconciledCategories,
        hasChanges: true,
      );
    } catch (e) {
      _setStatus(SyncStatus.error);
      return CloudSyncResult(
        mergedItems: localItems,
        mergedCategories: localCategories,
        hasChanges: false,
      );
    }
  }

  /// Check for remote updates from other devices and trigger UI update if changes found
  Future<void> checkRemoteUpdates(String userId) async {
    final localItems = _storage.getAllItems();
    final localCategories = _storage.getDailyCategories();

    final result = await pullAndMerge(
      userId: userId,
      localItems: localItems,
      localCategories: localCategories,
    );

    if (result.hasChanges && onRemoteDataUpdated != null) {
      onRemoteDataUpdated!(result.mergedItems, result.mergedCategories);
    }
  }

  /// Trigger manual two-way sync
  Future<CloudSyncResult> syncNow(String userId) async {
    final localItems = _storage.getAllItems();
    final localCategories = _storage.getDailyCategories();
    return pullAndMerge(
      userId: userId,
      localItems: localItems,
      localCategories: localCategories,
    );
  }

  void dispose() {
    _periodicSyncTimer?.cancel();
    _statusController.close();
  }
}
