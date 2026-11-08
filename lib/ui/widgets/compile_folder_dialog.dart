import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../models/neuro_item.dart';
import '../../providers/neuro_providers.dart';
import '../../services/aggregation_engine.dart';
import '../theme/app_theme.dart';

class CompileFolderHelper {
  /// Dialog for compiling/nesting a button inside another single button or wrapper container
  static void showCompileDialog({
    required BuildContext context,
    required NeuroItem sourceItem,
    required List<NeuroItem> availableFolders,
    required List<NeuroItem> allItems,
    required NeuroItemsNotifier notifier,
  }) {
    final descendantIds = AggregationEngine.getDescendants(sourceItem.id, allItems)
        .map((e) => e.id)
        .toSet();

    final otherFolders = availableFolders.where((f) {
      if (f.id == sourceItem.id) return false;
      if (descendantIds.contains(f.id)) return false;
      return true;
    }).toList();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: Text('Compile "${sourceItem.title}"', style: const TextStyle(fontSize: 16)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Compile/Move this button inside another single button or wrapper container:',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 14),

              // Option 1: Compile into New Container Button
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryAccent,
                  minimumSize: const Size(double.infinity, 42),
                ),
                icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                label: const Text('Compile into New Container Button', style: TextStyle(fontSize: 12)),
                onPressed: () {
                  Navigator.pop(context);
                  _showCreateWrapperDialog(
                    context: context,
                    sourceItem: sourceItem,
                    notifier: notifier,
                  );
                },
              ),

              // Option 2: Move to Top Level (if currently nested)
              if (sourceItem.parentId != null) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.secondaryAccent,
                    side: const BorderSide(color: AppTheme.secondaryAccent),
                    minimumSize: const Size(double.infinity, 42),
                  ),
                  icon: const Icon(Icons.unarchive_outlined, size: 18),
                  label: const Text('Move to Top Level (Main Screen)', style: TextStyle(fontSize: 12)),
                  onPressed: () {
                    notifier.updateItem(sourceItem.copyWith(parentId: null));
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Moved "${sourceItem.title}" to Top Level')),
                    );
                  },
                ),
              ],

              // Option 3: Compile into an existing folder
              if (otherFolders.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('Select Existing Button to Compile Into:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                ...otherFolders.map((f) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        f.type == NeuroItemType.vision
                            ? Icons.account_tree_outlined
                            : Icons.folder_special_rounded,
                        color: f.type == NeuroItemType.vision
                            ? AppTheme.primaryAccent
                            : AppTheme.routineAccent,
                      ),
                      title: Text(f.title, style: const TextStyle(fontSize: 13)),
                      subtitle: Text('P${f.priority}', style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                      onTap: () {
                        notifier.updateItem(sourceItem.copyWith(parentId: f.id));
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Compiled "${sourceItem.title}" inside "${f.title}"')),
                        );
                      },
                    )),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ],
      ),
    );
  }

  static void _showCreateWrapperDialog({
    required BuildContext context,
    required NeuroItem sourceItem,
    required NeuroItemsNotifier notifier,
  }) {
    final titleController = TextEditingController(text: 'Master ${sourceItem.title} Group');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: const Text('New Container Button Title', style: TextStyle(fontSize: 15)),
        content: TextField(
          controller: titleController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Container Button Name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final newTitle = titleController.text.trim();
              if (newTitle.isNotEmpty) {
                final newFolderId = const Uuid().v4();
                final containerFolder = NeuroItem(
                  id: newFolderId,
                  title: newTitle,
                  type: sourceItem.type == NeuroItemType.routineFolder
                      ? NeuroItemType.routineFolder
                      : NeuroItemType.vision,
                  parentId: sourceItem.parentId,
                  priority: sourceItem.priority,
                  startDate: DateTime.now(),
                );

                notifier.updateItem(containerFolder);
                notifier.updateItem(sourceItem.copyWith(parentId: newFolderId));
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Compiled button inside new "$newTitle" button')),
                );
              }
            },
            child: const Text('Compile'),
          ),
        ],
      ),
    );
  }
}
