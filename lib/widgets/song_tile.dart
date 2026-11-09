import 'package:flutter/material.dart';
import '../models/song.dart';
import '../theme/noor_song_tile.dart';
import '../theme/noor_widgets.dart';

/// A plain song row in the Noor look (artwork, title, artist, round play
/// button). Screens with extra badges use [NoorSongTile] directly.
class SongTile extends StatelessWidget {
  final Song song;
  final bool isPlaying;
  final VoidCallback onTap;
  final Widget? trailing;

  const SongTile({
    super.key,
    required this.song,
    required this.isPlaying,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return NoorSongTile(
      thumbnailUrl: song.thumbnailUrl,
      title: song.title,
      subtitle: Text(song.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: noorSubtitleStyle(context)),
      selected: isPlaying,
      onTap: onTap,
      trailing: trailing ??
          NoorRoundButton(
            size: 38,
            filled: isPlaying,
            muted: !isPlaying,
            child: Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 20),
          ),
    );
  }
}
