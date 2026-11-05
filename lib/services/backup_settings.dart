import 'package:shared_preferences/shared_preferences.dart';

import 'fallback_sources.dart';

const _kKey = 'backup_instances';

/// Instances to try when YouTube itself fails. Missing key → defaults;
/// an explicitly saved empty list disables the backup source.
Future<List<String>> loadBackupInstances() async {
  try {
    final p = await SharedPreferences.getInstance();
    return p.getStringList(_kKey) ?? kDefaultBackupInstances;
  } catch (_) {
    return kDefaultBackupInstances;
  }
}

Future<void> saveBackupInstances(List<String> instances) async {
  final p = await SharedPreferences.getInstance();
  await p.setStringList(_kKey, instances);
}

Future<void> resetBackupInstances() async {
  final p = await SharedPreferences.getInstance();
  await p.remove(_kKey);
}
