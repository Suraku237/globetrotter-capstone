import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'screens/admin/pending_destinations_screen.dart';
import 'screens/assistant/assistant_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/feed/feed_screen.dart';
import 'screens/home/discover_screen.dart';
import 'screens/itineraries/itineraries_screen.dart';
import 'screens/home/map_screen.dart'; // ✅ This imports ExploreMapScreen
import 'screens/profile/profile_screen.dart';
import 'Services/api_service.dart';
import 'Services/locale_controller.dart';
import 'Services/session_state.dart';
import 'l10n/generated/app_localizations.dart';
import 'theme/app_theme.dart';
import 'widgets/adaptive_shell.dart';
import 'widgets/logout_confirm.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const GlobeTrotterApp());
}

class GlobeTrotterApp extends StatefulWidget {
  const GlobeTrotterApp({super.key});

  @override
  State<GlobeTrotterApp> createState() => _GlobeTrotterAppState();
}

class _GlobeTrotterAppState extends State<GlobeTrotterApp> {
  final _session = SessionState();
  final _localeController = LocaleController();

  @override
  void initState() {
    super.initState();
    // A rejected token (expired, or otherwise invalid) should always drop
    // the user back on the login screen instead of leaving screens stuck
    // showing a stale "can't reach server" error.
    ApiService.instance.onUnauthorized = _session.signOut;
    _localeController.load();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _localeController,
      builder: (context, _) {
        return MaterialApp(
          title: 'GlobeTrotter',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          locale: _localeController.locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AnimatedBuilder(
            animation: _session,
            builder: (context, _) {
              if (!_session.isSignedIn) {
                return LoginScreen(
                  session: _session,
                  onSignedIn: () => setState(() {}),
                );
              }

              final role = _session.currentUser?.role ?? 'user';
              if (role == 'worker') {
                return _WorkerHomeScreen(
                  session: _session,
                  localeController: _localeController,
                );
              }
              // Admins get the exact same app regular users see (Discover,
              // Feed, My Trips, Map) plus an extra entry point for
              // destination moderation and the ability to delete posts —
              // not a separate, more limited dashboard.
              return _HomeShell(
                session: _session,
                isAdmin: role == 'admin',
                localeController: _localeController,
              );
            },
          ),
        );
      },
    );
  }
}

class _WorkerHomeScreen extends StatelessWidget {
  final SessionState session;
  final LocaleController localeController;
  const _WorkerHomeScreen(
      {required this.session, required this.localeController});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Worker platform'),
        backgroundColor: AppColors.canopy,
        actions: [
          IconButton(
            tooltip: 'Ask the assistant',
            icon: Icon(Icons.forum_rounded, color: AppColors.inkSoft),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const AssistantScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Profile',
            icon: Icon(Icons.account_circle_rounded, color: AppColors.inkSoft),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ProfileScreen(
                session: session,
                localeController: localeController,
              ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: Icon(Icons.logout_rounded, color: AppColors.inkSoft),
            onPressed: () async {
              if (await confirmSignOut(context)) session.signOut();
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.assignment_turned_in_rounded),
              title: const Text('Assigned tasks'),
              subtitle: const Text(
                  'Track daily service operations for Yaoundé visitors.'),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.route_rounded),
              title: const Text('Trip support'),
              subtitle: const Text('Coordinate itineraries and check-ins.'),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.fact_check_rounded),
              title: const Text('Review destination submissions'),
              subtitle: const Text('Approve or reject user-suggested destinations.'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const PendingDestinationsScreen(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeShell extends StatefulWidget {
  final SessionState session;
  final bool isAdmin;
  final LocaleController localeController;
  const _HomeShell({
    required this.session,
    required this.localeController,
    this.isAdmin = false,
  });

  @override
  State<_HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<_HomeShell> {
  int _index = 0;
  // Changing this forces DiscoverScreen to fully remount (and so reload
  // its destinations) after the admin returns from reviewing submissions —
  // it's otherwise a long-lived widget instance that only loads once, in
  // initState(), so a newly-approved destination wouldn't appear until
  // the app restarted.
  Key _discoverKey = UniqueKey();

  List<String> _titles(AppLocalizations l10n) => [
        l10n.titleDiscover,
        l10n.titleFeed,
        l10n.titleMyTrips,
        l10n.titleExploreMap,
        l10n.titleProfile,
      ];

  Widget get _body {
    switch (_index) {
      case 1:
        return FeedScreen(session: widget.session);
      case 2:
        return const ItinerariesScreen();
      case 3:
        return ExploreMapScreen(); // ✅ Correctly matched class name
      case 4:
        return ProfileScreen(
          session: widget.session,
          localeController: widget.localeController,
          embedded: true,
        );
      default:
        return DiscoverScreen(key: _discoverKey, isAdmin: widget.isAdmin);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AdaptiveShell(
      title: _titles(l10n)[_index],
      selectedIndex: _index,
      onDestinationSelected: (i) => setState(() => _index = i),
      avatarUrl: widget.session.currentUser?.avatarUrl,
      userName: widget.session.currentUser?.fullName,
      actions: [
        if (widget.isAdmin)
          IconButton(
            tooltip: l10n.reviewDestinationsTooltip,
            icon: const Icon(Icons.fact_check_rounded,
                color: AppColors.inkSoft),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const PendingDestinationsScreen(),
                ),
              );
              // Whatever was approved/rejected/edited in there, force
              // Discover to reload so it reflects the current state.
              if (mounted) setState(() => _discoverKey = UniqueKey());
            },
          ),
      ],
      child: _body,
    );
  }
}
