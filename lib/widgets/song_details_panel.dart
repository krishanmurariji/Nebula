import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/song.dart';
import '../providers/connection_provider.dart';
import '../services/song_details.dart';
import '../theme/noor_artwork.dart';
import '../theme/noor_palette.dart';
import '../theme/noor_play_pause.dart';
import '../theme/noor_song_card.dart';

/// The part a search result shows when it is expanded: the thumbnail in
/// full, the whole title, who uploaded it, how popular it is, and who made
/// the song (singer, lyrics, music...) as far as YouTube's page tells.
///
/// Tap anywhere but the play button to fold it away again.
class SongDetailsPanel extends ConsumerWidget {
  const SongDetailsPanel({
    super.key,
    required this.song,
    required this.onPlayPause,
    required this.onCollapse,
    this.artist,
    this.official = false,
    this.current = false,
    this.playing = false,
    this.loading = false,
  });

  final Song song;
  final String? artist;
  final bool official;
  final bool current;
  final bool playing;
  final bool loading;
  final VoidCallback onPlayPause;
  final VoidCallback onCollapse;

  static const _icons = <String, IconData>{
    'Singer': Icons.mic_none_rounded,
    'Lyrics': Icons.edit_note_rounded,
    'Music': Icons.piano_rounded,
    'Starring': Icons.people_outline_rounded,
    'Album': Icons.album_outlined,
    'Label': Icons.sell_outlined,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = NoorTheme.of(context);
    final details = ref.watch(songDetailsProvider(song.videoId));
    final d = details.valueOrNull;
    final offline = ref.watch(connectionProvider) == Connection.offline;

    Widget stat(IconData icon, String text) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: t.mute),
            const SizedBox(width: 4),
            Text(text,
                style: TextStyle(
                    color: t.ac, fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        );

    Widget credit(String label, String value) => Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_icons[label] ?? Icons.info_outline_rounded,
                  size: 18, color: t.ac),
              const SizedBox(width: 8),
              SizedBox(
                width: 64,
                child: Text(label,
                    style: TextStyle(
                        color: t.mute,
                        fontSize: 12,
                        height: 1.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3)),
              ),
              Expanded(
                child: Text(value,
                    style: TextStyle(
                        color: t.ac,
                        fontSize: 14,
                        height: 1.3,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        );

    final note = TextStyle(color: t.mute, fontSize: 13, height: 1.3);
    final List<Widget> body;
    if (details.isLoading) {
      body = [
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
              minHeight: 2,
              color: t.ac,
              backgroundColor: t.ac.withOpacity(0.12)),
        ),
        const SizedBox(height: 8),
        Text('Getting the details from YouTube…', style: note),
      ];
    } else if (d == null) {
      body = [
        const SizedBox(height: 10),
        Text(
            offline
                ? "You're offline. The details need internet."
                : 'The details could not be loaded right now.',
            style: note),
        if (!offline)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                  foregroundColor: t.ac, padding: EdgeInsets.zero),
              onPressed: () =>
                  ref.invalidate(songDetailsProvider(song.videoId)),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Try again'),
            ),
          ),
      ];
    } else {
      final credits = d.credits;
      body = [
        const SizedBox(height: 10),
        Wrap(
          spacing: 16,
          runSpacing: 6,
          children: [
            if (d.views != null)
              stat(Icons.visibility_outlined,
                  '${SongDetails.compactCount(d.views!)} views'),
            if (d.likes != null)
              stat(Icons.thumb_up_outlined,
                  '${SongDetails.compactCount(d.likes!)} likes'),
            if (d.published != null)
              stat(Icons.calendar_today_outlined,
                  SongDetails.monthYear(d.published!)),
          ],
        ),
        if (credits.isNotEmpty) ...[
          const SizedBox(height: 6),
          for (final (label, value) in credits) credit(label, value),
        ] else ...[
          const SizedBox(height: 8),
          Text('The upload does not say who sang or wrote it.', style: note),
        ],
      ];
    }

    final duration = d?.duration;
    return Semantics(
      container: true,
      label: 'Song details',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onCollapse,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: t.bg,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: t.ac, width: 0.8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The thumbnail, whole and sharp.
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      NoorArtwork(url: song.thumbnailUrl),
                      if (duration != null && duration > Duration.zero)
                        Positioned(
                          right: 8,
                          bottom: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.7),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(SongDetails.clock(duration),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(song.title,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: noorSongTitleStyle(t.ac, size: 22)),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(Icons.smart_display_outlined,
                                size: 16, color: t.mute),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(d?.channel ?? artist ?? song.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: t.ac,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600)),
                            ),
                            if (official) ...[
                              const SizedBox(width: 6),
                              Icon(Icons.verified_rounded,
                                  size: 15, color: t.ac),
                              const SizedBox(width: 2),
                              Text('Official',
                                  style:
                                      TextStyle(color: t.mute, fontSize: 12)),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  NoorPlayPauseButton(
                    playing: current && playing,
                    loading: loading,
                    onTap: onPlayPause,
                  ),
                ],
              ),
              ...body,
            ],
          ),
        ),
      ),
    );
  }
}
