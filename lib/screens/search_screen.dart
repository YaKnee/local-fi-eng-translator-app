import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/translated_model.dart';
import '../models/tts_voice_model.dart';
import '../services/speech_service.dart';
import '../services/storage_service.dart';
import '../widgets/playback_mini_player.dart';
import '../widgets/recording_tile.dart';
import '../widgets/search_bar.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();

  /// Complete list of recordings.
  List<Translated> _items = [];

  /// Currently displayed/search-filtered list.
  ///
  /// Playback also operates on this list, so when a search is active,
  /// playback only moves through the search results.
  List<Translated> _filteredItems = [];

  final Set<int> _selectedIds = {};

  /// ID of the recording currently being played.
  int? _playingId;

  /// Changes whenever playback is replaced or stopped.
  ///
  /// This prevents an old async playback operation from continuing after
  /// the user has selected another recording or stopped playback.
  int _playbackGeneration = 0;

  List<String> _categories = [];
  bool _loading = true;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _loadItems();
    _loadCategories();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Loading
  // ---------------------------------------------------------------------------

  Future<void> _loadItems() async {
    final storage = context.read<StorageService>();
    final items = await storage.getTranslated();

    if (!mounted) {
      return;
    }

    final orderedItems = items.reversed.toList();

    setState(() {
      _items = orderedItems;
      _filteredItems = List<Translated>.from(orderedItems);
      _loading = false;
    });
  }

  void _loadCategories() {
    final storage = context.read<StorageService>();
    _categories = storage.getCategories();
  }

  // ---------------------------------------------------------------------------
  // Search
  // ---------------------------------------------------------------------------

  Future<void> _applySearchResults(List<Translated> results) async {
    // Searching changes the playback queue, so stop current playback first.
    if (_playingId != null) {
      await _stopPlayback();
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _filteredItems = List<Translated>.from(results);
    });
  }

  // ---------------------------------------------------------------------------
  // TTS voice selection
  // ---------------------------------------------------------------------------

  /// Normalizes a stored language/locale into the application's supported
  /// language codes.
  ///
  /// Supported values include:
  ///
  ///   fi
  ///   fi-FI
  ///   en
  ///   en-US
  ///   en-GB
  String? _languageCode(String language) {
    final normalized = language.trim().toLowerCase().replaceAll('_', '-');

    if (normalized == 'fi' || normalized.startsWith('fi-')) {
      return 'fi';
    }

    if (normalized == 'en' || normalized.startsWith('en-')) {
      return 'en';
    }

    // Also handle full language names in case older stored recordings use
    // "Finnish" / "English".
    if (normalized == 'finnish') {
      return 'fi';
    }

    if (normalized == 'english') {
      return 'en';
    }

    return null;
  }

  /// Returns the configured voice for [language].
  ///
  /// Importantly, this resolves the voice by LANGUAGE rather than by whether
  /// the text happens to be original or translated.
  ///
  /// For example:
  ///
  ///   English source + Finnish target
  ///       original    -> English voice
  ///       translation -> Finnish voice
  ///
  ///   Finnish source + English target
  ///       original    -> Finnish voice
  ///       translation -> English voice
  Future<TtsVoice?> _getVoiceForLanguage(
    String language, {
    required StorageService storage,
    required SpeechService speechService,
  }) async {
    final languageCode = _languageCode(language);

    if (languageCode == null) {
      return null;
    }

    // First use the user's explicitly configured language-specific voice.
    TtsVoice? voice;

    if (languageCode == 'fi') {
      voice = storage.getFinnishVoice();
    } else if (languageCode == 'en') {
      voice = storage.getEnglishVoice();
    }

    if (voice != null) {
      return voice;
    }

    // If the user has not configured a voice for this language, select a
    // suitable installed system voice.
    return speechService.getDefaultTtsVoice(languageCode);
  }

  // ---------------------------------------------------------------------------
  // Playback
  // ---------------------------------------------------------------------------

  Future<void> _playFromIndex(int index) async {
    if (index < 0 || index >= _filteredItems.length) {
      return;
    }

    final item = _filteredItems[index];

    final originalText = item.originalText.trim();
    final translatedText = item.translatedText.trim();

    if (originalText.isEmpty && translatedText.isEmpty) {
      return;
    }

    final storage = context.read<StorageService>();
    final speechService = context.read<SpeechService>();

    final originalVoice = await _getVoiceForLanguage(
      item.sourceLanguage,
      storage: storage,
      speechService: speechService,
    );

    final translatedVoice = await _getVoiceForLanguage(
      item.targetLanguage,
      storage: storage,
      speechService: speechService,
    );

    if (!mounted) {
      return;
    }

    // Every playback operation gets a unique generation.
    final generation = ++_playbackGeneration;

    setState(() {
      _playingId = item.id;
    });

    try {
      // ---------------------------------------------------------------------
      // Original / source language
      // ---------------------------------------------------------------------

      if (originalText.isNotEmpty) {
        await speechService.speak(originalText, voice: originalVoice);
      }

      if (!_isCurrentPlayback(generation)) {
        return;
      }

      // ---------------------------------------------------------------------
      // Pause between languages
      // ---------------------------------------------------------------------

      await Future.delayed(const Duration(milliseconds: 500));

      if (!_isCurrentPlayback(generation)) {
        return;
      }

      // ---------------------------------------------------------------------
      // Translated / target language
      // ---------------------------------------------------------------------

      if (translatedText.isNotEmpty) {
        await speechService.speak(translatedText, voice: translatedVoice);
      }

      if (!_isCurrentPlayback(generation)) {
        return;
      }

      // ---------------------------------------------------------------------
      // Automatically continue with the next recording.
      // ---------------------------------------------------------------------

      final nextIndex = index + 1;

      if (nextIndex < _filteredItems.length) {
        await Future.delayed(const Duration(milliseconds: 700));

        if (!_isCurrentPlayback(generation)) {
          return;
        }

        // Start the next item as a new playback generation.
        await _playFromIndex(nextIndex);
      }
    } catch (error) {
      // Ignore errors from playback operations that have already been
      // replaced or stopped.
      if (!_isCurrentPlayback(generation)) {
        return;
      }

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not play recording: $error'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (!mounted) {
        return;
      }

      // Only the currently active generation may clear the player.
      if (_playbackGeneration == generation) {
        setState(() {
          _playingId = null;
        });
      }
    }
  }

  bool _isCurrentPlayback(int generation) {
    return mounted && generation == _playbackGeneration;
  }

  Future<void> _stopPlayback() async {
    // Invalidate the current playback immediately.
    //
    // This prevents an existing async playback operation from continuing
    // to the next language or recording while stopSpeaking() completes.
    _playbackGeneration++;

    final speechService = context.read<SpeechService>();

    await speechService.stopSpeaking();

    if (!mounted) {
      return;
    }

    setState(() {
      _playingId = null;
    });
  }

  Future<void> _playItem(int index) async {
    if (index < 0 || index >= _filteredItems.length) {
      return;
    }

    final item = _filteredItems[index];

    // Tapping the currently playing item stops playback.
    if (_playingId == item.id) {
      await _stopPlayback();
      return;
    }

    // Stop anything currently playing before starting a new item.
    if (_playingId != null) {
      await _stopPlayback();
    }

    if (!mounted) {
      return;
    }

    await _playFromIndex(index);
  }

  Future<void> _playPrevious() async {
    if (_playingId == null) {
      return;
    }

    final currentIndex = _filteredItems.indexWhere(
      (item) => item.id == _playingId,
    );

    if (currentIndex <= 0) {
      return;
    }

    await _playItem(currentIndex - 1);
  }

  Future<void> _playNext() async {
    if (_playingId == null) {
      return;
    }

    final currentIndex = _filteredItems.indexWhere(
      (item) => item.id == _playingId,
    );

    if (currentIndex == -1) {
      return;
    }

    if (currentIndex >= _filteredItems.length - 1) {
      return;
    }

    await _playItem(currentIndex + 1);
  }

  // ---------------------------------------------------------------------------
  // Selection
  // ---------------------------------------------------------------------------

  void _setSelected(Translated item, bool selected) {
    setState(() {
      if (selected) {
        _selectedIds.add(item.id);
      } else {
        _selectedIds.remove(item.id);
      }
    });
  }

  void _clearSelection() {
    if (_selectedIds.isEmpty) {
      return;
    }

    setState(() {
      _selectedIds.clear();
    });
  }

  void _toggleSelectAll() {
    if (_filteredItems.isEmpty) {
      return;
    }

    final allSelected = _filteredItems.every(
      (item) => _selectedIds.contains(item.id),
    );

    setState(() {
      if (allSelected) {
        for (final item in _filteredItems) {
          _selectedIds.remove(item.id);
        }
      } else {
        for (final item in _filteredItems) {
          _selectedIds.add(item.id);
        }
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Delete
  // ---------------------------------------------------------------------------

  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete recordings?'),
          content: Text(
            'Delete ${_selectedIds.length} selected recording'
            '${_selectedIds.length == 1 ? '' : 's'}?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop(true);
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    final storage = context.read<StorageService>();
    final ids = Set<int>.from(_selectedIds);

    // Stop playback before deleting anything.
    if (_playingId != null) {
      await _stopPlayback();
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _deleting = true;
    });

    try {
      for (final id in ids) {
        await storage.deleteTranslated(id);
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _items.removeWhere((item) => ids.contains(item.id));
        _filteredItems.removeWhere((item) => ids.contains(item.id));
        _selectedIds.clear();
        _deleting = false;
      });

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Deleted ${ids.length} recording'
              '${ids.length == 1 ? '' : 's'}.',
            ),
            backgroundColor: Colors.green,
          ),
        );
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _deleting = false;
      });

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Could not delete recordings: $error'),
            backgroundColor: Colors.red,
          ),
        );
    }
  }

  // ---------------------------------------------------------------------------
  // Mini player
  // ---------------------------------------------------------------------------

  Widget _buildPlaybackMiniPlayer() {
    final playingIndex = _filteredItems.indexWhere(
      (item) => item.id == _playingId,
    );

    if (playingIndex == -1) {
      return const SizedBox.shrink();
    }

    final item = _filteredItems[playingIndex];

    return PlaybackMiniPlayer(
      item: item,
      currentIndex: playingIndex + 1,
      totalItems: _filteredItems.length,
      onStop: _stopPlayback,
      onPrevious: _playPrevious,
      onNext: _playNext,
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final hasSelection = _selectedIds.isNotEmpty;

    final allVisibleItemsSelected =
        _filteredItems.isNotEmpty &&
        _filteredItems.every((item) => _selectedIds.contains(item.id));

    return Scaffold(
      body:
          _loading || _deleting
              ? const Center(child: CircularProgressIndicator())
              : Column(
                children: [
                  // Search and filters.
                  SearchAndFilterBar(
                    controller: _searchController,
                    items: _items,
                    categories: _categories,
                    onResults: _applySearchResults,
                  ),

                  // Selection actions.
                  if (hasSelection)
                    Material(
                      color: Theme.of(context).colorScheme.surfaceContainer,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                        child: Row(
                          children: [
                            Text(
                              '${_selectedIds.length} selected',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const Spacer(),
                            TextButton.icon(
                              onPressed: _deleting ? null : _toggleSelectAll,
                              icon: Icon(
                                allVisibleItemsSelected
                                    ? Icons.fullscreen_exit
                                    : Icons.fullscreen,
                              ),
                              label: const Text('All'),
                            ),
                            TextButton.icon(
                              onPressed: _deleting ? null : _clearSelection,
                              icon: const Icon(Icons.clear_rounded),
                              label: const Text('Clear'),
                            ),
                            TextButton.icon(
                              onPressed: _deleting ? null : _deleteSelected,
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Delete'),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Results.
                  Expanded(
                    child:
                        _filteredItems.isEmpty
                            ? const Center(
                              child: Text('No matching recordings.'),
                            )
                            : ListView.builder(
                              itemCount: _filteredItems.length,
                              padding: const EdgeInsets.only(bottom: 8),
                              itemBuilder: (context, index) {
                                final item = _filteredItems[index];

                                return RecordingTile(
                                  obj: item,
                                  isSelected: _selectedIds.contains(item.id),
                                  isPlaying: _playingId == item.id,
                                  onSelectionChanged: (selected) {
                                    _setSelected(item, selected);
                                  },
                                  onPlay: () {
                                    _playItem(index);
                                  },
                                );
                              },
                            ),
                  ),
                ],
              ),

      // Persistent player at the bottom of the screen.
      bottomNavigationBar:
          _playingId == null ? null : _buildPlaybackMiniPlayer(),
    );
  }
}
