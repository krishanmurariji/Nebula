import 'package:flutter/material.dart';

/// The girl from the Noor logo, large and faded, behind empty pages.
class NoorGirlWatermark extends StatelessWidget {
  const NoorGirlWatermark({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 110),
        child: Center(
          child: Opacity(
            opacity: 0.16,
            child: Image.asset('assets/images/noor_girl.png',
                fit: BoxFit.contain, semanticLabel: 'Noor'),
          ),
        ),
      ),
    );
  }
}
