class Song {
  final String videoId;
  final String title;
  final String artist;
  final String thumbnailUrl;
  final bool isOfficial;

  const Song({
    required this.videoId,
    required this.title,
    required this.artist,
    required this.thumbnailUrl,
    this.isOfficial = false,
  });

  factory Song.fromJson(Map<String, dynamic> json) {
    final snippet = json['snippet'] as Map<String, dynamic>? ?? {};
    String videoId = '';
    if (json['id'] is Map) {
      videoId = (json['id'] as Map)['videoId'] as String? ?? '';
    } else {
      videoId = json['id'] as String? ?? '';
    }
    final thumbs = snippet['thumbnails'] as Map<String, dynamic>? ?? {};
    final high   = thumbs['high'] as Map<String, dynamic>?
                ?? thumbs['default'] as Map<String, dynamic>? ?? {};
    final title        = snippet['title'] as String? ?? 'Unknown';
    final channelTitle = snippet['channelTitle'] as String? ?? '';
    return Song(
      videoId:      videoId,
      title:        title,
      artist:       channelTitle,
      thumbnailUrl: high['url'] as String? ?? '',
      isOfficial:   _detectOfficial(title, channelTitle),
    );
  }

  static bool _detectOfficial(String title, String channel) {
    final t = title.toLowerCase();
    final c = channel.toLowerCase();
    if (c.endsWith('- topic') || c.contains('vevo')) return true;
    return ['official video','official audio','official music video',
            'official mv','official lyric video']
        .any((k) => t.contains(k));
  }

  Map<String, dynamic> toMap() => {
    'videoId': videoId, 'title': title, 'artist': artist,
    'thumbnailUrl': thumbnailUrl, 'isOfficial': isOfficial,
  };

  factory Song.fromMap(Map<String, dynamic> m) => Song(
    videoId:      m['videoId']      as String? ?? '',
    title:        m['title']        as String? ?? 'Unknown',
    artist:       m['artist']       as String? ?? '',
    thumbnailUrl: m['thumbnailUrl'] as String? ?? '',
    isOfficial:   m['isOfficial']   as bool?   ?? false,
  );

  @override bool operator ==(Object o) =>
      identical(this, o) || (o is Song && videoId == o.videoId);
  @override int get hashCode => videoId.hashCode;
}
