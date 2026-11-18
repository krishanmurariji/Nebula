// Runs the integration tests on a device and saves their screenshots to
// build/emulator_shots/ (uploaded by .github/workflows/emulator.yml).
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() => integrationDriver(
      onScreenshot: (name, bytes, [args]) async {
        final file = File('build/emulator_shots/$name.png');
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(bytes);
        return true;
      },
    );
