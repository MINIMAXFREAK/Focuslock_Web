import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'subjects_page.dart';

var logger = Logger();
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://gryeofxctwnafoqqujes.supabase.co',
    anonKey: 'sb_publishable_k4r7t7eDkq6_Hz8lUOIJcg_UOjAaQ7O',
  );

  final prefs = await SharedPreferences.getInstance();
  final isDark = prefs.getBool('isDark') ?? false;
  themeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;

  final session = Supabase.instance.client.auth.currentSession;

  runApp(MyApp(initialSession: session));
}

class MyApp extends StatelessWidget {
  final Session? initialSession;
  const MyApp({super.key, this.initialSession});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, themeMode, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          themeMode: themeMode,
          theme: ThemeData(
            brightness: Brightness.light,
            primarySwatch: Colors.indigo,
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            primarySwatch: Colors.indigo,
            useMaterial3: true,
          ),
          home: initialSession != null ? const SubjectsPage() : const LoginPage(),
        );
      },
    );
  }
}

Future<void> toggleTheme() async {
  final prefs = await SharedPreferences.getInstance();
  if (themeNotifier.value == ThemeMode.light) {
    themeNotifier.value = ThemeMode.dark;
    await prefs.setBool('isDark', true);
  } else {
    themeNotifier.value = ThemeMode.light;
    await prefs.setBool('isDark', false);
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  String message = '';

  @override
  void initState() {
    super.initState();

    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      final session = data.session;

      if (event == AuthChangeEvent.signedIn && session != null) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const SubjectsPage()),
        );
      } else if (event == AuthChangeEvent.signedOut) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginPage()),
        );
      }
    });
  }

  Future<void> login() async {
    try {
      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: emailController.text.trim(),
        password: passwordController.text,
      );

      if (!mounted) return;

      if (response.session != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const SubjectsPage()),
        );
      } else {
        setState(() => message = 'Login fehlgeschlagen: falsche Daten');
      }
    } catch (e) {
      logger.e('LOGIN ERROR: $e');
      if (!mounted) return;
      setState(() => message = 'Login fehlgeschlagen: falsche Email oder Passwort');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SizedBox(
          width: 360,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextField(
                controller: emailController,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: passwordController,
                decoration: const InputDecoration(labelText: 'Passwort'),
                obscureText: true,
              ),
              const SizedBox(height: 20),
              ElevatedButton(onPressed: login, child: const Text('Login')),
              const SizedBox(height: 10),
              Text(
                message,
                style: const TextStyle(color: Colors.red),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
