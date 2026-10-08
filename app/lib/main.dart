import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'screens/home_screen.dart';
import 'models.dart';
import 'screens/login_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/device_storage.dart';
import 'services/notifications.dart';
import 'services/repo.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Приложение — диктофон в кармане: только вертикальная ориентация.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await initializeDateFormatting('ru');
  await ThemeController.load();
  await DeviceStorage.load();
  await Notifications.init();
  await Supabase.initialize(url: AppConfig.supabaseUrl, anonKey: AppConfig.supabaseAnonKey);
  runApp(const SamMariApp());
}

class SamMariApp extends StatelessWidget {
  const SamMariApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (_, mode, __) => MaterialApp(
        title: 'СамМари',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: mode,
        locale: const Locale('ru'),
        supportedLocales: const [Locale('ru')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const AuthGate(),
      ),
    );
  }
}

/// Показывает вход или главный экран в зависимости от сессии.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;
    return StreamBuilder<AuthState>(
      stream: auth.onAuthStateChange,
      builder: (context, _) => auth.currentSession == null ? const LoginScreen() : const _SignedIn(),
    );
  }
}

/// После входа: если роль ещё не выбрана — онбординг, иначе главная.
class _SignedIn extends StatefulWidget {
  const _SignedIn();
  @override
  State<_SignedIn> createState() => _SignedInState();
}

class _SignedInState extends State<_SignedIn> {
  late Future<bool> _onboarded = _load();

  Future<bool> _load() async {
    Repo.loadFolders().catchError((_) => <Folder>[]);
    try {
      return (await Repo.profile()).onboarded;
    } catch (_) {
      return true; // нет связи — не мешаем работе
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
        future: _onboarded,
        builder: (context, snap) {
          if (!snap.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
          if (snap.data == false) {
            return OnboardingScreen(onDone: () => setState(() {
                  _onboarded = Future.value(true);
                }));
          }
          return const HomeScreen();
        },
      );
}
