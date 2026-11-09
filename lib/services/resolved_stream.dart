/// Everything the player needs to start a song, independent of where the
/// stream came from (YouTube directly, or a backup instance).
class ResolvedStream {
  const ResolvedStream({
    required this.url,
    required this.totalBytes,
    required this.mimeType,
    required this.open,
    this.origin = 'youtube',
    this.clientIndex = -1,
    this.userAgent,
  });

  /// Direct URL (used by the raw-URL fallback source).
  final Uri url;
  final int totalBytes;
  final String mimeType;

  /// Opens a fresh byte stream of the whole file (chunking/retries included).
  final Stream<List<int>> Function() open;

  /// For logs: 'youtube' or the backup instance host.
  final String origin;

  /// Which resolver client produced this stream (-1 = unknown). Lets the
  /// player penalize a client whose streams cannot actually be downloaded.
  final int clientIndex;

  /// The User-Agent the media server expects for this URL (the client it was
  /// issued to), or null when unknown.
  final String? userAgent;

  ResolvedStream withClient(int index) => ResolvedStream(
        url: url,
        totalBytes: totalBytes,
        mimeType: mimeType,
        open: open,
        origin: origin,
        clientIndex: index,
        userAgent: userAgent,
      );
}
