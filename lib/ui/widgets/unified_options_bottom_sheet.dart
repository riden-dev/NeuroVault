import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class UnifiedOptionsBottomSheet {
  /// Standardized bottom sheet for long-pressing any folder or item across the app
  static void show({
    required BuildContext context,
    required String title,
    String? subtitle,
    required VoidCallback onEdit,
    required VoidCallback onDelete,
    VoidCallback? onToggleFailed,
    VoidCallback? onCompile,
    VoidCallback? onInsights,
    VoidCallback? onMoveToCategory,
    VoidCallback? onResetToUnmarked,
    bool isFailed = false,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle bar
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.textSecondary.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                if (subtitle != null && subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                const Divider(height: 1, color: Color(0xFF334155)),
                const SizedBox(height: 8),

                if (onInsights != null) ...[
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.insights_rounded, color: AppTheme.primaryAccent, size: 20),
                    ),
                    title: const Text('View Insights', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text('See charts and completion stats', style: TextStyle(fontSize: 11)),
                    onTap: () {
                      Navigator.pop(context);
                      onInsights();
                    },
                  ),
                ],

                if (onMoveToCategory != null) ...[
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.secondaryAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.label_rounded, color: AppTheme.secondaryAccent, size: 20),
                    ),
                    title: const Text('Assign to Category', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text('Group this item in daily track', style: TextStyle(fontSize: 11)),
                    onTap: () {
                      Navigator.pop(context);
                      onMoveToCategory();
                    },
                  ),
                ],

                if (onToggleFailed != null) ...[
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        isFailed ? Icons.refresh_rounded : Icons.cancel_outlined,
                        color: Colors.orangeAccent,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      isFailed ? 'Clear Failed Status' : 'Mark as Failed / Incomplete',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      isFailed ? 'Reset status to pending' : 'Flag this task as missed for today',
                      style: const TextStyle(fontSize: 11),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      onToggleFailed();
                    },
                  ),
                ],

                if (onResetToUnmarked != null) ...[
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blueGrey.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.restart_alt_rounded,
                        color: Colors.lightBlueAccent,
                        size: 20,
                      ),
                    ),
                    title: const Text('Reset to Unmarked', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text('Reset status to unmarked (clear completed & failed)', style: TextStyle(fontSize: 11)),
                    onTap: () {
                      Navigator.pop(context);
                      onResetToUnmarked();
                    },
                  ),
                ],

                if (onCompile != null) ...[
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.routineAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.drive_file_move_outlined, color: AppTheme.routineAccent, size: 20),
                    ),
                    title: const Text('Compile / Nest into Folder', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text('Move or group this button into another single button', style: TextStyle(fontSize: 11)),
                    onTap: () {
                      Navigator.pop(context);
                      onCompile();
                    },
                  ),
                ],

                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.edit_rounded, color: AppTheme.primaryAccent, size: 20),
                  ),
                  title: const Text('Edit Details', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Modify title, schedule, priority & settings', style: TextStyle(fontSize: 11)),
                  onTap: () {
                    Navigator.pop(context);
                    onEdit();
                  },
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent, size: 20),
                  ),
                  title: const Text('Delete', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Permanently remove this item', style: TextStyle(fontSize: 11)),
                  onTap: () {
                    Navigator.pop(context);
                    onDelete();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
