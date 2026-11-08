import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/neuro_providers.dart';
import '../../providers/auth_provider.dart';
import '../../services/cloud_sync_service.dart';
import '../widgets/account_sync_dialog.dart';
import '../theme/app_theme.dart';
import 'daily_track_screen.dart';
import 'goal_progress_screen.dart';
import 'routine_track_screen.dart';
import 'todo_list_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todayProgress = ref.watch(todayProgressProvider);
    final todayProgressText = ref.watch(todayProgressTextProvider);
    final routinesProgress = ref.watch(overallRoutinesProgressProvider);
    final routinesProgressText = ref.watch(overallRoutinesProgressTextProvider);
    final visionsProgress = ref.watch(overallVisionsProgressProvider);
    final visionsProgressText = ref.watch(overallVisionsProgressTextProvider);
    final dailyTrackProgress = ref.watch(dailyTrackProgressProvider);
    final dailyTrackProgressText = ref.watch(dailyTrackProgressTextProvider);

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              // App Header with Account & Sync button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox(width: 36), // Balance spacer
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          'Focus Space',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                letterSpacing: -0.5,
                                color: AppTheme.textPrimary,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Select a module to continue',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: AppTheme.textSecondary,
                              ),
                        ),
                      ],
                    ),
                  ),
                  _buildAccountSyncButton(context, ref),
                ],
              ),
              const SizedBox(height: 24),

              // Button 1: Visions (Master Planning Folder)
              _MenuButton(
                title: 'Visions',
                subtitle: 'Master Planning • Tree Distribution Engine',
                icon: Icons.account_tree_outlined,
                accentColor: AppTheme.primaryAccent,
                progressBarValue: visionsProgress,
                progressLabelText: visionsProgressText,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const GoalProgressScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),

              // Button 2: Routines (Master Planning Folder)
              _MenuButton(
                title: 'Routines',
                subtitle: 'Master Planning • Habits & Repetitive Tasks',
                icon: Icons.repeat_rounded,
                accentColor: AppTheme.routineAccent,
                progressBarValue: routinesProgress,
                progressLabelText: routinesProgressText,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const RoutineTrackScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),

              // Button 3: To-Do List
              _MenuButton(
                title: 'To-Do List',
                subtitle: 'Daily Task Management & Flex Tab',
                icon: Icons.check_circle_outline_rounded,
                accentColor: AppTheme.secondaryAccent,
                progressBarValue: todayProgress,
                progressLabelText: todayProgressText,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const TodoListScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),

              // NEW Button 4: Daily Track (Central Execution Hub!)
              _MenuButton(
                title: 'Daily Track',
                subtitle: 'Central Daily Execution • Rolling Calendar',
                icon: Icons.track_changes_rounded,
                accentColor: Colors.amberAccent,
                progressBarValue: dailyTrackProgress,
                progressLabelText: dailyTrackProgressText,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const DailyTrackScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAccountSyncButton(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authNotifierProvider);
    final syncStatusAsync = ref.watch(syncStatusProvider);
    final syncStatus = syncStatusAsync.value ?? SyncStatus.synced;

    Color badgeColor;
    switch (syncStatus) {
      case SyncStatus.synced:
        badgeColor = const Color(0xFF4ADE80);
        break;
      case SyncStatus.syncing:
        badgeColor = AppTheme.primaryAccent;
        break;
      case SyncStatus.offline:
        badgeColor = const Color(0xFFFBBF24);
        break;
      case SyncStatus.error:
        badgeColor = Colors.orangeAccent;
        break;
    }

    final isGuest = user == null || user.isGuest;
    final initials = user != null && user.displayName.isNotEmpty
        ? user.displayName[0].toUpperCase()
        : 'G';

    return InkWell(
      onTap: () => AccountSyncDialog.show(context),
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(4.0),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: isGuest
                  ? AppTheme.textSecondary.withValues(alpha: 0.25)
                  : AppTheme.primaryAccent.withValues(alpha: 0.25),
              child: isGuest
                  ? const Icon(Icons.person_outline_rounded, size: 18, color: AppTheme.textSecondary)
                  : Text(
                      initials,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryAccent,
                      ),
                    ),
            ),
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: badgeColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.backgroundColor, width: 1.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accentColor;
  final double? progressBarValue;
  final String? progressLabelText;
  final VoidCallback onTap;

  const _MenuButton({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    this.progressBarValue,
    this.progressLabelText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20.0),
        child: Ink(
          padding: const EdgeInsets.all(20.0),
          decoration: BoxDecoration(
            color: AppTheme.surfaceColor,
            borderRadius: BorderRadius.circular(20.0),
            border: Border.all(
              color: accentColor.withValues(alpha: 0.3),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: accentColor.withValues(alpha: 0.05),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(14.0),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16.0),
                    ),
                    child: Icon(
                      icon,
                      color: accentColor,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppTheme.textSecondary,
                    size: 24,
                  ),
                ],
              ),
              if (progressBarValue != null) ...[
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Completion Progress',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      progressLabelText ?? '${(progressBarValue! * 100).toInt()}%',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: progressBarValue! < 0
                            ? Colors.redAccent
                            : (progressBarValue! == 1.0
                                ? AppTheme.routineAccent
                                : accentColor),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6.0),
                  child: LinearProgressIndicator(
                    value: progressBarValue!.abs().clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: AppTheme.backgroundColor,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      progressBarValue! < 0
                          ? Colors.redAccent
                          : (progressBarValue! == 1.0
                              ? AppTheme.routineAccent
                              : accentColor),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
