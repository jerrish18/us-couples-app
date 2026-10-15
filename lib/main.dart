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
import 'core/design.dart';
import 'core/feature_header.dart';
import 'core/ui.dart';
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
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await VisualCapabilities.initialize();
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
          body: AmbientMesh(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(UsTokens.s32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.favorite_outline, size: UsTokens.s56),
                    const SizedBox(height: UsTokens.s20),
                    const Text(
                      'Us could not start. Close and reopen the app to try again.',
                    ),
                  ],
                ),
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
                    ? const LoadingPanel()
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
          builder: (_, state) => const FeatureScope(
            accent: Accent.blue,
            child: AppLockGate(child: LocationScreen()),
          ),
        ),
        GoRoute(
          path: '/letters',
          builder: (_, state) => const FeatureScope(
            accent: Accent.pink,
            child: AppLockGate(child: TogetherScreen(kind: 'letters')),
          ),
        ),
        GoRoute(
          path: '/expenses',
          builder: (_, state) => const FeatureScope(
            accent: Accent.green,
            child: AppLockGate(child: TogetherScreen(kind: 'expenses')),
          ),
        ),
        GoRoute(
          path: '/collections',
          builder: (_, state) => const FeatureScope(
            accent: Accent.coral,
            child: AppLockGate(child: TogetherScreen(kind: 'collections')),
          ),
        ),
        GoRoute(
          path: '/lists',
          builder: (_, state) => const FeatureScope(
            accent: Accent.green,
            child: AppLockGate(child: ListsScreen()),
          ),
        ),
        GoRoute(
          path: '/journal',
          builder: (_, state) => const FeatureScope(
            accent: Accent.lavender,
            child: AppLockGate(child: JournalScreen()),
          ),
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
        builder: (context, child) =>
            AmbientMesh(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}

class UsShell extends ConsumerWidget {
  const UsShell({super.key, required this.path, required this.child});
  final String path;
  final Widget child;
  static const paths = ['/', '/chat', '/calendar', '/memories', '/more'];
  static const tables = {
    '/': 'profiles',
    '/chat': 'messages',
    '/calendar': 'dates',
    '/memories': 'memories',
    '/more': 'profiles',
  };
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final space = ref.watch(spaceProvider);
    final live = ref.watch(locationProvider);
    return ListenableBuilder(
      listenable: Listenable.merge([space, live]),
      builder: (context, _) => Scaffold(
        extendBody: true,
        appBar: GlassAppBar(
          blur: path != '/chat',
          leading: IconButton(
            tooltip: 'Profile and settings',
            onPressed: () => context.go('/more'),
            icon: FlowerBadge(
              child: space.me?['avatar_path'] == null
                  ? null
                  : PrivatePhoto(
                      space,
                      space.me!['avatar_path'] as String,
                      height: UsTokens.s40,
                    ),
              icon: Icons.person_rounded,
              accent: Accent.lavender,
              size: UsTokens.s40,
            ),
          ),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.favorite_rounded,
                size: UsTokens.s16,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: UsTokens.s8),
              Flexible(
                child: Text(
                  space.session.couple?['name'] as String? ?? 'Us',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Find a feature',
              icon: const Icon(Icons.search_rounded),
              onPressed: () => showFeatureSearch(context),
            ),
            IconButton(
              tooltip: 'Dates and reminders',
              icon: const Icon(Icons.notifications_none_rounded),
              onPressed: () => showPlansOverview(context, space),
            ),
            if (space.syncing)
              const Padding(
                padding: EdgeInsets.all(UsTokens.s16),
                child: SizedBox(
                  width: UsTokens.s16,
                  height: UsTokens.s16,
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
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(context).bottom > 0
                      ? 0
                      : UsTokens.s96,
                ),
                child: FeatureScope(
                  accent: const [
                    Accent.yellow,
                    Accent.blue,
                    Accent.coral,
                    Accent.pink,
                    Accent.lavender,
                  ][paths.indexOf(path).clamp(0, 4)],
                  child: PageEntrance(
                    key: ValueKey(path),
                    child: SpaceBody(
                      space: space,
                      table: tables[path],
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: MediaQuery.viewInsetsOf(context).bottom > 0
            ? null
            : Center(
                heightFactor: 1,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: UsTokens.navMaxWidth,
                  ),
                  child: UsDock(
                    selected: paths.indexOf(path).clamp(0, 4),
                    onSelect: (index) {
                      if (path != paths[index]) context.go(paths[index]);
                    },
                  ),
                ),
              ),
      ),
    );
  }
}
