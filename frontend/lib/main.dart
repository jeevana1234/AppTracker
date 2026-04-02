import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/auth/login_screen.dart';
import 'screens/home/home_shell.dart';
import 'screens/jobs/jobs_screen.dart';
import 'screens/universities/universities_screen.dart';
import 'screens/resume/resume_screen.dart';
import 'screens/profile/profile_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://xvzsuwxughgqwhtyacuo.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inh2enN1d3h1Z2hncXdodHlhY3VvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUxMTg3NjUsImV4cCI6MjA5MDY5NDc2NX0.Ru5IhSmQo85rhEKfh4rjEbHk3hPIyd_sjmk8wJEJ7_w',
  );
  runApp(const AppTrackApp());
}

class _AuthNotifier extends ChangeNotifier {
  _AuthNotifier() {
    Supabase.instance.client.auth.onAuthStateChange
        .listen((_) => notifyListeners());
  }
}

final _authNotifier = _AuthNotifier();

final _router = GoRouter(
  refreshListenable: _authNotifier,
  initialLocation: '/login',
  redirect: (context, state) {
    final loggedIn = Supabase.instance.client.auth.currentSession != null;
    final onLogin = state.matchedLocation == '/login';
    if (loggedIn && onLogin) return '/jobs';
    if (!loggedIn && !onLogin) return '/login';
    return null;
  },
  routes: [
    GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
    ShellRoute(
      builder: (_, __, child) => HomeShell(child: child),
      routes: [
        GoRoute(path: '/jobs', builder: (_, __) => const JobsScreen()),
        GoRoute(
            path: '/universities',
            builder: (_, __) => const UniversitiesScreen()),
        GoRoute(path: '/resume', builder: (_, __) => const ResumeScreen()),
        GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
      ],
    ),
  ],
);

class AppTrackApp extends StatelessWidget {
  const AppTrackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'AppTrack',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
        useMaterial3: true,
      ),
      routerConfig: _router,
    );
  }
}
