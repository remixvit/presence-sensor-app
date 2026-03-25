import 'dart:math';
import 'package:flutter/material.dart';
import '../models/device_model.dart';

class RadarWidget extends StatefulWidget {
  final SensorStatus status;
  final int maxDist;

  const RadarWidget({super.key, required this.status, this.maxDist = 4000});

  @override
  State<RadarWidget> createState() => _RadarWidgetState();
}

class _RadarWidgetState extends State<RadarWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _sweepCtrl;
  final _trail = <_TrailPoint>[];
  static const _maxTrail = 20;

  @override
  void initState() {
    super.initState();
    _sweepCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void didUpdateWidget(RadarWidget old) {
    super.didUpdateWidget(old);
    if (!widget.status.presence) {
      _trail.clear();
      return;
    }
    if (widget.status.dist != old.status.dist && widget.status.dist > 0) {
      _trail.add(_TrailPoint(dist: widget.status.dist, time: DateTime.now()));
      if (_trail.length > _maxTrail) _trail.removeAt(0);
    }
  }

  @override
  void dispose() {
    _sweepCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _sweepCtrl,
      builder: (_, __) => CustomPaint(
        painter: _RadarPainter(
          sweepAngle: _sweepCtrl.value * 2 * pi,
          dist: widget.status.dist,
          maxDist: widget.maxDist,
          dir: widget.status.dir,
          presence: widget.status.presence,
          activator: widget.status.activator,
          trail: List.from(_trail),
        ),
      ),
    );
  }
}

class _TrailPoint {
  final int dist;
  final DateTime time;
  _TrailPoint({required this.dist, required this.time});
}

class _RadarPainter extends CustomPainter {
  final double sweepAngle;
  final int dist;
  final int maxDist;
  final String dir;
  final bool presence;
  final bool activator;
  final List<_TrailPoint> trail;

  _RadarPainter({
    required this.sweepAngle,
    required this.dist,
    required this.maxDist,
    required this.dir,
    required this.presence,
    required this.activator,
    required this.trail,
  });

  Color get _blipColor {
    if (!presence) return Colors.white24;
    switch (dir) {
      case 'approaching':
      case 'приближается': return Colors.greenAccent;
      case 'leaving':
      case 'удаляется':    return Colors.orangeAccent;
      default:             return Colors.lightBlueAccent;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = min(cx, cy) - 8;

    // --- Фон круга ---
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()..color = const Color(0xFF0A0E1A),
    );

    // --- Концентрические кольца (4 зоны) ---
    final ringPaint = Paint()
      ..color = Colors.greenAccent.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (int i = 1; i <= 4; i++) {
      canvas.drawCircle(Offset(cx, cy), r * i / 4, ringPaint);
    }

    // --- Крестовые линии ---
    final linePaint = Paint()
      ..color = Colors.greenAccent.withValues(alpha: 0.1)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(cx, cy - r), Offset(cx, cy + r), linePaint);
    canvas.drawLine(Offset(cx - r, cy), Offset(cx + r, cy), linePaint);
    canvas.drawLine(
      Offset(cx + r * cos(-pi / 4), cy + r * sin(-pi / 4)),
      Offset(cx + r * cos(-pi / 4 + pi), cy + r * sin(-pi / 4 + pi)),
      linePaint,
    );
    canvas.drawLine(
      Offset(cx + r * cos(pi / 4), cy + r * sin(pi / 4)),
      Offset(cx + r * cos(pi / 4 + pi), cy + r * sin(pi / 4 + pi)),
      linePaint,
    );

    // --- Свип сектор ---
    final sweepRect = Rect.fromCircle(center: Offset(cx, cy), radius: r);
    const sweepSpan = pi / 2; // 90 градусов
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        startAngle: sweepAngle - sweepSpan,
        endAngle: sweepAngle,
        colors: [
          Colors.transparent,
          Colors.greenAccent.withValues(alpha: 0.25),
        ],
        transform: GradientRotation(sweepAngle - sweepSpan),
      ).createShader(sweepRect);
    canvas.drawArc(sweepRect, sweepAngle - sweepSpan, sweepSpan, true, sweepPaint);

    // --- Линия свипа ---
    final sweepLinePaint = Paint()
      ..color = Colors.greenAccent.withValues(alpha: 0.8)
      ..strokeWidth = 1.5;
    canvas.drawLine(
      Offset(cx, cy),
      Offset(cx + r * cos(sweepAngle), cy + r * sin(sweepAngle)),
      sweepLinePaint,
    );

    // --- Трек объекта ---
    final now = DateTime.now();
    for (int i = 0; i < trail.length; i++) {
      final pt = trail[i];
      final age = now.difference(pt.time).inMilliseconds;
      final alpha = (1.0 - age / 8000).clamp(0.0, 1.0);
      if (alpha <= 0) continue;

      final ratio = (pt.dist / maxDist).clamp(0.0, 1.0);
      // Объект всегда сверху (угол -pi/2 = вверх)
      final px = cx + r * ratio * cos(-pi / 2);
      final py = cy + r * ratio * sin(-pi / 2);

      canvas.drawCircle(
        Offset(px, py),
        3.0 * alpha,
        Paint()..color = _blipColor.withValues(alpha: alpha * 0.5),
      );
    }

    // --- Основной блип (объект) ---
    if (presence && dist > 0) {
      final ratio = (dist / maxDist).clamp(0.0, 1.0);
      final px = cx + r * ratio * cos(-pi / 2);
      final py = cy + r * ratio * sin(-pi / 2);

      // Гало
      canvas.drawCircle(
        Offset(px, py),
        14,
        Paint()..color = _blipColor.withValues(alpha: 0.15),
      );
      // Блип
      canvas.drawCircle(
        Offset(px, py),
        6,
        Paint()..color = _blipColor,
      );
      // Центр
      canvas.drawCircle(
        Offset(px, py),
        2.5,
        Paint()..color = Colors.white,
      );
    }

    // --- Центральная точка (сенсор) ---
    canvas.drawCircle(
      Offset(cx, cy),
      activator ? 6 : 4,
      Paint()..color = activator ? Colors.orangeAccent : Colors.white38,
    );
    if (activator) {
      canvas.drawCircle(
        Offset(cx, cy),
        12,
        Paint()..color = Colors.orangeAccent.withValues(alpha: 0.2),
      );
    }

    // --- Метки дистанции ---
    final textStyle = TextStyle(
      color: Colors.greenAccent.withValues(alpha: 0.4),
      fontSize: 9,
    );
    for (int i = 1; i <= 4; i++) {
      final label = '${maxDist ~/ 4 * i ~/ 10}cm';
      final tp = TextPainter(
        text: TextSpan(text: label, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(cx + 3, cy - r * i / 4 - 11));
    }

    // --- Внешняя рамка ---
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()
        ..color = Colors.greenAccent.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_RadarPainter old) => true;
}
