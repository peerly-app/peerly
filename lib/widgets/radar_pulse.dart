import 'package:flutter/material.dart';

import '../design/colors.dart';

class RadarPulse extends StatefulWidget {
  final double coreDiameter;

  const RadarPulse({super.key, this.coreDiameter = 70});

  @override
  State<RadarPulse> createState() => _RadarPulseState();
}

class _RadarPulseState extends State<RadarPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static const _cycle = Duration(milliseconds: 2400);
  static const _delays = [0.0, 0.8 / 2.4, 1.6 / 2.4];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _cycle)..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maxDiameter = widget.coreDiameter * 1.6;
    return SizedBox(
      width: maxDiameter,
      height: maxDiameter,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Stack(
            alignment: Alignment.center,
            children: [
              for (final delay in _delays) _ring(_controller.value, delay),
              Container(
                width: widget.coreDiameter,
                height: widget.coreDiameter,
                decoration: const BoxDecoration(
                  color: AppColors.accentSoft,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Container(
                  width: widget.coreDiameter * 0.2,
                  height: widget.coreDiameter * 0.2,
                  decoration: const BoxDecoration(
                    color: AppColors.accent,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _ring(double t, double delay) {
    final phase = (t + (1 - delay)) % 1.0;
    final scale = 0.6 + phase * (1.6 - 0.6);
    final opacity = 1.0 - phase;

    return Opacity(
      opacity: opacity.clamp(0.0, 1.0),
      child: Transform.scale(
        scale: scale,
        child: Container(
          width: widget.coreDiameter,
          height: widget.coreDiameter,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            border: Border.fromBorderSide(
              BorderSide(color: AppColors.accent, width: 2),
            ),
          ),
        ),
      ),
    );
  }
}
