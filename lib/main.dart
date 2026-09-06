import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import './screens/app_startup_screen.dart';
import './services/speech_service.dart';
import './services/storage_service.dart';
import './services/translation_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final preferences = await SharedPreferences.getInstance();

  final storage = StorageService(preferences);
  final speechService = SpeechService();
  final translationService = TranslationService();

  runApp(
    MultiProvider(
      providers: [
        Provider<StorageService>.value(
          value: storage,
        ),
        Provider<SpeechService>.value(
          value: speechService,
        ),
        ChangeNotifierProvider<TranslationService>.value(
          value: translationService,
        ),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    return MaterialApp(
      title: 'Offline Translator',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
        ),
        useMaterial3: true,
      ),
      home: const AppStartupScreen(),
    );
  }
}