import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Own both cold-start and running-app callbacks. Never log callback URLs/tokens.
class AuthLinks {
  static const redirect = 'com.jerrish18.us://login-callback';
  static final errors = StreamController<String>.broadcast();
  static final _links = AppLinks();
  static final Set<String> _handled = {};
  static Future<void> _work = Future.value();
  static bool accepts(Uri uri) =>
      uri.scheme == 'com.jerrish18.us' && uri.host == 'login-callback';
  static Future<void> initialize() async {
    _links.uriLinkStream.listen(
      handle,
      onError: (Object _) {
        errors.add('Could not finish sign-in. Please try again.');
      },
    );
    final initial = await _links.getInitialLink();
    if (initial != null) handle(initial);
  }

  static void handle(Uri uri) {
    if (!accepts(uri)) return;
    _work = _work.then((_) async {
      final key = uri.toString();
      if (_handled.contains(key)) return;
      try {
        await Supabase.instance.client.auth.getSessionFromUrl(uri);
        _handled.add(key);
        // Keep only short-lived callback identifiers, in memory.
        if (_handled.length > 8) _handled.remove(_handled.first);
      } on AuthException catch (_) {
        errors.add(
          'Sign-in could not finish. Start Google sign-in again from Us, then return to this app.',
        );
      } catch (_) {
        errors.add('Could not connect to finish sign-in. Please try again.');
      }
    });
  }
}
