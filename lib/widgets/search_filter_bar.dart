import 'package:flutter/material.dart';
import '../theme/noor_palette.dart';

/// How search results are shown.
enum SearchFilter {
  /// Every result, in YouTube's own order.
  all,

  /// Everything, Noor's best match first (the default).
  bestMatch,

  /// Only uploads from a trusted source (Topic / VEVO / label / the artist).
  officialOnly,
}

/// The two filter chips shown under the search bar.
class SearchFilterBar extends StatelessWidget {
  const SearchFilterBar({
    super.key,
    required this.filter,
    required this.onChanged,
    required this.totalCount,
    required this.officialCount,
    required this.isDark,
    this.allCount,
    this.trailing,
  });

  /// Shown after the chips (e.g. the settings button).
  final Widget? trailing;

  /// How many results "All" holds; defaults to [totalCount].
  final int? allCount;

  final SearchFilter filter;
  final ValueChanged<SearchFilter> onChanged;
  final int totalCount;
  final int officialCount;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 6),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          _FilterChipButton(
            label: 'All',
            count: allCount ?? totalCount,
            icon: Icons.list_rounded,
            selected: filter == SearchFilter.all,
            isDark: isDark,
            onTap: () => onChanged(SearchFilter.all),
          ),
          _FilterChipButton(
            label: 'Official only',
            count: officialCount,
            icon: Icons.verified_rounded,
            selected: filter == SearchFilter.officialOnly,
            isDark: isDark,
            onTap: () => onChanged(SearchFilter.officialOnly),
          ),
          _FilterChipButton(
            label: 'Best match',
            count: totalCount,
            icon: Icons.auto_awesome_rounded,
            selected: filter == SearchFilter.bestMatch,
            isDark: isDark,
            onTap: () => onChanged(SearchFilter.bestMatch),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _FilterChipButton extends StatelessWidget {
  const _FilterChipButton({
    required this.label,
    required this.count,
    required this.icon,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  final String label;
  final int count;
  final IconData icon;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = NoorTheme.byMode(isDark);
    final fg = selected ? t.onAc : t.ac;

    return Semantics(
      button: true,
      selected: selected,
      label: '$label, $count results',
      onTap: onTap,
      // Read the chip once ("Official only, 3 results"), not once per inner text.
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          // 40 px tall: comfortable to tap.
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? t.ac : null,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: t.ac, width: 0.8),
          ),
          // Shrinks to fit instead of overflowing on very narrow screens or
          // with huge system text.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, color: fg),
                ),
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: fg.withOpacity(0.8)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
