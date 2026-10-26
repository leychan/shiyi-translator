import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_translator/popup_placement.dart';

void main() {
  test('opens just below and to the right of the captured pointer', () {
    const anchor = PopupAnchor(
      cursor: Offset(200, 100),
      workArea: Rect.fromLTWH(0, 32, 1920, 1000),
    );
    expect(
      popupBoundsNear(anchor, const Size(480, 700)),
      const Rect.fromLTWH(214, 118, 480, 700),
    );
  });
  test(
    'flips near the right and bottom edges without covering the pointer',
    () {
      const anchor = PopupAnchor(
        cursor: Offset(1890, 1000),
        workArea: Rect.fromLTWH(0, 32, 1920, 1000),
      );
      final bounds = popupBoundsNear(anchor, const Size(480, 700));
      expect(bounds, const Rect.fromLTWH(1396, 282, 480, 700));
      expect(bounds.contains(anchor.cursor), false);
    },
  );
  test(
    'uses the monitor containing the selection, including negative coordinates',
    () {
      const anchor = PopupAnchor(
        cursor: Offset(-1700, -100),
        workArea: Rect.fromLTWH(-1920, -200, 1920, 1080),
      );
      final bounds = popupBoundsNear(anchor, const Size(480, 700));
      expect(bounds.topLeft, const Offset(-1686, -82));
      expect(anchor.workArea.contains(bounds.topLeft), true);
      expect(anchor.workArea.contains(bounds.bottomRight), true);
      expect(PopupAnchor.fromJson(anchor.toJson()).cursor, anchor.cursor);
    },
  );
  test(
    'large popup shrinks to fit the available work area and avoids panels',
    () {
      const anchor = PopupAnchor(
        cursor: Offset(300, 500),
        workArea: Rect.fromLTWH(0, 40, 600, 560),
      );
      final bounds = popupBoundsNear(anchor, const Size(800, 900));
      expect(bounds, const Rect.fromLTWH(8, 48, 584, 544));
    },
  );
}
