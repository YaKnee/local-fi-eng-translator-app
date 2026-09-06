import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_result.dart' as stt;
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../models/tts_voice_model.dart';

class SpeechService {
  final stt.SpeechToText _speechToText =
      stt.SpeechToText();

  final FlutterTts _tts =
      FlutterTts();

  bool _initialized = false;
  String _recognizedText = '';

  Completer<String>?
      _recognitionCompleter;

  // ---------------------------------------------------------------------------
  // Speech recognition
  // ---------------------------------------------------------------------------

  bool get isInitialized =>
      _initialized;

  bool get isListening =>
      _speechToText.isListening;

  String get recognizedText =>
      _recognizedText;

  Future<bool> initialize() async {
    if (_initialized) {
      return true;
    }

    _initialized =
        await _speechToText.initialize(
      onError: (error) {
        print(
          'Speech recognition error: '
          '${error.errorMsg}',
        );

        final completer =
            _recognitionCompleter;

        if (completer != null &&
            !completer.isCompleted) {
          completer.complete(
            _recognizedText.trim(),
          );
        }
      },
      onStatus: (status) {
        print(
          'Speech recognition status: '
          '$status',
        );
      },
    );

    return _initialized;
  }

  /// Starts speech recognition.
  ///
  /// Examples:
  ///
  ///     startListening(localeId: 'fi-FI')
  ///     startListening(localeId: 'en-US')
  ///
  Future<bool> startListening({
    String? localeId,
  }) async {
    final initialized =
        await initialize();

    if (!initialized) {
      return false;
    }

    if (_speechToText.isListening) {
      await _speechToText.stop();
    }

    _recognizedText = '';

    _recognitionCompleter =
        Completer<String>();

    final options =
        stt.SpeechListenOptions(
      partialResults: true,
      pauseFor:
          const Duration(
        seconds: 3,
      ),
      listenFor:
          const Duration(
        seconds: 60,
      ),
      localeId: localeId,
      onDevice: false,
      cancelOnError: false,
      autoPunctuation: true,
    );

    await _speechToText.listen(
      onResult:
          _onSpeechResult,
      listenOptions:
          options,
    );

    return true;
  }

  Future<String> stopListening() async {
    if (!_speechToText.isListening) {
      final text =
          _recognizedText.trim();

      _recognitionCompleter =
          null;

      return text;
    }

    final completer =
        _recognitionCompleter;

    await _speechToText.stop();

    if (completer != null &&
        !completer.isCompleted) {
      try {
        await completer.future.timeout(
          const Duration(
            milliseconds: 750,
          ),
        );
      } on TimeoutException {
        // Use the latest recognized text.
      }
    }

    final transcription =
        _recognizedText.trim();

    _recognitionCompleter =
        null;

    return transcription;
  }

  Future<void> cancelListening() async {
    await _speechToText.cancel();

    _recognizedText = '';

    final completer =
        _recognitionCompleter;

    if (completer != null &&
        !completer.isCompleted) {
      completer.complete('');
    }

    _recognitionCompleter =
        null;
  }

  void _onSpeechResult(
    stt.SpeechRecognitionResult result,
  ) {
    final text =
        result.recognizedWords.trim();

    if (text.isNotEmpty) {
      _recognizedText = text;
    }

    final completer =
        _recognitionCompleter;

    if (result.finalResult &&
        completer != null &&
        !completer.isCompleted) {
      completer.complete(
        _recognizedText.trim(),
      );
    }
  }

  Future<List<stt.LocaleName>>
      getLocales() async {
    final initialized =
        await initialize();

    if (!initialized) {
      return [];
    }

    return _speechToText.locales();
  }

  Future<String?> getSystemLocale() async {
    final initialized =
        await initialize();

    if (!initialized) {
      return null;
    }

    final locale =
        await _speechToText.systemLocale();

    return locale?.localeId;
  }

  // ---------------------------------------------------------------------------
  // TTS
  // ---------------------------------------------------------------------------

  Future<void> setTtsLanguage(
    String language,
  ) async {
    await _tts.setLanguage(
      language,
    );
  }

  Future<void> setSpeechRate(
    double rate,
  ) async {
    await _tts.setSpeechRate(
      rate,
    );
  }

  Future<void> setVolume(
    double volume,
  ) async {
    await _tts.setVolume(
      volume,
    );
  }

  Future<void> setPitch(
    double pitch,
  ) async {
    await _tts.setPitch(
      pitch,
    );
  }

  // ---------------------------------------------------------------------------
  // TTS voices
  // ---------------------------------------------------------------------------

  /// Returns only English and Finnish TTS voices.
  ///
  /// This intentionally excludes every other installed language.
  Future<List<TtsVoice>>
      getTtsVoices() async {
    final voices =
        await _tts.getVoices;

    if (voices is! List) {
      return [];
    }

    final result = voices
        .whereType<Map>()
        .map(
          TtsVoice.fromPlatformMap,
        )
        .where(
          (voice) =>
              voice.name.isNotEmpty &&
              voice.locale.isNotEmpty,
        )
        .where(
          _isEnglishOrFinnish,
        )
        .toList();

    result.sort(
      (a, b) {
        final localeCompare =
            a.locale
                .toLowerCase()
                .compareTo(
                  b.locale
                      .toLowerCase(),
                );

        if (localeCompare != 0) {
          return localeCompare;
        }

        return a.name
            .toLowerCase()
            .compareTo(
              b.name
                  .toLowerCase(),
            );
      },
    );

    return result;
  }

  bool _isEnglishOrFinnish(
    TtsVoice voice,
  ) {
    final language =
        languageCodeForLocale(
      voice.locale,
    );

    return language == 'en' ||
        language == 'fi';
  }

  /// Returns the language portion of a locale.
  ///
  /// Examples:
  ///
  ///     fi-FI -> fi
  ///     fi_FI -> fi
  ///     en-US -> en
  ///     en_GB -> en
  String languageCodeForLocale(
    String locale,
  ) {
    final normalized =
        locale.trim().toLowerCase();

    if (normalized.isEmpty) {
      return '';
    }

    final hyphen =
        normalized.indexOf('-');

    final underscore =
        normalized.indexOf('_');

    var separator =
        hyphen;

    if (separator == -1 ||
        (underscore != -1 &&
            underscore < separator)) {
      separator = underscore;
    }

    if (separator == -1) {
      return normalized;
    }

    return normalized.substring(
      0,
      separator,
    );
  }

  /// Returns only voices belonging to [languageCode].
  ///
  /// [languageCode] must be:
  ///
  ///     fi
  ///     en
  Future<List<TtsVoice>>
      getTtsVoicesForLanguage(
    String languageCode,
  ) async {
    final normalized =
        languageCode.trim().toLowerCase();

    if (normalized != 'fi' &&
        normalized != 'en') {
      return [];
    }

    final voices =
        await getTtsVoices();

    return voices
        .where(
          (voice) =>
              languageCodeForLocale(
                voice.locale,
              ) ==
              normalized,
        )
        .toList();
  }

  /// Finds a suitable installed voice for a language.
  ///
  /// Finnish:
  ///   fi-FI is preferred.
  ///
  /// English:
  ///   en-US is preferred, then en-GB.
  Future<TtsVoice?> getDefaultTtsVoice(
    String languageCode,
  ) async {
    final voices =
        await getTtsVoicesForLanguage(
      languageCode,
    );

    if (voices.isEmpty) {
      return null;
    }

    final normalized =
        languageCode.trim().toLowerCase();

    if (normalized == 'fi') {
      for (final voice in voices) {
        if (voice.locale
                .toLowerCase() ==
            'fi-fi') {
          return voice;
        }
      }
    }

    if (normalized == 'en') {
      for (final voice in voices) {
        if (voice.locale
                .toLowerCase() ==
            'en-us') {
          return voice;
        }
      }

      for (final voice in voices) {
        if (voice.locale
                .toLowerCase() ==
            'en-gb') {
          return voice;
        }
      }
    }

    return voices.first;
  }

  /// Sets a specific TTS voice.
  Future<void> setTtsVoice(
    TtsVoice voice,
  ) async {
    final platformVoice =
        <String, String>{
      'name': voice.name,
      'locale': voice.locale,
    };

    if (voice.identifier != null &&
        voice.identifier!.isNotEmpty) {
      platformVoice['identifier'] =
          voice.identifier!;
    }

    await _tts.setVoice(
      platformVoice,
    );
  }

  /// Speaks using [voice].
  Future<void> speak(
    String text, {
    TtsVoice? voice,
  }) async {
    if (voice != null) {
      await setTtsVoice(
        voice,
      );
    }

    await _tts
        .awaitSpeakCompletion(true);

    await _tts.speak(text);
  }

  /// Speaks using the installed voice for a language.
  ///
  /// Example:
  ///
  ///     await speechService.speakInLanguage(
  ///       'Hei maailma',
  ///       languageCode: 'fi',
  ///     );
  Future<void> speakInLanguage(
    String text, {
    required String languageCode,
  }) async {
    final voice =
        await getDefaultTtsVoice(
      languageCode,
    );

    if (voice == null) {
      throw StateError(
        'No TTS voice is available '
        'for language "$languageCode".',
      );
    }

    await speak(
      text,
      voice: voice,
    );
  }

  Future<void> stopSpeaking() async {
    await _tts.stop();
  }

  // ---------------------------------------------------------------------------
  // TTS file generation
  // ---------------------------------------------------------------------------

  Future<void> synthesizeToFile({
    required String text,
    required String path,
    TtsVoice? voice,
  }) async {
    if (voice != null) {
      await setTtsVoice(
        voice,
      );
    }

    await _tts
        .awaitSynthCompletion(true);

    final result =
        await _tts.synthesizeToFile(
      text,
      path,
      true,
    );

    if (result != 1 &&
        result != true) {
      throw StateError(
        'Text-to-speech failed to create audio file.',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  Future<void> dispose() async {
    await _speechToText.cancel();
    await _tts.stop();
    _recognitionCompleter =
        null;
  }
}