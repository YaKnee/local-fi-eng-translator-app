import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/tts_voice_model.dart';
import '../models/translated_model.dart';

class StorageService {
  static const String _translatedKey = 'translated';
  static const String _categoriesKey = 'categories';

  static const String _originalTtsVoiceKey = 'original_tts_voice';
  static const String _translatedTtsVoiceKey = 'translated_tts_voice';
  static const String _legacyTtsVoiceKey = 'tts_voice';

  final SharedPreferences _preferences;

  StorageService(this._preferences);

  // ---------------------------------------------------------------------------
  // Translated
  // ---------------------------------------------------------------------------

  Future<List<Translated>> getTranslated() async {
    final value = _preferences.getString(_translatedKey);

    if (value == null) {
      return [];
    }

    try {
      final decoded = jsonDecode(value);

      if (decoded is! List) {
        return [];
      }

      return decoded
          .whereType<Map>()
          .map((item) => Translated.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveTranslated(Translated translated) async {
    final items = await getTranslated();

    items.add(translated);

    await _saveAll(items);
  }

  Future<void> updateTranslated(Translated translated) async {
    final items = await getTranslated();

    final index = items.indexWhere((item) => item.id == translated.id);

    if (index == -1) {
      throw StateError(
        'Translated item with id ${translated.id} was not found.',
      );
    }

    items[index] = translated;

    await _saveAll(items);
  }

  Future<void> deleteTranslated(int id) async {
    final items = await getTranslated();

    final index = items.indexWhere((item) => item.id == id);

    if (index == -1) {
      return;
    }

    items.removeAt(index);

    await _saveAll(items);
  }

  Future<void> _saveAll(List<Translated> items) async {
    final jsonList = items.map((item) => item.toJson()).toList();

    final saved = await _preferences.setString(
      _translatedKey,
      jsonEncode(jsonList),
    );

    if (!saved) {
      throw StateError('Could not save translations.');
    }
  }

  // ---------------------------------------------------------------------------
  // Categories
  // ---------------------------------------------------------------------------

  List<String> getCategories() {
    final storedCategories = _preferences.getStringList(_categoriesKey);

    if (storedCategories == null) {
      return [];
    }

    return storedCategories
        .map((category) => category.trim())
        .where((category) => category.isNotEmpty)
        .toList();
  }

  Future<void> saveCategory(String category) async {
    final trimmedCategory = category.trim();

    if (trimmedCategory.isEmpty) {
      return;
    }

    final categories = getCategories();

    final alreadyExists = categories.any(
      (existing) => existing.toLowerCase() == trimmedCategory.toLowerCase(),
    );

    if (alreadyExists) {
      return;
    }

    final updatedCategories = <String>[...categories, trimmedCategory];

    final saved = await _preferences.setStringList(
      _categoriesKey,
      updatedCategories,
    );

    if (!saved) {
      throw StateError('Could not save category.');
    }
  }

  Future<void> deleteCategory(String category) async {
    final categories = getCategories();

    final normalized = category.trim().toLowerCase();

    final updatedCategories =
        categories
            .where((existing) => existing.trim().toLowerCase() != normalized)
            .toList();

    final saved = await _preferences.setStringList(
      _categoriesKey,
      updatedCategories,
    );

    if (!saved) {
      throw StateError('Could not delete category.');
    }
  }

  // ---------------------------------------------------------------------------
  // TTS voices
  // ---------------------------------------------------------------------------
  //
  // The application supports exactly two TTS languages:
  //
  //   fi -> Finnish
  //   en -> English
  //
  // These methods deliberately do not return voices for other languages.
  //
  // "Original" means the voice used for the source text.
  // "Translated" means the voice used for the translated text.
  //
  // Defaults:
  //
  //   original   -> Finnish
  //   translated -> English
  //
  // RecordScreen can swap which setting is used depending on the
  // source/target direction.
  // ---------------------------------------------------------------------------

  TtsVoice? _getTtsVoice(String key) {
    final value = _preferences.getString(key);

    if (value == null) {
      return null;
    }

    try {
      final json = jsonDecode(value);

      if (json is! Map) {
        return null;
      }

      return TtsVoice.fromJson(Map<String, dynamic>.from(json));
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveTtsVoice(String key, TtsVoice voice) async {
    if (!_isSupportedTtsLocale(voice.locale)) {
      throw ArgumentError('Only Finnish and English TTS voices are supported.');
    }

    final saved = await _preferences.setString(key, jsonEncode(voice.toJson()));

    if (!saved) {
      throw StateError('Could not save TTS voice.');
    }
  }

  /// Returns true when [locale] represents English or Finnish.
  ///
  /// This accepts common variants such as:
  ///
  ///   en
  ///   en-US
  ///   en-GB
  ///   fi
  ///   fi-FI
  ///
  bool _isSupportedTtsLocale(String locale) {
    final normalized = locale.trim().toLowerCase().replaceAll('_', '-');

    return normalized == 'fi' ||
        normalized.startsWith('fi-') ||
        normalized == 'en' ||
        normalized.startsWith('en-');
  }

  /// Returns true when [locale] represents Finnish.
  bool isFinnishTtsLocale(String locale) {
    final normalized = locale.trim().toLowerCase().replaceAll('_', '-');

    return normalized == 'fi' || normalized.startsWith('fi-');
  }

  /// Returns true when [locale] represents English.
  bool isEnglishTtsLocale(String locale) {
    final normalized = locale.trim().toLowerCase().replaceAll('_', '-');

    return normalized == 'en' || normalized.startsWith('en-');
  }

  /// Returns the saved original/source voice.
  ///
  /// Legacy data is supported, but only if the legacy voice is Finnish or
  /// English.
  ///
  /// If no valid saved voice exists, null is returned. The caller can then
  /// select the appropriate default voice from the available device voices.
  TtsVoice? getOriginalTtsVoice() {
    final voice = _getTtsVoice(_originalTtsVoiceKey);

    if (voice != null && _isSupportedTtsLocale(voice.locale)) {
      return voice;
    }

    // Existing installations may still have the old single TTS setting.
    final legacy = _getTtsVoice(_legacyTtsVoiceKey);

    if (legacy != null && _isSupportedTtsLocale(legacy.locale)) {
      return legacy;
    }

    return null;
  }

  Future<void> saveOriginalTtsVoice(TtsVoice voice) async {
    await _saveTtsVoice(_originalTtsVoiceKey, voice);
  }

  Future<void> clearOriginalTtsVoice() async {
    await _preferences.remove(_originalTtsVoiceKey);
  }

  /// Returns the saved translated/target voice.
  ///
  /// Only Finnish and English voices are accepted.
  TtsVoice? getTranslatedTtsVoice() {
    final voice = _getTtsVoice(_translatedTtsVoiceKey);

    if (voice != null && _isSupportedTtsLocale(voice.locale)) {
      return voice;
    }

    return null;
  }

  Future<void> saveTranslatedTtsVoice(TtsVoice voice) async {
    await _saveTtsVoice(_translatedTtsVoiceKey, voice);
  }

  Future<void> clearTranslatedTtsVoice() async {
    await _preferences.remove(_translatedTtsVoiceKey);
  }

  // ---------------------------------------------------------------------------
  // Language-specific voice helpers
  // ---------------------------------------------------------------------------

  /// Returns the configured Finnish voice.
  ///
  /// If the saved original/translated setting contains a Finnish voice,
  /// it can be used. Otherwise this returns null and the UI/service should
  /// select an available Finnish voice as the default.
  TtsVoice? getFinnishVoice() {
    final original = getOriginalTtsVoice();

    if (original != null && isFinnishTtsLocale(original.locale)) {
      return original;
    }

    final translated = getTranslatedTtsVoice();

    if (translated != null && isFinnishTtsLocale(translated.locale)) {
      return translated;
    }

    return null;
  }

  /// Returns the configured English voice.
  TtsVoice? getEnglishVoice() {
    final original = getOriginalTtsVoice();

    if (original != null && isEnglishTtsLocale(original.locale)) {
      return original;
    }

    final translated = getTranslatedTtsVoice();

    if (translated != null && isEnglishTtsLocale(translated.locale)) {
      return translated;
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // Clear
  // ---------------------------------------------------------------------------

  Future<void> clear() async {
    await _preferences.remove(_translatedKey);
    await _preferences.remove(_categoriesKey);
    await _preferences.remove(_originalTtsVoiceKey);
    await _preferences.remove(_translatedTtsVoiceKey);
    await _preferences.remove(_legacyTtsVoiceKey);
  }
}
