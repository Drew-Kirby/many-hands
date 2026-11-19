import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:material_ui/material_ui.dart';

import 'firebase_options.dart';
import 'screens/auth.dart';
import 'screens/home.dart';
import 'screens/issues.dart';
import 'screens/me.dart';
import 'screens/members.dart';
import 'screens/search.dart';
import 'store.dart';
import 'widgets.dart';

// Change this to your group's name. It shows on the sign-in screen.
const communityName = 'Eastside Community Food Bank';

// App Check proves requests come from this app; Firebase requires it for Ask AI (AI Logic).
// Web: reCAPTCHA (Fraud Defense) site key for localhost and drew-kirby.github.io. Public by design.
const recaptchaSiteKey = '6LehwyYuAAAAAIPTWq5KKzxo3jAiggSN6o6cTejk';
// Android: a debug token registered in Firebase (App Check > Apps > Android > Manage debug tokens),
// because sideloaded APKs can't use Play Integrity. Fine for a class project; a store release would use Play Integrity.
const appCheckDebugToken = 'ED00B89C-6C2B-44F7-9DA1-3B2170A0DA2B';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await FirebaseAppCheck.instance.activate(
    providerWeb: ReCaptchaEnterpriseProvider(recaptchaSiteKey),
    providerAndroid: const AndroidDebugProvider(debugToken: appCheckDebugToken),
  );
  runApp(const ManyHandsApp());
}

class ManyHandsApp extends StatelessWidget {
  const ManyHandsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Many Hands',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: brand,
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
      ),
      home: const AuthGate(),
    );
  }
}

// Signed out → sign-in. Signed in → wait for the profile, then the app.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: auth.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) return const Loading();
        final user = snap.data;
        if (user == null) {
          store.stop();
          return const AuthScreen(communityName: communityName);
        }
        return MemberGate(key: ValueKey(user.uid), user: user);
      },
    );
  }
}

class MemberGate extends StatefulWidget {
  final User user;
  const MemberGate({super.key, required this.user});
  @override
  State<MemberGate> createState() => _MemberGateState();
}

class _MemberGateState extends State<MemberGate> {
  @override
  void initState() {
    super.initState();
    store.start();
  }

  @override
  Widget build(BuildContext context) {
    final uid = widget.user.uid;
    // A removed member's login still works, but the rules refuse everything, so explain instead.
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: db.collection('bans').doc(uid).snapshots(),
      builder: (context, ban) {
        if (ban.data?.exists == true) return const BannedScreen();
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: db.collection('members').doc(uid).snapshots(),
          builder: (context, snap) {
            if (!snap.hasData) return const Loading();
            final doc = snap.data!;
            if (doc.exists) return const HomeShell();
            // Right after sign-up the profile may still be on its way; wait for the server.
            return ValueListenableBuilder<bool>(
              valueListenable: signingUp,
              builder: (context, busy, _) =>
                  busy || doc.metadata.isFromCache ? const Loading() : FinishProfile(user: widget.user),
            );
          },
        );
      },
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(onOpenTab: (i) => setState(() => _tab = i)),
      const IssuesScreen(),
      const SearchScreen(),
      const MembersScreen(),
      const MeScreen(),
    ];
    return Scaffold(
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.list_alt_outlined), selectedIcon: Icon(Icons.list_alt), label: 'Issues'),
          NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome), label: 'Ask AI'),
          NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'Members'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Me'),
        ],
      ),
    );
  }
}

class Loading extends StatelessWidget {
  const Loading({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class BannedScreen extends StatelessWidget {
  const BannedScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('You were removed from this community.', textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              const Text('Ask an admin if you think this is a mistake.', textAlign: TextAlign.center),
              const SizedBox(height: 24),
              OutlinedButton(onPressed: () => auth.signOut(), child: const Text('Log out')),
            ]),
          ),
        ),
      );
}
