import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

final _ytId = RegExp(r'/vi(?:_webp)?/([A-Za-z0-9_-]{11})/');

/// The YouTube video id inside a thumbnail URL, or null.
String? youtubeIdOf(String url) => _ytId.firstMatch(url)?.group(1);

/// The sharpest version of a song's artwork.
///
/// YouTube search hands out `hqdefault` (480x360 with black bars above and
/// below the picture), which looks blurry and boxed when it fills a card.
/// This first asks for `maxresdefault` (1280x720, no bars). Not every video
/// has one; then it falls back to the given URL, zoomed just enough to cut
/// the black bars off.
class NoorArtwork extends StatelessWidget {
  const NoorArtwork({super.key, required this.url, this.fit = BoxFit.cover});

  final String url;
  final BoxFit fit;

  /// Tests and the README screenshot tool can supply pictures without the
  /// network. Returns null to fall back to the normal loading.
  @visibleForTesting
  static ImageProvider? Function(String url)? debugImageFor;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return const SizedBox.expand();
    final local = debugImageFor?.call(url);
    if (local != null) {
      return Image(
          image: local,
          fit: fit,
          width: double.infinity,
          height: double.infinity,
          filterQuality: FilterQuality.high);
    }
    final id = youtubeIdOf(url);
    final fallback =
        _image(url, letterboxed: id != null && !url.contains('maxres'));
    if (id == null || url.contains('maxresdefault')) return fallback;
    return CachedNetworkImage(
      imageUrl: 'https://i.ytimg.com/vi/$id/maxresdefault.jpg',
      fit: fit,
      filterQuality: FilterQuality.high,
      fadeInDuration: const Duration(milliseconds: 200),
      placeholder: (_, __) => fallback,
      errorWidget: (_, __, ___) => fallback,
    );
  }

  Widget _image(String u, {required bool letterboxed}) {
    final img = CachedNetworkImage(
      imageUrl: u,
      fit: fit,
      filterQuality: FilterQuality.high,
      fadeInDuration: const Duration(milliseconds: 200),
      errorWidget: (_, __, ___) => const SizedBox.expand(),
    );
    // 4:3 frames hold a 16:9 picture: scale by 4/3 to crop the bars.
    return letterboxed
        ? ClipRect(child: Transform.scale(scale: 4 / 3, child: img))
        : img;
  }
}
