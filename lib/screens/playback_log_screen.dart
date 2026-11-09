import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_log.dart';
import '../services/network_diagnostics.dart';
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
            tooltip: 'Network check',
            icon: const Icon(Icons.network_check_rounded),
            onPressed: () => _showNetworkCheck(context),
          ),
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
              'Used automatically when YouTube blocks or breaks. None are built in: '
              'public Piped/Invidious servers are often blocked or shut down, so '
              'add one that works for you (or your own), one https address per '
              'line. Leave empty to turn this off.',
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


/// Runs the network check and shows a plain-language verdict. Results are also
/// written to the log so they can be copied together with everything else.
Future<void> _showNetworkCheck(BuildContext context) async {
  final future = runNetworkDiagnostics().then((results) {
    for (final r in results) {
      nlog('[N] netcheck $r');
    }
    final advice = adviceFor(results);
    nlog('[N] netcheck verdict: $advice');
    return (results: results, advice: advice);
  });

  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Network check'),
      content: SizedBox(
        width: double.maxFinite,
        child: FutureBuilder<({List<DiagnosticResult> results, String advice})>(
          future: future,
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final data = snap.data!;
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final r in data.results)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(r.toString(),
                          style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: r.ok ? null : Colors.redAccent)),
                    ),
                  const SizedBox(height: 12),
                  Text(data.advice,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
      ],
    ),
  );
}
