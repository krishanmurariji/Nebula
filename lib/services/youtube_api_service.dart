import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/song.dart';

class YoutubeApiService {
  static const _base = 'https://www.googleapis.com/youtube/v3/search';
  final String apiKey;
  YoutubeApiService({required this.apiKey});

  Future<List<Song>> searchSongs(String query) async {
    if (query.trim().isEmpty) return [];
    if (apiKey.isEmpty) throw Exception('API key not set.');
    final uri = Uri.parse(_base).replace(queryParameters: {
      'part': 'snippet', 'q': '${query} music',
      'type': 'video', 'videoCategoryId': '10',
      'maxResults': '20', 'key': apiKey,
    });
    final res = await http.get(uri).timeout(const Duration(seconds: 15));
    if (res.statusCode == 200) {
      final data  = json.decode(res.body) as Map<String, dynamic>;
      final items = data['items'] as List<dynamic>? ?? [];
      return items
          .map((e) => Song.fromJson(e as Map<String, dynamic>))
          .where((s) => s.videoId.isNotEmpty)
          .toList();
    } else if (res.statusCode == 403) {
      throw Exception('Invalid API key or quota exceeded.');
    }
    throw Exception('Search failed: HTTP ${res.statusCode}');
  }
}
