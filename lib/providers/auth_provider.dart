import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_user.dart';
import '../services/auth_service.dart';
import '../services/cloud_sync_service.dart';
import 'neuro_providers.dart';

final authServiceProvider = Provider<AuthService>((ref) {
  final storage = ref.watch(storageServiceProvider);
  final authService = AuthService(storage);
  ref.onDispose(() => authService.dispose());
  return authService;
});

final syncStatusProvider = StreamProvider<SyncStatus>((ref) {
  final syncService = ref.watch(cloudSyncServiceProvider);
  return syncService.statusStream;
});

class AuthNotifier extends StateNotifier<AppUser?> {
  final AuthService _authService;
  final CloudSyncService _cloudSyncService;
  final Ref _ref;

  AuthNotifier(this._authService, this._cloudSyncService, this._ref)
      : super(_authService.currentUser) {
    _authService.authStateChanges.listen((user) {
      state = user;
    });
  }

  Future<void> signInWithGoogle({
    String? email,
    String? displayName,
    String? photoUrl,
  }) async {
    final user = await _authService.signInWithGoogle(
      email: email,
      displayName: displayName,
      photoUrl: photoUrl,
    );
    state = user;

    // Immediately pull and merge cloud data for this user
    await _pullUserData(user.id);
  }

  Future<void> signInWithEmail(String email, String password) async {
    final user = await _authService.signInWithEmail(email, password);
    state = user;
    await _pullUserData(user.id);
  }

  Future<void> signUpWithEmail(String email, String password, {String? displayName}) async {
    final user = await _authService.signUpWithEmail(email, password, displayName: displayName);
    state = user;
    await _pullUserData(user.id);
  }

  Future<void> signInAsGuest() async {
    final user = await _authService.signInAsGuest();
    state = user;
  }

  Future<void> signOut() async {
    await _authService.signOut();
    state = null;
  }

  Future<void> deleteAccount() async {
    final currentUser = state;
    if (currentUser != null) {
      await _authService.deleteAccount();
      _ref.read(neuroItemsProvider.notifier).setItems([]);
      _ref.read(dailyCategoriesProvider.notifier).setCategories([]);
      state = null;
    }
  }

  Future<void> syncNow() async {
    final user = state;
    if (user != null && !user.isGuest) {
      await _pullUserData(user.id);
    }
  }

  Future<void> _pullUserData(String userId) async {
    final localItems = _ref.read(neuroItemsProvider);
    final localCategories = _ref.read(dailyCategoriesProvider);

    final result = await _cloudSyncService.pullAndMerge(
      userId: userId,
      localItems: localItems,
      localCategories: localCategories,
    );

    if (result.hasChanges) {
      _ref.read(neuroItemsProvider.notifier).setItems(result.mergedItems);
      _ref.read(dailyCategoriesProvider.notifier).setCategories(result.mergedCategories);
    }
  }
}

final authNotifierProvider = StateNotifierProvider<AuthNotifier, AppUser?>((ref) {
  final authService = ref.watch(authServiceProvider);
  final syncService = ref.watch(cloudSyncServiceProvider);
  return AuthNotifier(authService, syncService, ref);
});
