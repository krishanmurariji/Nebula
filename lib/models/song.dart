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

  static bool detectOfficial(String title, String channel) {
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

  /// Tolerant on purpose: this reads data saved by older versions and
  /// anything on disk can be corrupted, so wrong types never throw.
  factory Song.fromMap(Map<dynamic, dynamic> m) {
    String str(Object? v, String fallback) => v is String ? v : fallback;
    return Song(
      videoId:      str(m['videoId'], ''),
      title:        str(m['title'], 'Unknown'),
      artist:       str(m['artist'], ''),
      thumbnailUrl: str(m['thumbnailUrl'], ''),
      isOfficial:   m['isOfficial'] is bool ? m['isOfficial'] as bool : false,
    );
  }

  /// True when this can actually be played / cached.
  bool get isPlayable => RegExp(r'^[A-Za-z0-9_-]{6,64}$').hasMatch(videoId);

  @override bool operator ==(Object o) =>
      identical(this, o) || (o is Song && videoId == o.videoId);
  @override int get hashCode => videoId.hashCode;
}
