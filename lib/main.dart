import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/neuro_providers.dart';
import 'services/hive_storage_service.dart';
import 'ui/screens/auth_screen.dart';
import 'ui/screens/daily_track_screen.dart';
import 'ui/screens/home_screen.dart';
import 'ui/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storageService = HiveStorageService();
  await storageService.init();

  final bool hasLaunchedBefore = storageService.hasLaunchedBefore;
  if (!hasLaunchedBefore) {
    await storageService.setLaunchedBefore();
  }

  final currentUser = storageService.getCurrentUser();
  final bool hasSession = currentUser != null;

  runApp(
    ProviderScope(
      overrides: [
        storageServiceProvider.overrideWithValue(storageService),
      ],
      child: NeurovaultApp(
        hasLaunchedBefore: hasLaunchedBefore,
        hasSession: hasSession,
      ),
    ),
  );
}

class NeurovaultApp extends StatelessWidget {
  final bool hasLaunchedBefore;
  final bool hasSession;

  const NeurovaultApp({
    super.key,
    this.hasLaunchedBefore = false,
    this.hasSession = false,
  });

  @override
  Widget build(BuildContext context) {
    Widget homeScreen;
    if (!hasSession && !hasLaunchedBefore) {
      homeScreen = const AuthScreen();
    } else if (hasLaunchedBefore) {
      homeScreen = const DailyTrackScreen();
    } else {
      homeScreen = const HomeScreen();
    }

    return MaterialApp(
      title: 'Neurovault',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: homeScreen,
    );
  }
}
