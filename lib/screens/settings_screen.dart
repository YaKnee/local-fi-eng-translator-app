import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/tts_voice_model.dart';
import '../services/speech_service.dart';
import '../services/storage_service.dart';
import '../widgets/voice_selector_dialog.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  List<TtsVoice> _voices = [];

  TtsVoice? _finnishVoice;
  TtsVoice? _englishVoice;

  List<String> _categories = [];

  bool _loading = true;

  bool _textToSpeechExpanded = false;
  bool _categoriesExpanded = false;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  // ---------------------------------------------------------------------------
  // Loading
  // ---------------------------------------------------------------------------

  Future<void> _loadSettings() async {
    final speechService = context.read<SpeechService>();
    final storage = context.read<StorageService>();

    try {
      final allVoices = await speechService.getTtsVoices();

      // Only expose English and Finnish voices.
      final voices = allVoices
          .where(_isSupportedLanguage)
          .toList();

      // -----------------------------------------------------------------------
      // Compatibility with the existing StorageService API.
      //
      // Existing "original" voice is treated as the Finnish voice.
      // Existing "translated" voice is treated as the English voice.
      //
      // This means changing translation direction does not change which
      // physical voice belongs to Finnish or English.
      // -----------------------------------------------------------------------

      final savedFinnishVoice =
          storage.getOriginalTtsVoice();

      final savedEnglishVoice =
          storage.getTranslatedTtsVoice();

      final finnishVoice =
          _findMatchingVoice(
        voices,
        savedFinnishVoice,
      ) ??
          _findPreferredVoice(
            voices,
            languageCode: 'fi',
          );

      final englishVoice =
          _findMatchingVoice(
        voices,
        savedEnglishVoice,
      ) ??
          _findPreferredVoice(
            voices,
            languageCode: 'en',
          );

      final categories =
          storage.getCategories();

      if (!mounted) {
        return;
      }

      setState(() {
        _voices = voices;
        _finnishVoice = finnishVoice;
        _englishVoice = englishVoice;
        _categories =
            List<String>.from(categories);
        _loading = false;
      });

      // Persist defaults when no valid saved voice exists.
      //
      // This makes the default deterministic instead of relying on the
      // platform TTS engine to choose something different later.
      if (savedFinnishVoice == null &&
          finnishVoice != null) {
        await storage.saveOriginalTtsVoice(
          finnishVoice,
        );
      }

      if (savedEnglishVoice == null &&
          englishVoice != null) {
        await storage.saveTranslatedTtsVoice(
          englishVoice,
        );
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _categories =
            List<String>.from(
          storage.getCategories(),
        );
        _loading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not load TTS voices: $error',
          ),
          backgroundColor: Colors.red,
        ),
      );

      debugPrint(
        'Could not load TTS voices: $error',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Voice filtering
  // ---------------------------------------------------------------------------

  bool _isSupportedLanguage(TtsVoice voice) {
    final language =
        _languageCodeFromLocale(
      voice.locale,
    );

    return language == 'fi' ||
        language == 'en';
  }

  String _languageCodeFromLocale(
    String locale,
  ) {
    final normalized =
        locale.trim().toLowerCase();

    if (normalized.isEmpty) {
      return '';
    }

    // Handles:
    //
    // fi-FI
    // fi_FI
    // en-US
    // en_US
    //
    final separatorIndex =
        normalized.indexOf('-');

    final underscoreIndex =
        normalized.indexOf('_');

    var index = separatorIndex;

    if (index == -1 ||
        (underscoreIndex != -1 &&
            underscoreIndex < index)) {
      index = underscoreIndex;
    }

    if (index == -1) {
      return normalized;
    }

    return normalized.substring(
      0,
      index,
    );
  }

  // ---------------------------------------------------------------------------
  // Voice matching / defaults
  // ---------------------------------------------------------------------------

  TtsVoice? _findMatchingVoice(
    List<TtsVoice> voices,
    TtsVoice? savedVoice,
  ) {
    if (savedVoice == null) {
      return null;
    }

    // First try the complete model equality.
    for (final voice in voices) {
      if (voice == savedVoice) {
        return voice;
      }
    }

    // Then name + locale.
    for (final voice in voices) {
      if (voice.name == savedVoice.name &&
          voice.locale == savedVoice.locale) {
        return voice;
      }
    }

    // Finally match by language. This is useful when Android's voice
    // identifier changes after a TTS engine update.
    final savedLanguage =
        _languageCodeFromLocale(
      savedVoice.locale,
    );

    if (savedLanguage.isNotEmpty) {
      for (final voice in voices) {
        if (_languageCodeFromLocale(
              voice.locale,
            ) ==
            savedLanguage) {
          return voice;
        }
      }
    }

    return null;
  }

  TtsVoice? _findPreferredVoice(
    List<TtsVoice> voices, {
    required String languageCode,
  }) {
    final languageVoices =
        voices.where(
      (voice) =>
          _languageCodeFromLocale(
            voice.locale,
          ) ==
          languageCode,
    );

    if (languageVoices.isEmpty) {
      return null;
    }

    final candidates =
        languageVoices.toList();

    // Prefer the common Finnish locale.
    if (languageCode == 'fi') {
      final fiFi = candidates.where(
        (voice) =>
            voice.locale.toLowerCase() ==
            'fi-fi',
      );

      if (fiFi.isNotEmpty) {
        return fiFi.first;
      }
    }

    // Prefer US English when available.
    if (languageCode == 'en') {
      final enUs = candidates.where(
        (voice) =>
            voice.locale.toLowerCase() ==
            'en-us',
      );

      if (enUs.isNotEmpty) {
        return enUs.first;
      }

      // Otherwise prefer British English.
      final enGb = candidates.where(
        (voice) =>
            voice.locale.toLowerCase() ==
            'en-gb',
      );

      if (enGb.isNotEmpty) {
        return enGb.first;
      }
    }

    return candidates.first;
  }

  // ---------------------------------------------------------------------------
  // Finnish voice
  // ---------------------------------------------------------------------------

  Future<void> _showFinnishVoiceSelector() async {
    final selected =
        await _showVoiceSelector(
      selectedVoice: _finnishVoice,
      languageCode: 'fi',
    );

    if (selected == null) {
      return;
    }

    await _saveFinnishVoice(selected);
  }

  Future<void> _saveFinnishVoice(
    TtsVoice voice,
  ) async {
    final storage =
        context.read<StorageService>();

    try {
      // Compatibility with the current StorageService.
      await storage.saveOriginalTtsVoice(
        voice,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _finnishVoice = voice;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Finnish voice changed to '
            '${voice.displayName}',
          ),
          backgroundColor: Colors.blue,
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not save Finnish voice: $error',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // English voice
  // ---------------------------------------------------------------------------

  Future<void> _showEnglishVoiceSelector() async {
    final selected =
        await _showVoiceSelector(
      selectedVoice: _englishVoice,
      languageCode: 'en',
    );

    if (selected == null) {
      return;
    }

    await _saveEnglishVoice(selected);
  }

  Future<void> _saveEnglishVoice(
    TtsVoice voice,
  ) async {
    final storage =
        context.read<StorageService>();

    try {
      // Compatibility with the current StorageService.
      await storage.saveTranslatedTtsVoice(
        voice,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _englishVoice = voice;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'English voice changed to '
            '${voice.displayName}',
          ),
          backgroundColor: Colors.blue,
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not save English voice: $error',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Voice selector
  // ---------------------------------------------------------------------------

  Future<TtsVoice?> _showVoiceSelector({
    required TtsVoice? selectedVoice,
    required String languageCode,
  }) async {
    if (_loading) {
      return null;
    }

    final languageVoices =
        _voices.where(
      (voice) =>
          _languageCodeFromLocale(
            voice.locale,
          ) ==
          languageCode,
    ).toList();

    if (languageVoices.isEmpty) {
      if (!mounted) {
        return null;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No ${languageCode == 'fi' ? 'Finnish' : 'English'} '
            'TTS voices are available.',
          ),
          backgroundColor: Colors.amber,
        ),
      );

      return null;
    }

    final matchingSelected =
        _findMatchingVoice(
      languageVoices,
      selectedVoice,
    );

    return showDialog<TtsVoice>(
      context: context,
      builder: (_) {
        return VoiceSelectorDialog(
          voices: languageVoices,
          selectedVoice: matchingSelected,
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Categories
  // ---------------------------------------------------------------------------

  Future<void> _addCategory() async {
    final category =
        await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return const _AddCategoryDialog();
      },
    );

    if (!mounted || category == null) {
      return;
    }

    final trimmedCategory =
        category.trim();

    if (trimmedCategory.isEmpty) {
      return;
    }

    final storage =
        context.read<StorageService>();

    final categories =
        storage.getCategories();

    final existingCategory =
        categories.where(
      (existing) =>
          existing.toLowerCase() ==
          trimmedCategory.toLowerCase(),
    );

    if (existingCategory.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Category "${existingCategory.first}" '
            'already exists.',
          ),
        ),
      );

      return;
    }

    try {
      await storage.saveCategory(
        trimmedCategory,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _categories =
            List<String>.from(
          storage.getCategories(),
        );
        _categoriesExpanded = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Category "$trimmedCategory" added.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not add category: $error',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _deleteCategory(
    String category,
  ) async {
    final confirmed =
        await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            'Delete category?',
          ),
          content: Text(
            'Delete "$category" from your categories?\n\n'
            'Existing recordings will not be deleted.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(
                  dialogContext,
                ).pop(false);
              },
              child: const Text(
                'Cancel',
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor:
                    Theme.of(context)
                        .colorScheme
                        .error,
                foregroundColor:
                    Theme.of(context)
                        .colorScheme
                        .onError,
              ),
              onPressed: () {
                Navigator.of(
                  dialogContext,
                ).pop(true);
              },
              child: const Text(
                'Delete',
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    final storage =
        context.read<StorageService>();

    try {
      await storage.deleteCategory(
        category,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _categories =
            List<String>.from(
          storage.getCategories(),
        );
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Category "$category" deleted.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not delete category: $error',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        children: [
          // =====================================================================
          // Text-to-speech
          // =====================================================================

          ExpansionTile(
            initiallyExpanded:
                _textToSpeechExpanded,
            onExpansionChanged:
                (expanded) {
              setState(() {
                _textToSpeechExpanded =
                    expanded;
              });
            },
            leading: const Icon(
              Icons.record_voice_over,
            ),
            title: const Text(
              'Text-to-speech',
            ),
            subtitle: Text(
              _loading
                  ? 'Loading available voices...'
                  : 'Finnish and English voices',
            ),
            children: [
              // -----------------------------------------------------------------
              // Finnish
              // -----------------------------------------------------------------

              ListTile(
                contentPadding:
                    const EdgeInsets.only(
                  left: 72,
                  right: 16,
                ),
                leading: const Icon(
                  Icons.record_voice_over,
                ),
                title: const Text(
                  'Finnish voice',
                ),
                subtitle: Text(
                  _loading
                      ? 'Loading...'
                      : (_finnishVoice
                              ?.displayName ??
                          'Device default'),
                ),
                trailing: const Icon(
                  Icons.chevron_right,
                ),
                onTap: _loading
                    ? null
                    : _showFinnishVoiceSelector,
              ),

              // -----------------------------------------------------------------
              // English
              // -----------------------------------------------------------------

              ListTile(
                contentPadding:
                    const EdgeInsets.only(
                  left: 72,
                  right: 16,
                ),
                leading: const Icon(
                  Icons.translate,
                ),
                title: const Text(
                  'English voice',
                ),
                subtitle: Text(
                  _loading
                      ? 'Loading...'
                      : (_englishVoice
                              ?.displayName ??
                          'Device default'),
                ),
                trailing: const Icon(
                  Icons.chevron_right,
                ),
                onTap: _loading
                    ? null
                    : _showEnglishVoiceSelector,
              ),
            ],
          ),

          const Divider(height: 1),

          // =====================================================================
          // Categories
          // =====================================================================

          ExpansionTile(
            initiallyExpanded:
                _categoriesExpanded,
            onExpansionChanged:
                (expanded) {
              setState(() {
                _categoriesExpanded =
                    expanded;
              });
            },
            leading: const Icon(
              Icons.category_outlined,
            ),
            title: const Text(
              'Categories',
            ),
            subtitle: Text(
              _categories.isEmpty
                  ? 'No categories'
                  : '${_categories.length} '
                      '${_categories.length == 1 ? 'category' : 'categories'}',
            ),
            children: [
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(
                  16,
                  0,
                  16,
                  8,
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed:
                        _addCategory,
                    icon: const Icon(
                      Icons.add,
                    ),
                    label: const Text(
                      'Add category',
                    ),
                  ),
                ),
              ),
              if (_categories.isEmpty)
                const Padding(
                  padding:
                      EdgeInsets.fromLTRB(
                    16,
                    8,
                    16,
                    20,
                  ),
                  child: Text(
                    'No categories yet.',
                    textAlign:
                        TextAlign.center,
                  ),
                )
              else
                ..._categories.map(
                  (category) {
                    return ListTile(
                      contentPadding:
                          const EdgeInsets.only(
                        left: 32,
                        right: 8,
                      ),
                      leading: const Icon(
                        Icons.folder_outlined,
                      ),
                      title: Text(
                        category,
                        overflow:
                            TextOverflow.ellipsis,
                      ),
                      trailing:
                          IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                        ),
                        tooltip:
                            'Delete category',
                        onPressed: () {
                          _deleteCategory(
                            category,
                          );
                        },
                      ),
                    );
                  },
                ),
              if (_categories.isNotEmpty)
                const SizedBox(
                  height: 8,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Add category dialog
// =============================================================================

class _AddCategoryDialog
    extends StatefulWidget {
  const _AddCategoryDialog();

  @override
  State<_AddCategoryDialog> createState() =>
      _AddCategoryDialogState();
}

class _AddCategoryDialogState
    extends State<_AddCategoryDialog> {
  late final TextEditingController
      _controller;

  @override
  void initState() {
    super.initState();

    _controller =
        TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final trimmed =
        _controller.text.trim();

    if (trimmed.isEmpty) {
      return;
    }

    Navigator.of(context).pop(
      trimmed,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        'Add category',
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization:
            TextCapitalization.sentences,
        textInputAction:
            TextInputAction.done,
        decoration:
            const InputDecoration(
          labelText: 'Category',
          hintText: 'e.g. Travel',
          border:
              OutlineInputBorder(),
        ),
        onSubmitted: (_) {
          _submit();
        },
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text(
            'Cancel',
          ),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text(
            'Add',
          ),
        ),
      ],
    );
  }
}