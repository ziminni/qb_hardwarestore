import 'package:client/core/constants/app_colors.dart';
import 'package:flutter/material.dart';

// Tape-measure style tick marks used as a brand edge on panels and headers.
class MeasureRuler extends StatelessWidget {
  const MeasureRuler({super.key, this.height = 22});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: const CustomPaint(painter: _RulerPainter()),
    );
  }
}

class _RulerPainter extends CustomPainter {
  const _RulerPainter();

  static const double _step = 8;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.brandGold.withValues(alpha: 0.55)
      ..strokeWidth = 1;

    canvas.drawLine(Offset.zero, Offset(size.width, 0), paint);

    var index = 0;
    for (double x = 0; x <= size.width; x += _step, index++) {
      final length = index % 10 == 0
          ? size.height
          : index % 5 == 0
          ? size.height * 0.6
          : size.height * 0.3;
      canvas.drawLine(Offset(x, 0), Offset(x, length), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RulerPainter oldDelegate) => false;
}

// Tape-measure style progress bar that fills with [progress].
class MeasureProgressPainter extends CustomPainter {
  MeasureProgressPainter(this.progress) : super(repaint: progress);

  final Animation<double> progress;

  static const double _step = 8;

  @override
  void paint(Canvas canvas, Size size) {
    final filled = size.width * progress.value;
    final base = Paint()
      ..color = AppColors.brandGold.withValues(alpha: 0.2)
      ..strokeWidth = 1;
    final active = Paint()
      ..color = AppColors.brandGoldLight
      ..strokeWidth = 1;

    canvas.drawLine(Offset.zero, Offset(size.width, 0), base);
    canvas.drawLine(
      Offset.zero,
      Offset(filled, 0),
      Paint()
        ..color = AppColors.brandGoldLight
        ..strokeWidth = 2,
    );

    var index = 0;
    for (double x = 0; x <= size.width + 0.1; x += _step, index++) {
      final length = index % 10 == 0
          ? size.height
          : index % 5 == 0
          ? size.height * 0.6
          : size.height * 0.3;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, length),
        x <= filled ? active : base,
      );
    }
  }

  @override
  bool shouldRepaint(covariant MeasureProgressPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
