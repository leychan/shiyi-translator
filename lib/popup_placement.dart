import 'dart:math' as math;
import 'dart:ui';

/// All coordinates are logical desktop pixels, including negative monitor origins.
class PopupAnchor {
  const PopupAnchor({required this.cursor, required this.workArea});
  final Offset cursor;
  final Rect workArea;

  Map<String, dynamic> toJson() => {
    'x': cursor.dx,
    'y': cursor.dy,
    'left': workArea.left,
    'top': workArea.top,
    'width': workArea.width,
    'height': workArea.height,
  };

  factory PopupAnchor.fromJson(Map<String, dynamic> json) {
    double number(String key) {
      final value = (json[key] as num).toDouble();
      if (!value.isFinite) throw const FormatException('Invalid coordinate');
      return value;
    }

    final area = Rect.fromLTWH(
      number('left'),
      number('top'),
      number('width'),
      number('height'),
    );
    if (area.width <= 0 || area.height <= 0) {
      throw const FormatException('Invalid work area');
    }
    return PopupAnchor(
      cursor: Offset(number('x'), number('y')),
      workArea: area,
    );
  }
}

Rect popupBoundsNear(PopupAnchor anchor, Size preferredSize) {
  const margin = 8.0;
  const gapX = 14.0;
  const gapY = 18.0;
  final area = anchor.workArea;
  final width = math.min(
    preferredSize.width,
    math.max(1.0, area.width - 2 * margin),
  );
  final height = math.min(
    preferredSize.height,
    math.max(1.0, area.height - 2 * margin),
  );
  var x = anchor.cursor.dx + gapX;
  var y = anchor.cursor.dy + gapY;
  if (x + width > area.right - margin) x = anchor.cursor.dx - width - gapX;
  if (y + height > area.bottom - margin) y = anchor.cursor.dy - height - gapY;
  final left = math.min(area.left + margin, area.right - width);
  final top = math.min(area.top + margin, area.bottom - height);
  x = x.clamp(left, math.max(left, area.right - margin - width));
  y = y.clamp(top, math.max(top, area.bottom - margin - height));
  return Rect.fromLTWH(x.roundToDouble(), y.roundToDouble(), width, height);
}
