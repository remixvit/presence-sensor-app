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

class _RadarWidgetState extends State<RadarWidget> {
  final _trail = <_TrailPoint>[];
  static const _maxTrail = 25;

  @override
  void didUpdateWidget(RadarWidget old) {
    super.didUpdateWidget(old);
    if (!widget.status.presence) {
      _trail.clear();
      return;
    }
    if (widget.status.dist > 0 && widget.status.dist != old.status.dist) {
      _trail.add(_TrailPoint(dist: widget.status.dist, time: DateTime.now()));
      if (_trail.length > _maxTrail) _trail.removeAt(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SectorPainter(
        dist: widget.status.dist,
        maxDist: widget.maxDist,
        dir: widget.status.dir,
        presence: widget.status.presence,
        activator: widget.status.activator,
        trail: List.from(_trail),
      ),
    );
  }
}

class _TrailPoint {
  final int dist;
  final DateTime time;
  _TrailPoint({required this.dist, required this.time});
}

class _SectorPainter extends CustomPainter {
  final int dist;
  final int maxDist;
  final String dir;
  final bool presence;
  final bool activator;
  final List<_TrailPoint> trail;

  static const double _halfAngle = pi * 0.38; // ~68° в каждую сторону
  static const double _up = -pi / 2;

  _SectorPainter({
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

  Offset _blipPos(Offset apex, double radius, int d) {
    final ratio = (d / maxDist).clamp(0.0, 1.0);
    return Offset(
      apex.dx + radius * ratio * cos(_up),
      apex.dy + radius * ratio * sin(_up),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    const apexMargin = 24.0;
    final apex = Offset(cx, size.height - apexMargin);
    final radius = size.height - apexMargin - 8;

    // ── Обрезаем по форме сектора ───────────────────────────
    final fanPath = Path()
      ..moveTo(apex.dx, apex.dy)
      ..arcTo(
        Rect.fromCircle(center: apex, radius: radius),
        _up - _halfAngle,
        _halfAngle * 2,
        false,
      )
      ..close();
    canvas.clipPath(fanPath);

    // ── Фон ────────────────────────────────────────────────
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFF080C18),
    );

    // ── Заливка сектора ────────────────────────────────────
    canvas.drawPath(
      fanPath,
      Paint()..color = const Color(0xFF0D1525),
    );

    // ── Концентрические дуги ───────────────────────────────
    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (int i = 1; i <= 4; i++) {
      final r = radius * i / 4;
      arcPaint.color = Colors.greenAccent.withValues(alpha: i == 4 ? 0.25 : 0.12);
      canvas.drawArc(
        Rect.fromCircle(center: apex, radius: r),
        _up - _halfAngle,
        _halfAngle * 2,
        false,
        arcPaint,
      );
    }

    // ── Боковые лучи сектора ───────────────────────────────
    final edgePaint = Paint()
      ..color = Colors.greenAccent.withValues(alpha: 0.2)
      ..strokeWidth = 1;
    for (final angle in [_up - _halfAngle, _up + _halfAngle]) {
      canvas.drawLine(
        apex,
        Offset(apex.dx + radius * cos(angle), apex.dy + radius * sin(angle)),
        edgePaint,
      );
    }

    // ── Центральная ось ────────────────────────────────────
    canvas.drawLine(
      apex,
      Offset(apex.dx, apex.dy - radius),
      Paint()
        ..color = Colors.greenAccent.withValues(alpha: 0.1)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );

    // ── Трек объекта ───────────────────────────────────────
    final now = DateTime.now();
    for (int i = 0; i < trail.length; i++) {
      final pt = trail[i];
      final age = now.difference(pt.time).inMilliseconds;
      final alpha = (1.0 - age / 6000).clamp(0.0, 1.0);
      if (alpha <= 0) continue;

      final pos = _blipPos(apex, radius, pt.dist);
      final fraction = i / trail.length;
      canvas.drawCircle(
        pos,
        2.5 * fraction,
        Paint()..color = _blipColor.withValues(alpha: alpha * fraction * 0.6),
      );
    }

    // ── Главный блип ───────────────────────────────────────
    if (presence && dist > 0) {
      final pos = _blipPos(apex, radius, dist);

      // Горизонтальная полоса — ширина зоны обнаружения
      final ratio = (dist / maxDist).clamp(0.0, 1.0);
      final spreadWidth = size.width * 0.5 * ratio;
      canvas.drawLine(
        Offset(pos.dx - spreadWidth / 2, pos.dy),
        Offset(pos.dx + spreadWidth / 2, pos.dy),
        Paint()
          ..color = _blipColor.withValues(alpha: 0.15)
          ..strokeWidth = 2,
      );

      // Гало
      canvas.drawCircle(pos, 18, Paint()..color = _blipColor.withValues(alpha: 0.12));
      // Блип
      canvas.drawCircle(pos, 7, Paint()..color = _blipColor);
      // Центр
      canvas.drawCircle(pos, 3, Paint()..color = Colors.white);
    }

    // ── Метки дистанции ────────────────────────────────────
    final labelStyle = TextStyle(
      color: Colors.greenAccent.withValues(alpha: 0.45),
      fontSize: 9,
      fontFamily: 'monospace',
    );
    for (int i = 1; i <= 4; i++) {
      final cm = maxDist ~/ 4 * i ~/ 10;
      final label = '${cm}cm';
      final tp = TextPainter(
        text: TextSpan(text: label, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      final r = radius * i / 4;
      // Метка справа от центральной оси
      final lx = apex.dx + r * cos(_up + 0.15) - tp.width / 2 + 14;
      final ly = apex.dy + r * sin(_up + 0.15) - tp.height / 2;
      tp.paint(canvas, Offset(lx, ly));
    }

    // ── Сенсор (апекс) ─────────────────────────────────────
    canvas.drawCircle(
      apex,
      activator ? 7 : 5,
      Paint()..color = activator ? Colors.orangeAccent : Colors.white54,
    );
    if (activator) {
      canvas.drawCircle(
        apex,
        14,
        Paint()..color = Colors.orangeAccent.withValues(alpha: 0.2),
      );
    }
  }

  @override
  bool shouldRepaint(_SectorPainter old) =>
      old.dist != dist ||
      old.presence != presence ||
      old.activator != activator ||
      old.dir != dir ||
      old.trail.length != trail.length;
}
