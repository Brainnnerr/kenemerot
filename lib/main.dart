import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'login_screen.dart';
import 'home_screen.dart';
import 'reset_password_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://rxcfjykqfdamsnvsrcvr.supabase.co',
    publishableKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJ4Y2ZqeWtxZmRhbXNudnNyY3ZyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTM0MTg4MjUsImV4cCI6MjEwODk5NDgyNX0.ljJIlR1kTczDT84D2FyU7k1uyFxARLSgebXmC5qLz1c',
  );

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();

    // Listen to Auth State changes (e.g. Password Recovery event)
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final AuthChangeEvent event = data.event;

      if (event == AuthChangeEvent.passwordRecovery) {
        _navigatorKey.currentState?.pushReplacement(
          MaterialPageRoute(builder: (_) => const ResetPasswordScreen()),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'KenemeRoute',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF0F5B33),
        scaffoldBackgroundColor: Colors.white,
      ),
      home: const AnimatedSplashScreen(),
    );
  }
}

class AnimatedSplashScreen extends StatefulWidget {
  const AnimatedSplashScreen({super.key});

  @override
  State<AnimatedSplashScreen> createState() => _AnimatedSplashScreenState();
}

class _AnimatedSplashScreenState extends State<AnimatedSplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _logoController;
  late Animation<double> _logoScaleAnimation;
  late Animation<double> _logoFadeAnimation;

  late AnimationController _textController;
  late Animation<double> _textFadeAnimation;

  @override
  void initState() {
    super.initState();

    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _logoFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeIn),
    );

    _logoScaleAnimation = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeOutBack),
    );

    _textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _textFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _textController, curve: Curves.easeIn),
    );

    _initializeApp();
  }

  void _initializeApp() async {
    _logoController.forward();
    await Future.delayed(const Duration(milliseconds: 300));
    _textController.forward();

    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    final session = Supabase.instance.client.auth.currentSession;
    final Widget targetScreen =
        (session != null) ? const HomeScreen() : const LoginScreen();

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 600),
        pageBuilder: (context, animation, secondaryAnimation) => targetScreen,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  void dispose() {
    _logoController.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: _logoController,
              builder: (context, child) {
                return FadeTransition(
                  opacity: _logoFadeAnimation,
                  child: ScaleTransition(
                    scale: _logoScaleAnimation,
                    child: Image.asset(
                      'assets/images/kenemeroute-logo.png',
                      width: 220,
                      height: 220,
                      fit: BoxFit.contain,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 4),
            FadeTransition(
              opacity: _textFadeAnimation,
              child: const Text(
                'KenemeRoute',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F5B33),
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}