import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:window_manager/window_manager.dart';
import 'utils/app_theme.dart';
import 'providers/theme_provider.dart';
import 'utils/constants.dart';
import 'screens/resident_home_screen.dart';
import 'screens/login_screen.dart';
import 'providers/auth_providers.dart';
import 'services/server_manager.dart';

final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = MyHttpOverrides();

  if (Platform.isMacOS) {
    await windowManager.ensureInitialized();
    windowManager.waitUntilReadyToShow(const WindowOptions(), () async {
      await windowManager.show();
      await windowManager.setHasShadow(true);
      await windowManager.focus();
    });
  }

  // ============================================================
  // Инициализация ServerManager
  // ============================================================
  const storage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
    mOptions: MacOsOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  final serverManager = ServerManagerNotifier(
    read: (key) => storage.read(key: 'sm_$key'),
    write: (key, value) => storage.write(key: 'sm_$key', value: value),
    onServerSwitch: () async {
      await storage.delete(key: AppConstants.accessTokenKey);
      await storage.delete(key: AppConstants.refreshTokenKey);
      debugPrint('🖥️ [Main] Токены очищены при смене сервера');
    },
  );
  await serverManager.init();

  // Устанавливаем текущие URL в AppConstants
  _syncConstants(serverManager.state);

  serverManager.addListener(() {
    _syncConstants(serverManager.state);
  });

  runApp(
    ProviderScope(
      overrides: [
        serverManagerProvider.overrideWith((_) => serverManager),
      ],
      child: const MyApp(),
    ),
  );
}

/// Синхронизация AppConstants с текущим активным сервером
void _syncConstants(ServerManagerState state) {
  AppConstants.baseUrl = state.currentBaseUrl;
  AppConstants.wsBaseUrl = state.currentWsBaseUrl;
  debugPrint('🖥️ [Main] baseUrl = ${AppConstants.baseUrl}');
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'Кабинет жильца',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      scaffoldMessengerKey: scaffoldMessengerKey,
      home: _getHome(authState),
    );
  }

  Widget _getHome(AuthState authState) {
    if (authState.isLoading && authState.status == AuthStatus.initial) {
      return const Scaffold(
        backgroundColor: AppTheme.darkBackground,
        body: Center(
          child: CircularProgressIndicator(color: AppTheme.primaryBlue),
        ),
      );
    }

    if (authState.status == AuthStatus.authenticated) {
      return const ResidentHomeScreen();
    }

    return const LoginScreen();
  }
}
