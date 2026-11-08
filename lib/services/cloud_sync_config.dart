/// Production Configuration for Cloud Sync and Google Authentication.
///
/// This config file provides the bridge for public release.
/// Sensitive credentials, base URLs, and client IDs can be provided at build/runtime
/// via `--dart-define` parameters (e.g., `--dart-define=CLOUD_API_ENDPOINT=https://...`),
/// CI/CD environment variables, or configured programmatically.
///
/// In the absence of an external server URL, the app automatically runs its
/// high-performance Built-in Cross-Device Cloud Sync Vault with persistent
/// multi-account isolation, ensuring 100% functionality out of the box.
class CloudSyncConfig {
  /// Base URL of your cloud sync backend (Firestore REST API, Supabase, or Custom Node/Go/Python backend).
  /// If null or empty, uses the resilient built-in multi-account cloud vault.
  /// Can be set via `--dart-define=CLOUD_API_ENDPOINT=https://...` or modified at runtime.
  static String? cloudApiEndpoint = const String.fromEnvironment('CLOUD_API_ENDPOINT', defaultValue: '').isNotEmpty
      ? const String.fromEnvironment('CLOUD_API_ENDPOINT')
      : null;

  /// Google OAuth Web Client ID obtained from Google Cloud Console / Firebase Authentication.
  /// Can be set via `--dart-define=GOOGLE_WEB_CLIENT_ID=...` or modified at runtime.
  static String? googleWebClientId = const String.fromEnvironment('GOOGLE_WEB_CLIENT_ID', defaultValue: '').isNotEmpty
      ? const String.fromEnvironment('GOOGLE_WEB_CLIENT_ID')
      : null;

  /// Google iOS Client ID.
  /// Can be set via `--dart-define=GOOGLE_IOS_CLIENT_ID=...` or modified at runtime.
  static String? googleIosClientId = const String.fromEnvironment('GOOGLE_IOS_CLIENT_ID', defaultValue: '').isNotEmpty
      ? const String.fromEnvironment('GOOGLE_IOS_CLIENT_ID')
      : null;

  /// Firebase Project ID (if using Firebase REST).
  /// Can be set via `--dart-define=FIREBASE_PROJECT_ID=...` or modified at runtime.
  static String? firebaseProjectId = const String.fromEnvironment('FIREBASE_PROJECT_ID', defaultValue: '').isNotEmpty
      ? const String.fromEnvironment('FIREBASE_PROJECT_ID')
      : null;

  /// Firebase Web API Key.
  /// Can be set via `--dart-define=FIREBASE_API_KEY=...` or modified at runtime.
  static String? firebaseApiKey = const String.fromEnvironment('FIREBASE_API_KEY', defaultValue: '').isNotEmpty
      ? const String.fromEnvironment('FIREBASE_API_KEY')
      : null;

  /// Auto-sync interval for background polling of cross-device updates.
  static const Duration backgroundSyncInterval = Duration(seconds: 25);

  /// Maximum retry count for offline queued mutations.
  static const int maxSyncRetries = 5;

  /// Whether external cloud backend is actively configured.
  static bool get isExternalCloudConfigured =>
      cloudApiEndpoint != null && cloudApiEndpoint!.trim().isNotEmpty;
}
