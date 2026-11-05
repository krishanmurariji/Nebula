/// How a playback problem should be handled. The player never shows a dead-end
/// error for these: it ignores, retries a bounded number of times, or skips.
enum FailureKind {
  /// We interrupted ourselves (user skipped). Ignore completely.
  cancelled,

  /// Network blip, expired URL, timeout, 403/410. Worth a bounded retry.
  transient,

  /// YouTube is throttling us. Retrying immediately makes it worse; wait.
  rateLimited,

  /// Video is gone / private / region-locked / age-restricted. Skip it.
  permanent,
}

/// Classifies an error thrown by just_audio or youtube_explode_dart.
///
/// Uses the runtime type name instead of importing the exception classes, so
/// this stays a plain-Dart file that is trivial to unit test and does not break
/// if the package renames an exception.
FailureKind classifyPlaybackError(Object error) {
  final type = error.runtimeType.toString().toLowerCase();
  final text = error.toString().toLowerCase();

  if (text.contains('loading interrupted') ||
      text.contains('already exists') ||
      type.contains('playerinterrupted') ||
      (text.contains('abort') && !text.contains('connection abort'))) {
    return FailureKind.cancelled;
  }

  if (type.contains('requestlimit') ||
      text.contains('429') ||
      text.contains('too many requests') ||
      text.contains('rate limit')) {
    return FailureKind.rateLimited;
  }

  if (type.contains('videounavailable') ||
      type.contains('videounplayable') ||
      type.contains('videorequirespurchase') ||
      type.contains('videorestricted') ||
      text.contains('video is unavailable') ||
      text.contains('private video') ||
      text.contains('age restricted') ||
      text.contains('age-restricted')) {
    return FailureKind.permanent;
  }

  return FailureKind.transient;
}

/// Delay before retry number [attempt] (0-based): 0.8s, 1.6s, 3.2s … capped at 6s.
Duration retryDelay(int attempt) {
  final ms = 800 * (1 << attempt.clamp(0, 4));
  return Duration(milliseconds: ms > 6000 ? 6000 : ms);
}
