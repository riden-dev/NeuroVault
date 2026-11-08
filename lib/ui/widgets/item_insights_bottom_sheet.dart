import 'package:flutter/material.dart';
import '../../models/neuro_item.dart';
import '../../services/aggregation_engine.dart';
import '../theme/app_theme.dart';

class ItemInsightsBottomSheet extends StatelessWidget {
  final NeuroItem item;
  final List<NeuroItem> allItems;

  const ItemInsightsBottomSheet({
    super.key,
    required this.item,
    required this.allItems,
  });

  static void show(
    BuildContext context, {
    required NeuroItem item,
    required List<NeuroItem> allItems,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => ItemInsightsBottomSheet(
        item: item,
        allItems: allItems,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Map<String, dynamic> insights;
    try {
      insights = AggregationEngine.calculateItemInsights(
        item: item,
        allItems: allItems,
        lookbackDays: 90,
      );
    } catch (_) {
      insights = {
        'completionRate': 0.0,
        'totalScheduled': 0,
        'totalCompleted': 0.0,
        'totalFailed': 0,
        'currentStreak': 0,
        'bestStreak': 0,
        'successRate': 0.0,
        'avgPerWeek': 0.0,
        'consistencyScore': 0.0,
        'dayOfWeekCompletions': <int, int>{},
        'totalDays': 0,
        'totalItems': 0,
        'completedItems': 0,
        'activeItems': 0,
        'isFolder': item.type == NeuroItemType.routineFolder || item.type == NeuroItemType.vision,
      };
    }

    final isFolder = insights['isFolder'] as bool? ?? false;
    final completionRate = (insights['completionRate'] as num?)?.toDouble() ?? 0.0;

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppTheme.surfaceColor,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              // Drag Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.textSecondary.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Sheet Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _getItemColor().withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(_getItemIcon(), color: _getItemColor(), size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _getItemColor().withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  item.type.name.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: _getItemColor(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isFolder ? 'Folder Insights' : 'Item Analytics',
                                style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: AppTheme.textSecondary),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),
              const Divider(height: 1, color: Color(0xFF334155)),

              // Content Body
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20.0),
                  children: [
                    if (isFolder)
                      _buildFolderInsights(insights, completionRate)
                    else
                      _buildItemInsights(insights, completionRate),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFolderInsights(Map<String, dynamic> insights, double completionRate) {
    final totalItems = (insights['totalItems'] as num?)?.toInt() ?? 0;
    final completedItems = (insights['completedItems'] as num?)?.toInt() ?? 0;
    final activeItems = (insights['activeItems'] as num?)?.toInt() ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Big Progress Card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.backgroundColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _getItemColor().withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Overall Progress',
                        style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${(completionRate * 100).toInt()}%',
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          color: _getItemColor(),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(
                    width: 60,
                    height: 60,
                    child: CircularProgressIndicator(
                      value: completionRate,
                      strokeWidth: 6,
                      backgroundColor: const Color(0xFF334155),
                      valueColor: AlwaysStoppedAnimation<Color>(_getItemColor()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: completionRate,
                  minHeight: 8,
                  backgroundColor: const Color(0xFF334155),
                  valueColor: AlwaysStoppedAnimation<Color>(_getItemColor()),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),
        const Text(
          'Hierarchy Breakdown',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        ),
        const SizedBox(height: 12),

        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                title: 'Total Items',
                value: '$totalItems',
                icon: Icons.list_alt_rounded,
                color: AppTheme.primaryAccent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricCard(
                title: 'Completed',
                value: '$completedItems',
                icon: Icons.check_circle_rounded,
                color: Colors.greenAccent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricCard(
                title: 'Active / Pending',
                value: '$activeItems',
                icon: Icons.pending_actions_rounded,
                color: Colors.orangeAccent,
              ),
            ),
          ],
        ),

        const SizedBox(height: 24),
        const Text(
          'Settings & Contribution',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.backgroundColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              _buildSettingRow(
                label: 'Success Contributes to Progress',
                enabled: item.successContributesToProgress,
                activeColor: Colors.greenAccent,
              ),
              const Divider(color: Color(0xFF334155)),
              _buildSettingRow(
                label: 'Failure Penalizes Progress',
                enabled: item.failureContributesToProgress,
                activeColor: Colors.redAccent,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildItemInsights(Map<String, dynamic> insights, double completionRate) {
    final totalScheduled = (insights['totalScheduled'] as num?)?.toInt() ?? 0;
    final totalCompleted = (insights['totalCompleted'] as num?)?.toDouble() ?? 0.0;
    final totalFailed = (insights['totalFailed'] as num?)?.toInt() ?? 0;
    final currentStreak = (insights['currentStreak'] as num?)?.toInt() ?? 0;
    final bestStreak = (insights['bestStreak'] as num?)?.toInt() ?? 0;
    final successRate = (insights['successRate'] as num?)?.toDouble() ?? 0.0;
    final avgPerWeek = (insights['avgPerWeek'] as num?)?.toDouble() ?? 0.0;
    final consistencyScore = (insights['consistencyScore'] as num?)?.toDouble() ?? 0.0;
    final dayOfWeekCompletions = (insights['dayOfWeekCompletions'] as Map<dynamic, dynamic>?)?.map(
      (k, v) => MapEntry((k as num).toInt(), (v as num).toInt()),
    ) ?? <int, int>{};

    final completedDisplay = (totalCompleted % 1 == 0)
        ? '${totalCompleted.toInt()}'
        : totalCompleted.toStringAsFixed(1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Primary Score Card
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppTheme.backgroundColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _getItemColor().withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Consistency Score',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${(consistencyScore * 100).toInt()}%',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: _getItemColor(),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Avg ${avgPerWeek.toStringAsFixed(1)} completions / week',
                    style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                  ),
                ],
              ),
              Column(
                children: [
                  Row(
                    children: [
                      const Text('🔥 ', style: TextStyle(fontSize: 18)),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('$currentStreak d', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.orangeAccent)),
                          const Text('Current Streak', style: TextStyle(fontSize: 9, color: AppTheme.textSecondary)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Text('🏆 ', style: TextStyle(fontSize: 18)),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('$bestStreak d', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.amberAccent)),
                          const Text('Best Streak', style: TextStyle(fontSize: 9, color: AppTheme.textSecondary)),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),
        const Text(
          'Completion Statistics (90-Day Lookback)',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        ),
        const SizedBox(height: 12),

        // Metrics Grid
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                title: 'Scheduled',
                value: '$totalScheduled',
                icon: Icons.calendar_today_rounded,
                color: AppTheme.primaryAccent,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildMetricCard(
                title: 'Completed',
                value: completedDisplay,
                icon: Icons.check_circle_rounded,
                color: Colors.greenAccent,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildMetricCard(
                title: 'Missed/Failed',
                value: '$totalFailed',
                icon: Icons.cancel_rounded,
                color: Colors.redAccent,
              ),
            ),
          ],
        ),

        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                title: 'Success Rate',
                value: '${(successRate * 100).toInt()}%',
                icon: Icons.trending_up_rounded,
                color: Colors.tealAccent,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildMetricCard(
                title: 'Priority',
                value: 'P${item.priority}',
                icon: Icons.flag_rounded,
                color: AppTheme.secondaryAccent,
              ),
            ),
          ],
        ),

        const SizedBox(height: 22),
        const Text(
          'Weekly Consistency Heatmap',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        ),
        const SizedBox(height: 10),

        // Day of week heatmap chips
        Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
          decoration: BoxDecoration(
            color: AppTheme.backgroundColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildDayChip('M', dayOfWeekCompletions[1] ?? 0),
              _buildDayChip('T', dayOfWeekCompletions[2] ?? 0),
              _buildDayChip('W', dayOfWeekCompletions[3] ?? 0),
              _buildDayChip('T', dayOfWeekCompletions[4] ?? 0),
              _buildDayChip('F', dayOfWeekCompletions[5] ?? 0),
              _buildDayChip('S', dayOfWeekCompletions[6] ?? 0),
              _buildDayChip('S', dayOfWeekCompletions[7] ?? 0),
            ],
          ),
        ),

        const SizedBox(height: 22),
        const Text(
          'Progress Bar Contribution',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.backgroundColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              _buildSettingRow(
                label: 'Success contributes to progress',
                enabled: item.successContributesToProgress,
                activeColor: Colors.greenAccent,
              ),
              const Divider(color: Color(0xFF334155)),
              _buildSettingRow(
                label: 'Failure affects progress',
                enabled: item.failureContributesToProgress,
                activeColor: Colors.redAccent,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDayChip(String label, int count) {
    final bool hasCompletions = count > 0;
    return Column(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: hasCompletions
                ? _getItemColor().withValues(alpha: (0.2 + (count * 0.15)).clamp(0.2, 1.0))
                : const Color(0xFF334155).withValues(alpha: 0.5),
            shape: BoxShape.circle,
            border: Border.all(
              color: hasCompletions ? _getItemColor() : Colors.transparent,
              width: 1,
            ),
          ),
          child: Center(
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: hasCompletions ? Colors.white : AppTheme.textSecondary,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.backgroundColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingRow({
    required String label,
    required bool enabled,
    required Color activeColor,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: enabled ? activeColor.withValues(alpha: 0.15) : Colors.grey.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                enabled ? Icons.check_circle_outline : Icons.cancel_outlined,
                size: 14,
                color: enabled ? activeColor : AppTheme.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                enabled ? 'Enabled' : 'Disabled',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: enabled ? activeColor : AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Color _getItemColor() {
    if (item.colorHex != null) return Color(item.colorHex!);
    switch (item.type) {
      case NeuroItemType.vision:
        return AppTheme.primaryAccent;
      case NeuroItemType.routineFolder:
      case NeuroItemType.routine:
        return AppTheme.routineAccent;
      case NeuroItemType.task:
        return AppTheme.secondaryAccent;
      case NeuroItemType.goal:
        return const Color(0xFFF59E0B);
      case NeuroItemType.list:
        return Colors.tealAccent;
    }
  }

  IconData _getItemIcon() {
    switch (item.type) {
      case NeuroItemType.vision:
        return Icons.account_tree_outlined;
      case NeuroItemType.routineFolder:
        return Icons.folder_special_rounded;
      case NeuroItemType.routine:
        return Icons.repeat_rounded;
      case NeuroItemType.task:
        return Icons.check_circle_outline_rounded;
      case NeuroItemType.goal:
        return Icons.flag_rounded;
      case NeuroItemType.list:
        return Icons.checklist_rounded;
    }
  }
}
