import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

const _kKey = 'nebula_api_key';

final apiKeyProvider =
    StateNotifierProvider<ApiKeyNotifier, String>((ref) => ApiKeyNotifier());

final hasApiKeyProvider =
    Provider<bool>((ref) => ref.watch(apiKeyProvider).isNotEmpty);

class ApiKeyNotifier extends StateNotifier<String> {
  ApiKeyNotifier() : super('') { _load(); }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    state = p.getString(_kKey) ?? '';
  }

  Future<String?> validateAndSave(String key) async {
    final k = key.trim();
    if (k.isEmpty) return 'Please enter your API key.';
    if (!k.startsWith('AIza')) return 'Key should start with "AIza".';
    try {
      final uri = Uri.parse('https://www.googleapis.com/youtube/v3/search')
          .replace(queryParameters: {
        'part': 'snippet', 'q': 'test', 'maxResults': '1', 'key': k,
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200 || res.statusCode == 400) {
        final p = await SharedPreferences.getInstance();
        await p.setString(_kKey, k);
        state = k;
        return null;
      } else if (res.statusCode == 403) {
        return 'Key invalid or no YouTube API access.';
      }
      return 'Validation failed (HTTP ${res.statusCode}).';
    } catch (_) {
      return 'Network error. Check your connection.';
    }
  }

  Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kKey);
    state = '';
  }
}
