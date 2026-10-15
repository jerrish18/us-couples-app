import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config.dart';
import 'core/auth_links.dart';
import 'core/share_inbox.dart';
import 'features/location/live_location.dart';
import 'features/location/location_screen.dart';
import 'features/together/together_screen.dart';
import 'core/session.dart';
import 'core/theme.dart';
import 'core/settings.dart';
import 'core/space.dart';
import 'core/notifications.dart';
import 'features/home/home_screen.dart';
import 'features/chat/chat_screen.dart';
import 'features/calendar/calendar_screen.dart';
import 'features/memories/memories_screen.dart';
import 'features/more/more_screen.dart';
import 'features/lists/lists_screen.dart';
import 'features/journal/journal_screen.dart';
import 'features/auth/auth_screen.dart';
import 'features/pairing/pair_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var stage = 'Firebase';
  try {
    await Firebase.initializeApp(options: firebaseOptions);
    stage = 'Supabase';
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabaseKey,
      authOptions: FlutterAuthClientOptions(
        localStorage: SecureSessionStorage(),
        detectSessionInUri: false,
      ),
    );
    await AuthLinks.initialize();
    await ShareInbox.initialize();
    stage = 'local notifications';
    await UsNotifications.initialize();
    runApp(const ProviderScope(child: UsApp()));
  } catch (error) {
    // Startup diagnostics contain the component and error code, never credentials.
    debugPrint('Us startup failed at $stage: ${error.runtimeType}');
    if (error is PlatformException)
      debugPrint('Us platform error: ${error.code}');
    runApp(
      MaterialApp(
        theme: usTheme(Brightness.light),
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.favorite_outline, size: 56),
                  const SizedBox(height: 20),
                  const Text(
                    'Us could not start. Close and reopen the app to try again.',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class UsApp extends ConsumerStatefulWidget {
  const UsApp({super.key});
  @override
  ConsumerState<UsApp> createState() => _UsAppState();
}

class _UsAppState extends ConsumerState<UsApp> {
  late final GoRouter _router;
  StreamSubscription<String>? _notificationTaps;
  StreamSubscription<dynamic>? _shares;
  @override
  void initState() {
    super.initState();
    final session = ref.read(sessionProvider);
    _router = GoRouter(
      initialLocation: UsNotifications.initialRoute ?? '/',
      refreshListenable: session,
      redirect: (context, state) {
        if (!session.ready)
          return state.uri.path == '/loading' ? null : '/loading';
        if (session.userId == null)
          return state.uri.path == '/login' ? null : '/login';
        if (session.error != null)
          return state.uri.path == '/loading' ? null : '/loading';
        if (session.coupleId == null)
          return state.uri.path == '/pair' ? null : '/pair';
        if (['/login', '/pair', '/loading'].contains(state.uri.path)) {
          final route =
              UsNotifications.initialRoute ??
              (ShareInbox.pending.isNotEmpty ? '/chat' : '/');
          UsNotifications.initialRoute = null;
          return route;
        }
        return null;
      },
      routes: [
        GoRoute(
          path: '/loading',
          builder: (_, state) => Scaffold(
            body: Center(
              child: ListenableBuilder(
                listenable: session,
                builder: (context, _) => session.error == null
                    ? const CircularProgressIndicator()
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(session.error!),
                          TextButton(
                            onPressed: session.refresh,
                            child: const Text('Try again'),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
        GoRoute(path: '/login', builder: (_, state) => const AuthScreen()),
        GoRoute(path: '/pair', builder: (_, state) => const PairScreen()),
        ShellRoute(
          builder: (context, state, child) => AppLockGate(
            child: UsShell(path: state.uri.path, child: child),
          ),
          routes: [
            GoRoute(path: '/', builder: (_, state) => const HomeScreen()),
            GoRoute(path: '/chat', builder: (_, state) => const ChatScreen()),
            GoRoute(
              path: '/calendar',
              builder: (_, state) => const CalendarScreen(),
            ),
            GoRoute(
              path: '/memories',
              builder: (_, state) => const MemoriesScreen(),
            ),
            GoRoute(path: '/more', builder: (_, state) => const MoreScreen()),
          ],
        ),
        GoRoute(
          path: '/location',
          builder: (_, state) => const AppLockGate(child: LocationScreen()),
        ),
        GoRoute(
          path: '/letters',
          builder: (_, state) =>
              const AppLockGate(child: TogetherScreen(kind: 'letters')),
        ),
        GoRoute(
          path: '/expenses',
          builder: (_, state) =>
              const AppLockGate(child: TogetherScreen(kind: 'expenses')),
        ),
        GoRoute(
          path: '/collections',
          builder: (_, state) =>
              const AppLockGate(child: TogetherScreen(kind: 'collections')),
        ),
        GoRoute(
          path: '/lists',
          builder: (_, state) => const AppLockGate(child: ListsScreen()),
        ),
        GoRoute(
          path: '/journal',
          builder: (_, state) => const AppLockGate(child: JournalScreen()),
        ),
      ],
    );
    _notificationTaps = UsNotifications.taps.stream.listen(
      (route) => _router.go(route),
    );
    _shares = ShareInbox.changes.stream.listen((_) {
      if (session.userId != null && session.coupleId != null)
        _router.go('/chat');
    });
    if (ShareInbox.pending.isNotEmpty)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (session.coupleId != null) _router.go('/chat');
      });
    unawaited(UsNotifications.bind(session));
  }

  @override
  void dispose() {
    _shares?.cancel();
    _notificationTaps?.cancel();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    return ListenableBuilder(
      listenable: settings,
      builder: (_, child) => MaterialApp.router(
        title: 'Us',
        debugShowCheckedModeBanner: false,
        theme: usTheme(Brightness.light),
        darkTheme: usTheme(Brightness.dark),
        themeMode: settings.theme,
        routerConfig: _router,
      ),
    );
  }
}

class UsShell extends ConsumerWidget {
  const UsShell({super.key, required this.path, required this.child});
  final String path;
  final Widget child;
  static const paths = ['/', '/chat', '/calendar', '/memories', '/more'];
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final space = ref.watch(spaceProvider);
    final live = ref.watch(locationProvider);
    return ListenableBuilder(
      listenable: Listenable.merge([space, live]),
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Text(space.session.couple?['name'] as String? ?? 'Us'),
          actions: [
            if (space.syncing)
              const Padding(
                padding: EdgeInsets.all(18),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
          ],
        ),
        body: Column(
          children: [
            if (live.sharing)
              Material(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.my_location),
                  title: const Text('Live location is on'),
                  onTap: () => context.push('/location'),
                  trailing: TextButton(
                    onPressed: live.stop,
                    child: const Text('Stop'),
                  ),
                ),
              ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: KeyedSubtree(key: ValueKey(path), child: child),
              ),
            ),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: paths.indexOf(path).clamp(0, 4),
          onDestinationSelected: (index) => context.go(paths[index]),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline),
              selectedIcon: Icon(Icons.chat_bubble),
              label: 'Chat',
            ),
            NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined),
              selectedIcon: Icon(Icons.calendar_month),
              label: 'Calendar',
            ),
            NavigationDestination(
              icon: Icon(Icons.photo_library_outlined),
              selectedIcon: Icon(Icons.photo_library),
              label: 'Memories',
            ),
            NavigationDestination(icon: Icon(Icons.more_horiz), label: 'More'),
          ],
        ),
      ),
    );
  }
}
