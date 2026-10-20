import 'dart:async';

import 'package:flutter/services.dart';

abstract final class UsHaptics {
  static const _channel = MethodChannel('us/presentation');
  static DateTime? _last;
  static void selection() => _play('selection');
  static void confirm() => _play('confirm');
  static void reject() => _play('reject');
  static void _play(String kind) {
    final now = DateTime.now();
    if (_last != null && now.difference(_last!).inMilliseconds < 70) return;
    _last = now;
    unawaited(
      _channel
          .invokeMethod<bool>('haptic', {'kind': kind})
          .then((handled) {
            if (handled != true)
              return kind == 'selection'
                  ? HapticFeedback.selectionClick()
                  : HapticFeedback.lightImpact();
          })
          .catchError((_) {
            return HapticFeedback.selectionClick();
          }),
    );
  }
}
