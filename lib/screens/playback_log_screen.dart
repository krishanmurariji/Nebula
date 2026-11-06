import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_log.dart';
import '../services/backup_settings.dart';
import '../services/fallback_sources.dart';

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
  await showDialog<void>(
    context: context,
    builder: (_) => _BackupSourcesDialog(initial: current),
  );
}

class _BackupSourcesDialog extends StatefulWidget {
  const _BackupSourcesDialog({required this.initial});
  final List<String> initial;
  @override
  State<_BackupSourcesDialog> createState() => _BackupSourcesDialogState();
}

class _BackupSourcesDialogState extends State<_BackupSourcesDialog> {
  // Owned by the dialog's State so it is disposed only after the dialog is
  // really gone (disposing right after showDialog returns can throw).
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial.join('\n'));
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final lines = _controller.text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final valid = <String>[];
    final rejected = <String>[];
    for (final line in lines) {
      final n = normalizeInstanceUrl(line);
      if (n == null) {
        rejected.add(line);
      } else if (!valid.contains(n)) {
        valid.add(n);
      }
    }
    if (rejected.isNotEmpty) {
      setState(() => _error =
          'Not accepted (https addresses of public servers only):\n${rejected.take(3).join('\n')}');
      return;
    }
    if (valid.length > 8) {
      setState(() => _error = 'Please keep it to 8 servers or fewer.');
      return;
    }
    await saveBackupInstances(valid);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Backup Sources'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Used automatically when YouTube blocks or breaks. One Piped or '
              'Invidious https address per line. Public servers come and go, '
              'so you can add your own. Leave empty to turn this off.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              maxLines: 5,
              minLines: 3,
              keyboardType: TextInputType.multiline,
              autocorrect: false,
              enableSuggestions: false,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: 'https://pipedapi.example.com',
                errorText: _error,
                errorMaxLines: 5,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await resetBackupInstances();
            if (mounted) Navigator.pop(context);
          },
          child: const Text('Reset to defaults'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
