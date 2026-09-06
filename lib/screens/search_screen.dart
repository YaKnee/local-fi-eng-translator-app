import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/translated_model.dart';
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
  /// Playback also operates on this list, so when a search is
  /// active, playback only moves through the search results.
  List<Translated> _filteredItems = [];

  final Set<int> _selectedIds = {};

  /// ID of the recording currently being played.
  int? _playingId;

  /// Incremented every time playback is replaced/stopped.
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
    // Searching changes the playback queue, so stop the current
    // playback before replacing the displayed list.
    if (_playingId != null) {
      await _stopPlayback();
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _filteredItems = results;
    });
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

    final originalVoice = storage.getOriginalTtsVoice();
    final translatedVoice = storage.getTranslatedTtsVoice();

    // Every playback operation gets a unique generation.
    final generation = ++_playbackGeneration;

    if (!mounted) {
      return;
    }

    setState(() {
      _playingId = item.id;
    });

    try {
      // ---------------------------------------------------------------------
      // Original language
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
      // Translated language
      // ---------------------------------------------------------------------

      if (translatedText.isNotEmpty) {
        await speechService.speak(translatedText, voice: translatedVoice);
      }

      if (!_isCurrentPlayback(generation)) {
        return;
      }

      // ---------------------------------------------------------------------
      // Current item finished -> automatically play next item.
      // ---------------------------------------------------------------------

      final nextIndex = index + 1;

      if (nextIndex < _filteredItems.length) {
        await Future.delayed(const Duration(milliseconds: 700));
        await _playFromIndex(nextIndex);
      }
    } catch (error) {
      // If this playback has already been replaced/stopped,
      // don't show an error from the old playback operation.
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

      // Only clear the player if this is still the active
      // playback generation.
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
    // This prevents the existing async playback operation from
    // continuing to the next item while stopSpeaking() completes.
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

    // Stop anything currently playing before starting
    // the newly selected item.
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

  /// Clears all selected items.
  void _clearSelection() {
    if (_selectedIds.isEmpty) {
      return;
    }

    setState(() {
      _selectedIds.clear();
    });
  }

  /// Selects all currently visible items, or deselects all currently
  /// visible items if they are already all selected.
  void _toggleSelectAll() {
    if (_filteredItems.isEmpty) {
      return;
    }

    final allSelected = _filteredItems.every(
      (item) => _selectedIds.contains(item.id),
    );

    setState(() {
      if (allSelected) {
        // Deselect all currently visible items.
        for (final item in _filteredItems) {
          _selectedIds.remove(item.id);
        }
      } else {
        // Select all currently visible items.
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
                  // -----------------------------------------------------------
                  // Search and filters
                  // -----------------------------------------------------------
                  SearchAndFilterBar(
                    controller: _searchController,
                    items: _items,
                    categories: _categories,
                    onResults: _applySearchResults,
                  ),

                  // -----------------------------------------------------------
                  // Selection actions
                  // -----------------------------------------------------------
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
                              label: Text('All'),
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

                  // -----------------------------------------------------------
                  // Results
                  // -----------------------------------------------------------
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
