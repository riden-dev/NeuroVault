import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../providers/auth_provider.dart';
import '../../providers/neuro_providers.dart';
import '../../services/cloud_sync_service.dart';
import '../screens/auth_screen.dart';
import '../theme/app_theme.dart';

/// Modal dialog providing user profile overview, live cloud sync status,
/// manual sync trigger, account switching, and account deletion.
class AccountSyncDialog extends ConsumerStatefulWidget {
  const AccountSyncDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (context) => const AccountSyncDialog(),
    );
  }

  @override
  ConsumerState<AccountSyncDialog> createState() => _AccountSyncDialogState();
}

class _AccountSyncDialogState extends ConsumerState<AccountSyncDialog> {
  bool _isSyncingManual = false;

  Future<void> _handleManualSync() async {
    setState(() => _isSyncingManual = true);
    try {
      await ref.read(authNotifierProvider.notifier).syncNow();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cloud sync completed! All devices up to date.'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync error: $e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncingManual = false);
    }
  }

  void _showDeleteAccountConfirmDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Account & Cloud Data?', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent)),
        content: const Text(
          'This will permanently delete your cloud account, all saved habits, visions, routines, and categories. This action cannot be undone.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              Navigator.pop(ctx); // Close alert
              Navigator.pop(context); // Close dialog
              await ref.read(authNotifierProvider.notifier).deleteAccount();
              if (mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const AuthScreen()),
                  (route) => false,
                );
              }
            },
            child: const Text('Delete Permanently', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authNotifierProvider);
    final syncStatusAsync = ref.watch(syncStatusProvider);
    final syncStatus = syncStatusAsync.value ?? SyncStatus.synced;
    final syncService = ref.watch(cloudSyncServiceProvider);
    final totalItems = ref.watch(neuroItemsProvider).length;
    final totalCategories = ref.watch(dailyCategoriesProvider).length;

    final isGuest = user == null || user.isGuest;
    final displayName = user?.displayName ?? 'Guest User';
    final email = user?.email ?? 'Offline Session';

    Color statusColor;
    String statusLabel;
    IconData statusIcon;

    switch (syncStatus) {
      case SyncStatus.synced:
        statusColor = const Color(0xFF4ADE80); // Emerald green
        statusLabel = isGuest ? 'Local Vault (Offline)' : 'All Changes Synced to Cloud';
        statusIcon = Icons.cloud_done_rounded;
        break;
      case SyncStatus.syncing:
        statusColor = AppTheme.primaryAccent;
        statusLabel = 'Syncing with Cloud...';
        statusIcon = Icons.cloud_sync_rounded;
        break;
      case SyncStatus.offline:
        statusColor = const Color(0xFFFBBF24); // Amber
        statusLabel = 'Offline Mode (Saved Locally)';
        statusIcon = Icons.cloud_off_rounded;
        break;
      case SyncStatus.error:
        statusColor = Colors.orangeAccent;
        statusLabel = 'Sync Queued (Retrying)';
        statusIcon = Icons.cloud_queue_rounded;
        break;
    }

    final lastSyncText = syncService.lastSyncedAt != null
        ? DateFormat('h:mm a, MMM d').format(syncService.lastSyncedAt!)
        : 'Active';

    return Dialog(
      backgroundColor: AppTheme.surfaceColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // User Profile Header
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: isGuest
                      ? AppTheme.textSecondary.withValues(alpha: 0.3)
                      : AppTheme.primaryAccent.withValues(alpha: 0.2),
                  child: isGuest
                      ? const Icon(Icons.person_outline_rounded, color: AppTheme.textPrimary, size: 28)
                      : Text(
                          displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryAccent,
                          ),
                        ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        email,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: (isGuest ? Colors.amber : AppTheme.primaryAccent).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isGuest ? 'Guest / Offline Mode' : 'Google Account • Cloud Synced',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isGuest ? Colors.amber : AppTheme.primaryAccent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),
            const Divider(color: Color(0xFF334155), height: 1),
            const SizedBox(height: 16),

            // Live Cloud Sync Status Box
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.backgroundColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: statusColor.withValues(alpha: 0.3), width: 1.2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(statusIcon, color: statusColor, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          statusLabel,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: statusColor,
                          ),
                        ),
                      ),
                      if (!isGuest)
                        InkWell(
                          onTap: _isSyncingManual ? null : _handleManualSync,
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: _isSyncingManual
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryAccent),
                                  )
                                : const Icon(Icons.refresh_rounded, size: 18, color: AppTheme.primaryAccent),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Last sync: $lastSyncText',
                        style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                      ),
                      Text(
                        '$totalItems tasks • $totalCategories categories',
                        style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Account Actions
            if (isGuest) ...[
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryAccent,
                  foregroundColor: AppTheme.backgroundColor,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                label: const Text('Connect Google Account', style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AuthScreen()),
                  );
                },
              ),
              const SizedBox(height: 10),
            ] else ...[
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primaryAccent,
                  side: const BorderSide(color: AppTheme.primaryAccent, width: 1.2),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.sync_rounded, size: 18),
                label: Text(_isSyncingManual ? 'Syncing...' : 'Sync Cloud Now', style: const TextStyle(fontWeight: FontWeight.bold)),
                onPressed: _isSyncingManual ? null : _handleManualSync,
              ),
              const SizedBox(height: 10),
            ],

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.textSecondary,
                      side: const BorderSide(color: Color(0xFF334155)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AuthScreen()),
                      );
                    },
                    child: const Text('Switch Account'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.5)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () async {
                      Navigator.pop(context);
                      await ref.read(authNotifierProvider.notifier).signOut();
                      if (context.mounted) {
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(builder: (_) => const AuthScreen()),
                          (route) => false,
                        );
                      }
                    },
                    child: const Text('Sign Out'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Delete Account / Data Compliance Link
            Center(
              child: TextButton(
                onPressed: _showDeleteAccountConfirmDialog,
                child: const Text(
                  'Delete Account & Cloud Data',
                  style: TextStyle(fontSize: 11, color: Colors.redAccent),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
