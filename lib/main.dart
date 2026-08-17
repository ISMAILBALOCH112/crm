import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'screens/auth_gate.dart';
import 'screens/signup_screen.dart';
import 'services/invite_session.dart';
import 'services/push_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _navKey = GlobalKey<NavigatorState>();
  StreamSubscription<Uri>? _linkSub;

  @override
  void initState() {
    super.initState();
    _initInviteLinks();
  }

  Future<void> _initInviteLinks() async {
    final appLinks = AppLinks();
    try {
      final initial = await appLinks.getInitialLink();
      if (initial != null) _onInviteUri(initial);
    } catch (_) {}
    _linkSub = appLinks.uriLinkStream.listen(_onInviteUri);
  }

  void _onInviteUri(Uri uri) {
    final token = InviteSession.parseUri(uri);
    if (token == null || token.isEmpty) return;
    InviteSession.setToken(token);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final nav = _navKey.currentState;
      if (nav == null) return;
      // Already signed in — keep token for later / ignore signup push.
      if (FirebaseAuth.instance.currentUser != null) {
        ScaffoldMessenger.of(nav.context).showSnackBar(
          const SnackBar(content: Text('Already signed in. Sign out to join with this invite.')),
        );
        return;
      }
      nav.push(
        MaterialPageRoute(builder: (_) => SignupScreen(inviteToken: token)),
      );
    });
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navKey,
      title: 'WaTech',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const AuthGate(),
    );
  }
}
