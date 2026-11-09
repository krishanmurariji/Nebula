import 'dart:math';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_music_player/screens/player_screen.dart';

void main() {
  const c = Offset(100, 100);
  Offset at(double degrees, [double r = 80]) {
    final a = degrees * pi / 180;
    return Offset(c.dx + r * cos(a), c.dy + r * sin(a));
  }

  group('volumeFromRingPoint', () {
    test('bottom-left is silent, top is half, bottom-right is full', () {
      expect(volumeFromRingPoint(at(135), c), closeTo(0.0, 1e-9));
      expect(volumeFromRingPoint(at(270), c), closeTo(0.5, 1e-9));
      expect(volumeFromRingPoint(at(45), c), closeTo(1.0, 1e-9));
    });

    test('going clockwise from the start raises the volume smoothly', () {
      var last = -1.0;
      for (var deg = 135.0; deg <= 135 + 270; deg += 5) {
        final v = volumeFromRingPoint(at(deg), c);
        expect(v, greaterThanOrEqualTo(last));
        last = v;
      }
      expect(last, closeTo(1.0, 1e-9));
    });

    test('left side is lower than the right side', () {
      expect(volumeFromRingPoint(at(180), c), closeTo(1 / 6, 1e-9));
      expect(volumeFromRingPoint(at(0), c), closeTo(5 / 6, 1e-9));
    });

    test('a touch in the gap at the bottom snaps to the nearer end', () {
      expect(volumeFromRingPoint(at(60), c), 1.0);
      expect(volumeFromRingPoint(at(120), c), 0.0);
    });

    test('distance from the centre does not matter, only the angle', () {
      expect(volumeFromRingPoint(at(270, 10), c), closeTo(0.5, 1e-9));
      expect(volumeFromRingPoint(at(270, 400), c), closeTo(0.5, 1e-9));
    });
  });
}
