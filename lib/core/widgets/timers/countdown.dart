import 'dart:async';

import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:flutter/material.dart';

enum CountdownFormat { mmss, dhm }

class Countdown extends StatefulWidget {
  final DateTime until;
  final VoidCallback onTimeout;
  final TextStyle? textStyle;
  final CountdownFormat format;

  const Countdown({
    super.key,
    required this.until,
    required this.onTimeout,
    this.textStyle,
    this.format = CountdownFormat.mmss,
  });

  @override
  CountdownState createState() => CountdownState();
}

class CountdownState extends State<Countdown> {
  late Duration remainingTime;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    remainingTime = _calculateRemainingTime();
    if (remainingTime <= Duration.zero) {
      remainingTime = Duration.zero;
      _scheduleTimeout();
      return;
    }
    timer = Timer.periodic(const Duration(seconds: 1), _updateTimer);
  }

  @override
  void didUpdateWidget(Countdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.until != widget.until) {
      // Cancel the old timer
      timer?.cancel();

      // Recalculate remaining time with new deadline
      remainingTime = _calculateRemainingTime();

      if (remainingTime <= Duration.zero) {
        remainingTime = Duration.zero;
        _scheduleTimeout();
        return;
      }

      // Start a new timer
      timer = Timer.periodic(const Duration(seconds: 1), _updateTimer);
    }
  }

  Duration _calculateRemainingTime() {
    // Calculate the remaining time always from the deadline time and the current time
    // to ensure it updates correctly instead of just subtracting a second each time which
    // could lead to inaccuracies when the app is paused or resumed or other asynchronous events occur.
    return widget.until.difference(DateTime.now().toUtc());
  }

  void _updateTimer(Timer timer) {
    final nextRemainingTime = _calculateRemainingTime();
    if (nextRemainingTime <= Duration.zero) {
      timer.cancel();
      if (mounted) {
        setState(() {
          remainingTime = Duration.zero;
        });
      }
      _scheduleTimeout();
      return;
    }

    setState(() {
      remainingTime = nextRemainingTime;
    });
  }

  void _scheduleTimeout() {
    final deadline = widget.until;
    Timer.run(() {
      if (!mounted) return;
      if (deadline != widget.until) return;
      if (_calculateRemainingTime() > Duration.zero) return;
      widget.onTimeout();
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _formatRemainingTime(),
      style:
          widget.textStyle ??
          context.font.bodyMedium?.copyWith(
            fontWeight: .w500,
            color: context.appColors.primary,
          ),
    );
  }

  String _formatRemainingTime() {
    return switch (widget.format) {
      CountdownFormat.mmss =>
        '${remainingTime.inMinutes}:${(remainingTime.inSeconds % 60).toString().padLeft(2, '0')}',
      CountdownFormat.dhm => _formatDaysHoursMinutes(),
    };
  }

  String _formatDaysHoursMinutes() {
    final days = remainingTime.inDays;
    final hours = remainingTime.inHours % 24;
    final minutes = remainingTime.inMinutes % 60;

    if (days > 0) return '${days}d ${hours}h ${minutes}m';
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m';
  }
}
