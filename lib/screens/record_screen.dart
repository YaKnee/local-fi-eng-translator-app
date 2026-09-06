import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/translated_model.dart';
import '../services/speech_service.dart';
import '../services/storage_service.dart';
import '../services/translation_service.dart';
import '../widgets/transcription_dialog.dart';
import '../widgets/translation_preview_dialog.dart';

enum _ProcessingStep {
  none,
  processingSpeech,
  reviewing,
  translating,
  previewing,
  saving,
}

class RecordScreen extends StatefulWidget {
  const RecordScreen({super.key});

  @override
  State<RecordScreen> createState() =>
      _RecordScreenState();
}

class _RecordScreenState
    extends State<RecordScreen> {
  bool _isRecording = false;
  bool _isPointerDown = false;
  bool _stopRequested = false;

  _ProcessingStep _processingStep =
      _ProcessingStep.none;

  // ---------------------------------------------------------------------------
  // Language direction
  //
  // These are now the source of truth.
  //
  // The UI displays:
  //
  //     source → target
  //
  // and the swap button changes:
  //
  //     en → fi
  //     fi → en
  // ---------------------------------------------------------------------------

  String _sourceLang = 'fi';
  String _targetLang = 'en';

  TranslationDirection get _direction {
    if (_sourceLang == 'en' &&
        _targetLang == 'fi') {
      return TranslationDirection
          .englishToFinnish;
    }

    return TranslationDirection
        .finnishToEnglish;
  }

  String get _sourceLanguage {
    switch (_sourceLang) {
      case 'en':
        return 'English';
      case 'fi':
        return 'Finnish';
      default:
        return _sourceLang;
    }
  }

  String get _targetLanguage {
    switch (_targetLang) {
      case 'en':
        return 'English';
      case 'fi':
        return 'Finnish';
      default:
        return _targetLang;
    }
  }

  String get _sourceLocaleId {
    switch (_sourceLang) {
      case 'fi':
        return 'fi-FI';
      case 'en':
        return 'en-GB';
      default:
        return 'fi-FI';
    }
  }

  bool get _isProcessing {
    return _processingStep !=
        _ProcessingStep.none;
  }

  // ---------------------------------------------------------------------------
  // Direction
  // ---------------------------------------------------------------------------

  void _swapLanguages() {
    if (_isProcessing || _isRecording) {
      return;
    }

    setState(() {
      final oldSource = _sourceLang;

      _sourceLang = _targetLang;
      _targetLang = oldSource;
    });
  }

  // ---------------------------------------------------------------------------
  // Recording
  // ---------------------------------------------------------------------------

  Future<void> _handlePointerDown() async {
    if (_isProcessing || _isPointerDown) {
      return;
    }

    _isPointerDown = true;
    _stopRequested = false;

    await _startRecording();
  }

  Future<void> _handlePointerUp() async {
    _isPointerDown = false;

    if (_isProcessing) {
      return;
    }

    if (!_isRecording) {
      _stopRequested = true;
      return;
    }

    await _stopRecording();
  }

  Future<void> _handlePointerCancel() async {
    _isPointerDown = false;

    if (_isProcessing) {
      return;
    }

    if (!_isRecording) {
      _stopRequested = true;
      return;
    }

    await _stopRecording();
  }

  // TODO: Fix not recognising spoken Finnish
  Future<void> _startRecording() async {
    final speechService =
        context.read<SpeechService>();

    try {
      final speechInitialized =
          await speechService.initialize();

      if (!mounted) {
        return;
      }

      if (!speechInitialized) {
        _stopRequested = false;

        ScaffoldMessenger.of(context)
            .showSnackBar(
          const SnackBar(
            content: Text(
              'Speech recognition is not available.',
            ),
            backgroundColor: Colors.red,
          ),
        );

        return;
      }

      final listeningStarted =
          await speechService.startListening(localeId: _sourceLocaleId);

      if (!mounted) {
        return;
      }

      if (!listeningStarted) {
        _stopRequested = false;

        ScaffoldMessenger.of(context)
            .showSnackBar(
          const SnackBar(
            content: Text(
              'Could not start speech recognition.',
            ),
            backgroundColor: Colors.red,
          ),
        );

        return;
      }

      if (_stopRequested ||
          !_isPointerDown) {
        _stopRequested = false;

        await speechService.cancelListening();

        return;
      }

      setState(() {
        _isRecording = true;
      });
    } catch (error) {
      await speechService.cancelListening();

      if (!mounted) {
        return;
      }

      _stopRequested = false;

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            'Could not start speech recognition: $error',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Stop + process recording
  // ---------------------------------------------------------------------------

  Future<void> _stopRecording() async {
    if (!_isRecording) {
      return;
    }

    final speechService =
        context.read<SpeechService>();

    setState(() {
      _isRecording = false;
      _processingStep =
          _ProcessingStep.processingSpeech;
    });

    try {
      final transcription =
          await speechService.stopListening();

      if (!mounted) {
        return;
      }

      if (transcription.trim().isEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(
          const SnackBar(
            content: Text(
              'No speech was recognized.',
            ),
            backgroundColor: Colors.amber,
          ),
        );

        return;
      }

      await _reviewAndTranslate(
        transcription,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Could not process speech: $error',
            ),
            backgroundColor: Colors.red,
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          _processingStep =
              _ProcessingStep.none;
        });
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Manual text entry
  // ---------------------------------------------------------------------------

  Future<void> _enterTextManually() async {
    if (_isProcessing || _isRecording) {
      return;
    }

    await _reviewAndTranslate('');
  }

  // ---------------------------------------------------------------------------
  // Review + translate + preview + save
  // ---------------------------------------------------------------------------

  Future<void> _reviewAndTranslate(
    String initialText,
  ) async {
    if (!mounted) {
      return;
    }

    final storage =
        context.read<StorageService>();

    final translationService =
        context.read<TranslationService>();

    setState(() {
      _processingStep =
          _ProcessingStep.reviewing;
    });

    try {
      // -----------------------------------------------------------------------
      // 1. Review source text + category.
      // -----------------------------------------------------------------------

      final result =
          await _showTranscriptionDialog(
        initialText,
      );

      if (!mounted) {
        return;
      }

      if (result == null ||
          result.text.trim().isEmpty) {
        return;
      }

      final text =
          result.text.trim();

      // -----------------------------------------------------------------------
      // 2. Category
      // -----------------------------------------------------------------------

      final category =
          await _ensureCategory(
        result.category,
      );

      if (!mounted) {
        return;
      }

      // -----------------------------------------------------------------------
      // 3. Translate
      //
      // IMPORTANT:
      //
      // This is where the lazy ONNX model loading happens.
      //
      // If the selected direction is English -> Finnish
      // and the en-fi model hasn't been loaded yet,
      // TranslationService loads it here.
      // -----------------------------------------------------------------------

      setState(() {
        _processingStep =
            _ProcessingStep.translating;
      });

      final translatedText =
          await translationService.translate(
        text,
        _direction,
      );

      if (!mounted) {
        return;
      }

      if (translatedText.trim().isEmpty) {
        throw Exception(
          'Translation returned empty text.',
        );
      }

      // -----------------------------------------------------------------------
      // 4. Preview
      // -----------------------------------------------------------------------

      setState(() {
        _processingStep =
            _ProcessingStep.previewing;
      });

      final shouldSave =
          await _showTranslationPreview(
        originalText: text,
        translatedText:
            translatedText.trim(),
        category: category,
      );

      if (!mounted) {
        return;
      }

      if (!shouldSave) {
        return;
      }

      // -----------------------------------------------------------------------
      // 5. Save
      // -----------------------------------------------------------------------

      setState(() {
        _processingStep =
            _ProcessingStep.saving;
      });

      final now =
          DateTime.now();

      final translated =
          Translated(
        id: now.millisecondsSinceEpoch,
        createdAt: now,
        originalText: text,
        translatedText:
            translatedText.trim(),
        sourceLanguage:
            _sourceLang,
        targetLanguage:
            _targetLang,
        category: category,
      );

      await storage.saveTranslated(
        translated,
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              category == null
                  ? 'Translation saved.'
                  : 'Translation saved to "$category".',
            ),
            backgroundColor: Colors.green,
          ),
        );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Could not process text: $error',
            ),
            backgroundColor: Colors.red,
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          _processingStep =
              _ProcessingStep.none;
        });
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Category persistence
  // ---------------------------------------------------------------------------

  Future<String?> _ensureCategory(
    String? category,
  ) async {
    final trimmedCategory =
        category?.trim();

    if (trimmedCategory == null ||
        trimmedCategory.isEmpty) {
      return null;
    }

    final storage =
        context.read<StorageService>();

    final categories =
        storage.getCategories();

    for (final existingCategory
        in categories) {
      if (existingCategory.toLowerCase() ==
          trimmedCategory.toLowerCase()) {
        return existingCategory;
      }
    }

    await storage.saveCategory(
      trimmedCategory,
    );

    return trimmedCategory;
  }

  // ---------------------------------------------------------------------------
  // Dialogs
  // ---------------------------------------------------------------------------

  Future<TranscriptionDialogResult?>
      _showTranscriptionDialog(
    String transcription,
  ) {
    final storage =
        context.read<StorageService>();

    return showDialog<
        TranscriptionDialogResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return TranscriptionDialog(
          initialText: transcription,
          categories:
              storage.getCategories(),
        );
      },
    );
  }

  Future<bool> _showTranslationPreview({
    required String originalText,
    required String translatedText,
    required String? category,
  }) async {
    final result =
        await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return TranslationPreviewDialog(
          sourceLanguage:
              _sourceLanguage,
          targetLanguage:
              _targetLanguage,
          originalText:
              originalText,
          translatedText:
              translatedText,
          category:
              category,
        );
      },
    );

    return result ?? false;
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  String get _processingLabel {
    switch (_processingStep) {
      case _ProcessingStep.processingSpeech:
        return 'Processing speech...';

      case _ProcessingStep.reviewing:
        return 'Review the text...';

      case _ProcessingStep.translating:
        return 'Translating...';

      case _ProcessingStep.previewing:
        return 'Review translation...';

      case _ProcessingStep.saving:
        return 'Saving...';

      case _ProcessingStep.none:
        return '';
    }
  }

  IconData get _statusIcon {
    if (_processingStep ==
        _ProcessingStep.translating) {
      return Icons.translate;
    }

    if (_processingStep ==
        _ProcessingStep.previewing) {
      return Icons.preview_outlined;
    }

    if (_processingStep ==
        _ProcessingStep.saving) {
      return Icons.save_outlined;
    }

    if (_processingStep ==
        _ProcessingStep.processingSpeech) {
      return Icons.hourglass_top;
    }

    if (_processingStep ==
        _ProcessingStep.reviewing) {
      return Icons.edit_note;
    }

    if (_isRecording) {
      return Icons.mic;
    }

    return Icons.mic_none;
  }

  @override
  void dispose() {
    // SpeechService is shared and owned by the application root.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme =
        Theme.of(context);

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding:
              const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 32,
          ),
          child: Column(
            mainAxisAlignment:
                MainAxisAlignment.center,
            children: [
              // -----------------------------------------------------------------
              // Language direction
              // -----------------------------------------------------------------

              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _sourceLanguage,
                    style:
                        theme.textTheme.titleLarge,
                  ),

                  const SizedBox(width: 12),

                  Icon(
                    Icons.arrow_forward,
                    color:
                        theme.colorScheme.primary,
                  ),

                  const SizedBox(width: 12),

                  Text(
                    _targetLanguage,
                    style:
                        theme.textTheme.titleLarge,
                  ),

                  const SizedBox(width: 8),

                  IconButton.filled(
                    tooltip:
                        'Switch languages',
                    onPressed:
                        _isProcessing ||
                                _isRecording
                            ? null
                            : _swapLanguages,
                    icon: const Icon(
                      Icons.swap_horiz,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 36),

              // -----------------------------------------------------------------
              // Record button
              // -----------------------------------------------------------------

              Listener(
                onPointerDown:
                    _isProcessing
                        ? null
                        : (_) =>
                            _handlePointerDown(),
                onPointerUp:
                    _isProcessing
                        ? null
                        : (_) =>
                            _handlePointerUp(),
                onPointerCancel:
                    _isProcessing
                        ? null
                        : (_) =>
                            _handlePointerCancel(),
                child: Material(
                  elevation:
                      _isRecording ? 2 : 6,
                  shape:
                      const CircleBorder(),
                  color:
                      _isRecording
                          ? theme
                              .colorScheme
                              .error
                          : theme
                              .colorScheme
                              .primary,
                  shadowColor:
                      Colors.black54,
                  child: Container(
                    width: 140,
                    height: 140,
                    decoration:
                        BoxDecoration(
                      shape:
                          BoxShape.circle,
                      border:
                          Border.all(
                        color:
                            _isRecording
                                ? theme
                                    .colorScheme
                                    .primaryContainer
                                : theme
                                    .colorScheme
                                    .inversePrimary,
                        width: 3,
                      ),
                    ),
                    child: Icon(
                      _statusIcon,
                      size: 64,
                      color:
                          theme
                              .colorScheme
                              .onPrimary,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // -----------------------------------------------------------------
              // Status
              // -----------------------------------------------------------------

              if (_isProcessing) ...[
                const SizedBox(
                  width: 220,
                  child:
                      LinearProgressIndicator(),
                ),
                const SizedBox(height: 12),
                Text(
                  _processingLabel,
                  style:
                      theme.textTheme.bodyLarge,
                ),
              ] else ...[
                Text(
                  _isRecording
                      ? 'Release to stop'
                      : 'Press and hold to record',
                  style:
                      theme.textTheme.bodyMedium,
                ),

                const SizedBox(height: 20),

                // -----------------------------------------------------------------
                // Manual entry
                // -----------------------------------------------------------------

                OutlinedButton.icon(
                  onPressed:
                      _enterTextManually,
                  icon: const Icon(
                    Icons.keyboard_outlined,
                  ),
                  label: const Text(
                    'Enter text manually',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}