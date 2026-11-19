/// What this build is, stamped in by the release workflow
/// (--dart-define NOOR_VERSION / NOOR_BUILD / NOOR_COMMIT). A build made on
/// a computer without them says so instead of showing a made-up number.
class AppVersion {
  static const version = String.fromEnvironment('NOOR_VERSION');
  static const build = String.fromEnvironment('NOOR_BUILD');
  static const commit = String.fromEnvironment('NOOR_COMMIT');

  /// e.g. "Version 1.0.0 · build 108 · 742355d", or "Development build".
  static String get label {
    if (version.isEmpty && build.isEmpty) return 'Development build';
    return [
      if (version.isNotEmpty) 'Version $version',
      if (build.isNotEmpty) 'build $build',
      if (commit.isNotEmpty) commit,
    ].join('  ·  ');
  }
}
