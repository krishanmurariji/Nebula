import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/connection_provider.dart';
import '../theme/noor_palette.dart';
import '../theme/noor_song_card.dart';

/// A thin pill under the header while there is no usable internet:
/// "Offline · saved songs only". It slides away by itself when the
/// connection is back; tapping it checks again at once.
class NoorOfflinePill extends ConsumerWidget {
  const NoorOfflinePill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = NoorTheme.of(context);
    final offline = ref.watch(connectionProvider) == Connection.offline;
    return AnimatedSize(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: !offline
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Center(
                child: Semantics(
                  container: true,
                  liveRegion: true,
                  button: true,
                  label: 'Offline, saved songs only. Tap to check again.',
                  excludeSemantics: true,
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      ref.read(connectionProvider.notifier).recheck();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 5),
                      decoration: BoxDecoration(
                        color: t.bg,
                        borderRadius: BorderRadius.circular(kNoorCardRadius),
                        border: Border.all(color: t.ac, width: 0.8),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.wifi_off_rounded, size: 14, color: t.ac),
                        const SizedBox(width: 6),
                        Text('Offline · saved songs only',
                            style: TextStyle(
                                color: t.ac,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
