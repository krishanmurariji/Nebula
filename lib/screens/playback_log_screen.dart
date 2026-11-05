import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_log.dart';
import '../services/backup_settings.dart';

/// Live view of the playback log — lets problems be diagnosed on the phone.
class PlaybackLogScreen extends StatelessWidget {
  const PlaybackLogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Playback Log'),
        actions: [
          IconButton(
            tooltip: 'Copy all',
            icon: const Icon(Icons.copy_rounded),
            onPressed: () async {
              await Clipboard.setData(
                  ClipboardData(text: AppLog.instance.dump()));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Log copied to clipboard')));
              }
            },
          ),
          IconButton(
            tooltip: 'Clear',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: AppLog.instance.clear,
          ),
        ],
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: AppLog.instance.revision,
        builder: (context, _, __) {
          final lines = AppLog.instance.lines;
          if (lines.isEmpty) {
            return const Center(child: Text('Nothing logged yet'));
          }
          return ListView.builder(
            reverse: true, // newest at the bottom, stays pinned there
            padding: const EdgeInsets.all(12),
            itemCount: lines.length,
            itemBuilder: (_, i) {
              final line = lines[lines.length - 1 - i];
              final isBad = line.contains('failed') ||
                  line.contains('error') ||
                  line.contains('offline');
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  line,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: isBad
                        ? Colors.redAccent
                        : theme.colorScheme.onSurface.withOpacity(0.85),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Edit the Piped/Invidious instances used when YouTube itself fails.
Future<void> showBackupSourcesDialog(BuildContext context) async {
  final current = await loadBackupInstances();
  if (!context.mounted) return;
  final controller = TextEditingController(text: current.join('\n'));

  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Backup Sources'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Used automatically when YouTube blocks or breaks. One Piped or '
            'Invidious address per line. Public servers come and go, so you '
            'can add your own. Leave empty to turn this off.',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            maxLines: 5,
            minLines: 3,
            keyboardType: TextInputType.multiline,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'https://pipedapi.example.com'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await resetBackupInstances();
            if (ctx.mounted) Navigator.pop(ctx);
          },
          child: const Text('Reset to defaults'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () async {
            final list = controller.text
                .split('\n')
                .map((e) => e.trim())
                .where((e) => e.startsWith('http'))
                .toList();
            await saveBackupInstances(list);
            if (ctx.mounted) Navigator.pop(ctx);
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
  controller.dispose();
}
