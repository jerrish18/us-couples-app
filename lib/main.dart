import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/config.dart';
import 'core/session.dart';
import 'core/theme.dart';
import 'features/auth/auth_screen.dart';
import 'features/pairing/pair_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(options: firebaseOptions);
    await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseKey,
      authOptions: FlutterAuthClientOptions(localStorage: SecureSessionStorage()));
    runApp(const ProviderScope(child: UsApp()));
  } catch (_) {
    runApp(MaterialApp(theme: usTheme(Brightness.light), home: Scaffold(body: Center(child: Padding(
      padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.favorite_outline, size: 56), const SizedBox(height: 20),
        const Text('Us could not start. Close and reopen the app to try again.'),
      ]),
    )))));
  }
}

class UsApp extends ConsumerStatefulWidget {
  const UsApp({super.key});
  @override
  ConsumerState<UsApp> createState() => _UsAppState();
}
class _UsAppState extends ConsumerState<UsApp> {
  late final GoRouter _router;
  @override
  void initState() {
    super.initState();
    final session = ref.read(sessionProvider);
    _router = GoRouter(refreshListenable: session, redirect: (context, state) {
      if (!session.ready) return state.uri.path == '/loading' ? null : '/loading';
      if (session.userId == null) return state.uri.path == '/login' ? null : '/login';
      if (session.error != null) return state.uri.path == '/loading' ? null : '/loading';
      if (session.coupleId == null) return state.uri.path == '/pair' ? null : '/pair';
      if (['/login', '/pair', '/loading'].contains(state.uri.path)) return '/';
      return null;
    }, routes: [
      GoRoute(path: '/loading', builder: (_, state) => Scaffold(body: Center(child: ListenableBuilder(
        listenable: session, builder: (context, _) => session.error == null ? const CircularProgressIndicator()
          : Column(mainAxisSize: MainAxisSize.min, children: [Text(session.error!),
            TextButton(onPressed: session.refresh, child: const Text('Try again'))]),
      )))),
      GoRoute(path: '/login', builder: (_, state) => const AuthScreen()),
      GoRoute(path: '/pair', builder: (_, state) => const PairScreen()),
      GoRoute(path: '/', builder: (_, state) => const FoundationHome()),
    ]);
  }
  @override
  void dispose() { _router.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => MaterialApp.router(title: 'Us', debugShowCheckedModeBanner: false,
    theme: usTheme(Brightness.light), darkTheme: usTheme(Brightness.dark), routerConfig: _router);
}

// This is the account/pairing foundation; remaining features are implemented before release.
class FoundationHome extends ConsumerWidget {
  const FoundationHome({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    return Scaffold(appBar: AppBar(title: Text(session.couple?['name'] as String? ?? 'Us'),
      actions: [IconButton(tooltip: 'Refresh', onPressed: session.refresh, icon: const Icon(Icons.refresh)),
        IconButton(tooltip: 'Sign out', onPressed: () => session.client.auth.signOut(), icon: const Icon(Icons.logout))]),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        const Icon(Icons.favorite_rounded, size: 72), const SizedBox(height: 24),
        Text(session.partnerId == null ? 'Waiting for your person' : 'Your private space',
          style: Theme.of(context).textTheme.headlineMedium), const SizedBox(height: 16),
        if (session.partnerId == null) FutureBuilder<String?>(future: session.invite(), builder: (context, snapshot) =>
          snapshot.hasError ? const Text('Could not load your invite. Tap refresh to try again.')
          : snapshot.connectionState != ConnectionState.done ? const Center(child: CircularProgressIndicator())
          : SelectableText(snapshot.data ?? '', textAlign: TextAlign.center, style: Theme.of(context).textTheme.displaySmall)),
        const SizedBox(height: 16), Text(session.partnerId == null
          ? 'Share this code with your partner. Ask them to choose “Join my person” after signing in.'
          : 'Your space is locked to the two of you.'),
      ]));
  }
}
