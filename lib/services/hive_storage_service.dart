import 'package:hive_flutter/hive_flutter.dart';
import '../models/neuro_item.dart';
import '../models/app_user.dart';

class HiveStorageService {
  static const String _boxName = 'neuro_items_box';
  static const String _metaBoxName = 'neuro_meta_box';
  static const String _userBoxName = 'neuro_user_box';
  static const String _cloudVaultBoxName = 'neuro_cloud_vault_box';
  Box? _box;
  Box? _metaBox;
  Box? _userBox;
  Box? _cloudVaultBox;

  Future<void> init() async {
    await Hive.initFlutter();
    _box = await Hive.openBox(_boxName);
    _metaBox = await Hive.openBox(_metaBoxName);
    _userBox = await Hive.openBox(_userBoxName);
    _cloudVaultBox = await Hive.openBox(_cloudVaultBoxName);
  }

  bool get hasSeeded => _metaBox?.get('has_seeded_v1', defaultValue: false) as bool? ?? false;

  Future<void> setSeeded() async {
    await _metaBox?.put('has_seeded_v1', true);
  }

  bool get hasLaunchedBefore => _metaBox?.get('has_launched_before', defaultValue: false) as bool? ?? false;

  Future<void> setLaunchedBefore() async {
    await _metaBox?.put('has_launched_before', true);
  }

  List<NeuroItem> getAllItems() {
    if (_box == null) return [];
    final rawList = _box!.values.toList();
    return rawList
        .map((e) => NeuroItem.fromJson(e as String))
        .toList();
  }

  Future<void> saveItem(NeuroItem item) async {
    if (_box == null) return;
    await _box!.put(item.id, item.toJson());
  }

  Future<void> saveAllItems(List<NeuroItem> items) async {
    if (_box == null) return;
    await _box!.clear();
    final Map<String, String> map = {
      for (var item in items) item.id: item.toJson()
    };
    await _box!.putAll(map);
  }

  Future<void> deleteItem(String id) async {
    if (_box == null) return;
    await _box!.delete(id);
  }

  List<String> getDailyCategoryOrder() {
    if (_metaBox == null) return [];
    final raw = _metaBox!.get('daily_category_order');
    if (raw is List) {
      return raw.map((e) => e.toString()).toList();
    }
    return [];
  }

  Future<void> saveDailyCategoryOrder(List<String> order) async {
    await _metaBox?.put('daily_category_order', order);
  }

  bool getShowDailyCategories() {
    return _metaBox?.get('show_daily_categories', defaultValue: true) as bool? ?? true;
  }

  Future<void> saveShowDailyCategories(bool show) async {
    await _metaBox?.put('show_daily_categories', show);
  }

  int getDailyViewMode() {
    if (_metaBox == null) return 0;
    final val = _metaBox!.get('daily_view_mode');
    if (val is int && val >= 0 && val <= 2) return val;
    final show = _metaBox!.get('show_daily_categories') as bool?;
    if (show == false) return 1;
    return 0;
  }

  Future<void> saveDailyViewMode(int mode) async {
    await _metaBox?.put('daily_view_mode', mode);
    await _metaBox?.put('show_daily_categories', mode == 0);
  }

  List<String> getCollapsedCategoryIds() {
    if (_metaBox == null) return [];
    final raw = _metaBox!.get('collapsed_category_ids');
    if (raw is List) {
      return raw.map((e) => e.toString()).toList();
    }
    return [];
  }

  Future<void> saveCollapsedCategoryIds(List<String> ids) async {
    await _metaBox?.put('collapsed_category_ids', ids);
  }

  List<String> getExpandedChecklistItemIds() {
    if (_metaBox == null) return [];
    final raw = _metaBox!.get('expanded_checklist_item_ids');
    if (raw is List) {
      return raw.map((e) => e.toString()).toList();
    }
    return [];
  }

  Future<void> saveExpandedChecklistItemIds(List<String> ids) async {
    await _metaBox?.put('expanded_checklist_item_ids', ids);
  }

  Future<void> clearAll() async {
    if (_box == null) return;
    await _box!.clear();
  }

  List<DailyCategory> getDailyCategories() {
    if (_metaBox == null) return [];
    final raw = _metaBox!.get('daily_categories');
    if (raw is List) {
      return raw.map((e) => DailyCategory.fromMap(Map<String, dynamic>.from(e as Map))).toList();
    }
    return [];
  }

  Future<void> saveDailyCategories(List<DailyCategory> categories) async {
    await _metaBox?.put('daily_categories', categories.map((c) => c.toMap()).toList());
  }

  String getCustomUngroupedName() {
    if (_metaBox == null) return 'Ungrouped Tasks';
    return _metaBox!.get('custom_ungrouped_name', defaultValue: 'Ungrouped Tasks') as String? ?? 'Ungrouped Tasks';
  }

  Future<void> saveCustomUngroupedName(String name) async {
    await _metaBox?.put('custom_ungrouped_name', name);
  }

  int? getCustomUngroupedColor() {
    if (_metaBox == null) return null;
    return _metaBox!.get('custom_ungrouped_color') as int?;
  }

  Future<void> saveCustomUngroupedColor(int? colorHex) async {
    await _metaBox?.put('custom_ungrouped_color', colorHex);
  }

  bool getIsUngroupedCategoryDeleted() {
    if (_metaBox == null) return false;
    return _metaBox!.get('is_ungrouped_category_deleted', defaultValue: false) as bool? ?? false;
  }

  Future<void> saveIsUngroupedCategoryDeleted(bool deleted) async {
    await _metaBox?.put('is_ungrouped_category_deleted', deleted);
  }

  int getCustomUngroupedPriority() {
    if (_metaBox == null) return 50;
    return _metaBox!.get('custom_ungrouped_priority', defaultValue: 50) as int? ?? 50;
  }

  Future<void> saveCustomUngroupedPriority(int priority) async {
    await _metaBox?.put('custom_ungrouped_priority', priority);
  }

  // --- User Session Persistence ---
  AppUser? getCurrentUser() {
    if (_userBox == null) return null;
    final raw = _userBox!.get('current_user');
    if (raw is String) {
      try {
        return AppUser.fromJson(raw);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  Future<void> saveCurrentUser(AppUser? user) async {
    if (_userBox == null) return;
    if (user == null) {
      await _userBox!.delete('current_user');
    } else {
      await _userBox!.put('current_user', user.toJson());
    }
  }

  // --- Per-User Cloud Vault (Local Cross-Device Cloud Mirror) ---
  List<NeuroItem> getCloudVaultItems(String userId) {
    if (_cloudVaultBox == null) return [];
    final raw = _cloudVaultBox!.get('cloud_items_$userId');
    if (raw is List) {
      return raw.map((e) => NeuroItem.fromJson(e as String)).toList();
    }
    return [];
  }

  Future<void> saveCloudVaultItems(String userId, List<NeuroItem> items) async {
    if (_cloudVaultBox == null) return;
    await _cloudVaultBox!.put('cloud_items_$userId', items.map((e) => e.toJson()).toList());
  }

  List<DailyCategory> getCloudVaultCategories(String userId) {
    if (_cloudVaultBox == null) return [];
    final raw = _cloudVaultBox!.get('cloud_cats_$userId');
    if (raw is List) {
      return raw.map((e) => DailyCategory.fromMap(Map<String, dynamic>.from(e as Map))).toList();
    }
    return [];
  }

  Future<void> saveCloudVaultCategories(String userId, List<DailyCategory> categories) async {
    if (_cloudVaultBox == null) return;
    await _cloudVaultBox!.put('cloud_cats_$userId', categories.map((e) => e.toMap()).toList());
  }

  List<Map<String, dynamic>> getPendingSyncQueue(String userId) {
    if (_metaBox == null) return [];
    final raw = _metaBox!.get('sync_queue_$userId');
    if (raw is List) {
      return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  Future<void> savePendingSyncQueue(String userId, List<Map<String, dynamic>> queue) async {
    if (_metaBox == null) return;
    await _metaBox!.put('sync_queue_$userId', queue);
  }

  Future<void> deleteUserData(String userId) async {
    if (_cloudVaultBox != null) {
      await _cloudVaultBox!.delete('cloud_items_$userId');
      await _cloudVaultBox!.delete('cloud_cats_$userId');
    }
    if (_metaBox != null) {
      await _metaBox!.delete('sync_queue_$userId');
    }
    final current = getCurrentUser();
    if (current?.id == userId) {
      await saveCurrentUser(null);
      await clearAll();
    }
  }
}
