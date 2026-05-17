import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Circular tap-to-record button with a pulsing ring animation while
/// listening. Idle, listening, processing, and disabled states are
/// expressed via [MicButtonState].
enum MicButtonState { idle, listening, processing, disabled }

class MicButton extends StatefulWidget {
  const MicButton({
    super.key,
    required this.state,
    required this.onPressed,
    this.size = 132,
  });

  final MicButtonState state;
  final VoidCallback? onPressed;
  final double size;

  @override
  State<MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<MicButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant MicButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) _syncAnimation();
  }

  void _syncAnimation() {
    if (widget.state == MicButtonState.listening) {
      _pulse.repeat();
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isInteractive =
        widget.state != MicButtonState.disabled &&
        widget.state != MicButtonState.processing &&
        widget.onPressed != null;

    final core = _coreColorFor(widget.state, colors);
    final icon = _iconFor(widget.state);

    return SizedBox(
      width: widget.size + 80,
      height: widget.size + 80,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (widget.state == MicButtonState.listening)
            AnimatedBuilder(
              animation: _pulse,
              builder: (context, _) {
                return CustomPaint(
                  size: Size.square(widget.size + 80),
                  painter: _PulsePainter(
                    progress: _pulse.value,
                    color: core,
                  ),
                );
              },
            ),
          Material(
            color: core,
            elevation: isInteractive ? 6 : 1,
            shape: const CircleBorder(),
            shadowColor: core.withValues(alpha: 0.6),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: isInteractive ? widget.onPressed : null,
              child: SizedBox(
                width: widget.size,
                height: widget.size,
                child: Center(
                  child: widget.state == MicButtonState.processing
                      ? SizedBox(
                          width: widget.size * 0.45,
                          height: widget.size * 0.45,
                          child: CircularProgressIndicator(
                            strokeWidth: 4,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              colors.onPrimary,
                            ),
                          ),
                        )
                      : Icon(
                          icon,
                          size: widget.size * 0.45,
                          color: colors.onPrimary,
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(MicButtonState s) {
    switch (s) {
      case MicButtonState.listening:
        return Icons.mic;
      case MicButtonState.disabled:
        return Icons.mic_off;
      case MicButtonState.idle:
      case MicButtonState.processing:
        return Icons.mic_none;
    }
  }

  Color _coreColorFor(MicButtonState s, ColorScheme colors) {
    switch (s) {
      case MicButtonState.listening:
        return colors.error;
      case MicButtonState.disabled:
        return colors.outlineVariant;
      case MicButtonState.processing:
        return colors.primary.withValues(alpha: 0.85);
      case MicButtonState.idle:
        return colors.primary;
    }
  }
}

class _PulsePainter extends CustomPainter {
  _PulsePainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.shortestSide / 2;
    final ringRadius = math.min(size.width, size.height) * 0.34;

    for (int i = 0; i < 2; i++) {
      final t = (progress + i * 0.5) % 1.0;
      final radius = ringRadius + (maxRadius - ringRadius) * t;
      final alpha = (1.0 - t).clamp(0.0, 1.0);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = color.withValues(alpha: alpha * 0.55);
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PulsePainter old) =>
      old.progress != progress || old.color != color;
}
