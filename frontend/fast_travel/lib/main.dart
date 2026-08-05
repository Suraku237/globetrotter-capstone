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
import 'Services/session_state.dart';
import 'theme/app_theme.dart';
import 'widgets/adaptive_shell.dart';

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

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GlobeTrotter',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
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
          if (role == 'admin') {
            return _AdminHomeScreen(session: _session);
          }
          if (role == 'worker') {
            return _WorkerHomeScreen(session: _session);
          }
          return _HomeShell(session: _session);
        },
      ),
    );
  }
}

class _AdminHomeScreen extends StatelessWidget {
  final SessionState session;
  const _AdminHomeScreen({required this.session});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin platform'),
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
                builder: (context) => ProfileScreen(session: session),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: Icon(Icons.logout_rounded, color: AppColors.inkSoft),
            onPressed: session.signOut,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.dashboard_customize_rounded),
              title: const Text('Admin dashboard'),
              subtitle:
                  const Text('Manage users, destinations, and monitoring.'),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.groups_rounded),
              title: const Text('User oversight'),
              subtitle: const Text('Review signups and role access.'),
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

class _WorkerHomeScreen extends StatelessWidget {
  final SessionState session;
  const _WorkerHomeScreen({required this.session});

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
                builder: (context) => ProfileScreen(session: session),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: Icon(Icons.logout_rounded, color: AppColors.inkSoft),
            onPressed: session.signOut,
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
  const _HomeShell({required this.session});

  @override
  State<_HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<_HomeShell> {
  int _index = 0;

  static const _titles = [
    'Discover Yaoundé',
    'Feed',
    'My Trips',
    'Explore Map'
  ];

  Widget get _body {
    switch (_index) {
      case 1:
        return FeedScreen(session: widget.session);
      case 2:
        return const ItinerariesScreen();
      case 3:
        return ExploreMapScreen(); // ✅ Correctly matched class name
      default:
        return const DiscoverScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveShell(
      title: _titles[_index],
      selectedIndex: _index,
      onDestinationSelected: (i) => setState(() => _index = i),
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
              builder: (context) => ProfileScreen(session: widget.session),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Sign out',
          icon: Icon(Icons.logout_rounded, color: AppColors.inkSoft),
          onPressed: widget.session.signOut,
        ),
      ],
      child: _body,
    );
  }
}
