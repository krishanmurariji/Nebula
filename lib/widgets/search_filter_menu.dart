import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/search_provider.dart';
import '../theme/noor_palette.dart';
import '../theme/noor_song_card.dart';
import 'search_filter_bar.dart';

/// The small pop-up the settings button opens while searching: Best match,
/// Official only or All, each with how many results it holds. [anchor] is
/// the button that opened it (the pop-up hangs just under it).
Future<void> showSearchFilters(BuildContext context, {BuildContext? anchor}) {
  Rect? from;
  final box = anchor?.findRenderObject();
  if (box is RenderBox && box.hasSize) {
    from = box.localToGlobal(Offset.zero) & box.size;
  }
  HapticFeedback.selectionClick();
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close filters',
    barrierColor: Colors.black.withOpacity(0.06),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, _, __) => _FilterMenu(anchor: from),
    transitionBuilder: (ctx, a, _, child) {
      final c = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: c,
        child: ScaleTransition(
            scale: Tween(begin: 0.92, end: 1.0).animate(c),
            alignment: Alignment.topRight,
            child: child),
      );
    },
  );
}

class _FilterMenu extends ConsumerWidget {
  const _FilterMenu({this.anchor});
  final Rect? anchor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = NoorTheme.of(context);
    final search = ref.watch(searchProvider);
    final filter = ref.watch(searchFilterProvider);
    final mq = MediaQuery.of(context);
    final top = anchor != null ? anchor!.bottom + 8 : mq.padding.top + 66;
    final right =
        anchor != null ? mq.size.width - anchor!.right : 14.0;

    Widget option(SearchFilter f, String label, String hint, IconData icon, int count) {
      final on = filter == f;
      return InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          HapticFeedback.selectionClick();
          ref.read(searchFilterProvider.notifier).set(f);
          Navigator.of(context).pop();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 20, color: t.ac),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label,
                        style: TextStyle(
                            color: t.ac,
                            fontSize: 15,
                            fontWeight: on ? FontWeight.w700 : FontWeight.w600)),
                    Text(hint, style: TextStyle(color: t.mute, fontSize: 11.5)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text('$count',
                  style: TextStyle(
                      color: t.mute, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(width: 10),
              // A ring that fills when chosen.
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: t.ac, width: 1),
                ),
                padding: const EdgeInsets.all(3),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  opacity: on ? 1 : 0,
                  child: DecoratedBox(
                      decoration: BoxDecoration(shape: BoxShape.circle, color: t.ac)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final official = search.results.where((s) => s.isOfficial).length;
    return Stack(
      children: [
        Positioned(
          top: top,
          right: right,
          width: 290,
          child: Material(
            color: t.bg,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(26),
              side: BorderSide(color: t.ac, width: 0.8),
            ),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 12, 6, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
                    child: Text('Show results',
                        style: noorSongTitleStyle(t.ac, size: 20)),
                  ),
                  option(SearchFilter.bestMatch, 'Best match', 'Noor’s ranking, best first',
                      Icons.auto_awesome_outlined, search.results.length),
                  option(SearchFilter.officialOnly, 'Official only',
                      'Labels, Topic and artist channels', Icons.verified_outlined, official),
                  option(SearchFilter.all, 'All', 'Everything, in YouTube’s order',
                      Icons.list_rounded,
                      search.all.isEmpty ? search.results.length : search.all.length),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
