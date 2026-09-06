import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/translation_service.dart';
import 'main_screen.dart';

class AppStartupScreen extends StatefulWidget {
  const AppStartupScreen({super.key});

  @override
  State<AppStartupScreen> createState() => _AppStartupScreenState();
}

class _AppStartupScreenState extends State<AppStartupScreen> {
  bool _loading = true;
  Object? _error;

  TranslationService? _translationService;

  @override
  void initState() {
    super.initState();

    _translationService = context.read<TranslationService>();

    _initialize();
  }

  Future<void> _initialize() async {
    if (!mounted) {
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final translationService = context.read<TranslationService>();

      await translationService.initialize();

      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
      });
    } catch (error, stackTrace) {
      debugPrint('Application startup failed: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      final translationService =
          _translationService ?? context.read<TranslationService>();

      return AnimatedBuilder(
        animation: translationService,
        builder: (context, _) {
          return _LoadingScreen(
            progress: translationService.loadingProgress,
            status: translationService.loadingStatus,
          );
        },
      );
    }

    if (_error != null) {
      return _StartupErrorScreen(error: _error!, onRetry: _initialize);
    }

    return const MainScreen();
  }
}

class _LoadingScreen extends StatelessWidget {
  final double progress;
  final String status;

  const _LoadingScreen({required this.progress, required this.status});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final percentage = (progress * 100).round();

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/icon.png',
                width: 96,
                height: 96,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 32),
              Text(
                'Offline Translator',
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Preparing Finnish → English',
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                status,
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 10),
              Text('$percentage%', style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _StartupErrorScreen extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const _StartupErrorScreen({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 24),
              Text(
                'Could not load translation models',
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                '$error',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
