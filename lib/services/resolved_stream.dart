/// Everything the player needs to start a song, independent of where the
/// stream came from (YouTube directly, or a backup instance).
class ResolvedStream {
  const ResolvedStream({
    required this.url,
    required this.totalBytes,
    required this.mimeType,
    required this.open,
    this.origin = 'youtube',
  });

  /// Direct URL (used by the raw-URL fallback source).
  final Uri url;
  final int totalBytes;
  final String mimeType;

  /// Opens a fresh byte stream of the whole file (chunking/retries included).
  final Stream<List<int>> Function() open;

  /// For logs: 'youtube' or the backup instance host.
  final String origin;
}
