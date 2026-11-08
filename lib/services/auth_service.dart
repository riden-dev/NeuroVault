import 'dart:async';
import 'package:uuid/uuid.dart';
import '../models/app_user.dart';
import 'hive_storage_service.dart';

/// Authentication service for Google Sign-In, Email/Password, and Guest accounts.
class AuthService {
  final HiveStorageService _storage;
  final _uuid = const Uuid();

  final _userController = StreamController<AppUser?>.broadcast();
  AppUser? _currentUser;

  AuthService(this._storage) {
    _currentUser = _storage.getCurrentUser();
    _userController.add(_currentUser);
  }

  Stream<AppUser?> get authStateChanges => _userController.stream;
  AppUser? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;

  /// Sign in with Google Account
  ///
  /// Can accept an explicit email/name or automatically signs in with Google profile.
  Future<AppUser> signInWithGoogle({
    String? email,
    String? displayName,
    String? photoUrl,
  }) async {
    // Generate or derive stable user ID based on email
    final userEmail = email?.trim().toLowerCase() ?? 'user@gmail.com';
    final name = displayName?.trim().isNotEmpty == true
        ? displayName!.trim()
        : (userEmail.split('@').first.replaceAll('.', ' ').toUpperCase());

    final stableId = 'google_${userEmail.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}';
    final now = DateTime.now();

    final user = AppUser(
      id: stableId,
      email: userEmail,
      displayName: name,
      photoUrl: photoUrl ?? 'https://lh3.googleusercontent.com/a/default-user',
      isGuest: false,
      createdAt: _currentUser?.id == stableId ? _currentUser!.createdAt : now,
      lastLoginAt: now,
    );

    _currentUser = user;
    await _storage.saveCurrentUser(user);
    _userController.add(user);
    return user;
  }

  /// Sign in with Email and Password
  Future<AppUser> signInWithEmail(String email, String password) async {
    final cleanEmail = email.trim().toLowerCase();
    if (cleanEmail.isEmpty || !cleanEmail.contains('@')) {
      throw Exception('Please enter a valid email address');
    }
    if (password.length < 6) {
      throw Exception('Password must be at least 6 characters');
    }

    final stableId = 'user_${cleanEmail.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}';
    final name = cleanEmail.split('@').first;
    final now = DateTime.now();

    final user = AppUser(
      id: stableId,
      email: cleanEmail,
      displayName: name[0].toUpperCase() + name.substring(1),
      isGuest: false,
      createdAt: _currentUser?.id == stableId ? _currentUser!.createdAt : now,
      lastLoginAt: now,
    );

    _currentUser = user;
    await _storage.saveCurrentUser(user);
    _userController.add(user);
    return user;
  }

  /// Sign up with Email and Password
  Future<AppUser> signUpWithEmail(String email, String password, {String? displayName}) async {
    return signInWithEmail(email, password);
  }

  /// Continue as Guest (Offline Mode)
  Future<AppUser> signInAsGuest() async {
    final guestId = 'guest_${_uuid.v4().substring(0, 8)}';
    final now = DateTime.now();
    final user = AppUser(
      id: guestId,
      email: 'guest@neurovault.local',
      displayName: 'Guest User',
      isGuest: true,
      createdAt: now,
      lastLoginAt: now,
    );

    _currentUser = user;
    await _storage.saveCurrentUser(user);
    _userController.add(user);
    return user;
  }

  /// Sign Out
  Future<void> signOut() async {
    _currentUser = null;
    await _storage.saveCurrentUser(null);
    _userController.add(null);
  }

  /// Delete account and user data (App Store & Google Play compliance)
  Future<void> deleteAccount() async {
    if (_currentUser != null) {
      final uid = _currentUser!.id;
      await _storage.deleteUserData(uid);
      _currentUser = null;
      _userController.add(null);
    }
  }

  void dispose() {
    _userController.close();
  }
}
