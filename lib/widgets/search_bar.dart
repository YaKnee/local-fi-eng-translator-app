import 'package:flutter/material.dart';

import '../models/translated_model.dart';

class SearchAndFilterBar extends StatefulWidget {
  final TextEditingController controller;
  final List<Translated> items;
  final List<String> categories;

  final ValueChanged<List<Translated>> onResults;

  const SearchAndFilterBar({
    super.key,
    required this.controller,
    required this.items,
    required this.categories,
    required this.onResults,
  });

  @override
  State<SearchAndFilterBar> createState() => _SearchAndFilterBarState();
}

class _SearchAndFilterBarState extends State<SearchAndFilterBar> {
  String? _selectedCategory;

  bool get _hasSearchText {
    return widget.controller.text.trim().isNotEmpty;
  }

  bool get _hasFilters {
    return _hasSearchText || _selectedCategory != null;
  }

  @override
  void initState() {
    super.initState();

    widget.controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(covariant SearchAndFilterBar oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTextChanged);
      widget.controller.addListener(_onTextChanged);
    }

    // If the available categories changed and the selected category
    // no longer exists, clear the selection.
    if (_selectedCategory != null &&
        !widget.categories.contains(_selectedCategory)) {
      _selectedCategory = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _triggerSearch();
        }
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _triggerSearch() {
    final query = widget.controller.text.trim().toLowerCase();

    final results =
        widget.items.where((item) {
          // ---------------------------------------------------------------
          // Text filtering
          // ---------------------------------------------------------------

          final matchesQuery =
              query.isEmpty ||
              item.originalText.toLowerCase().contains(query) ||
              item.translatedText.toLowerCase().contains(query);

          if (!matchesQuery) {
            return false;
          }

          // ---------------------------------------------------------------
          // Category filtering
          // ---------------------------------------------------------------

          if (_selectedCategory == null) {
            return true;
          }

          return item.category == _selectedCategory;
        }).toList();

    widget.onResults(results);
  }

  void _clearSearchText() {
    widget.controller.clear();

    // If there is still a category filter, keep it active.
    _triggerSearch();
  }

  void _clearAll() {
    widget.controller.clear();

    setState(() {
      _selectedCategory = null;
    });

    widget.onResults(List<Translated>.from(widget.items));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // -----------------------------------------------------------------
          // Search
          // -----------------------------------------------------------------
          TextField(
            controller: widget.controller,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _triggerSearch(),
            decoration: InputDecoration(
              hintText: 'Search phrases',
              prefixIcon: const Icon(Icons.search),
              suffixIcon:
                  _hasSearchText
                      ? IconButton(
                        onPressed: _clearSearchText,
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.clear),
                      )
                      : null,
              border: const OutlineInputBorder(),
              isDense: false,
            ),
          ),

          const SizedBox(height: 10),

          // -----------------------------------------------------------------
          // Category + actions
          // -----------------------------------------------------------------
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // -------------------------------------------------------------
              // Category selector
              // -------------------------------------------------------------
              Expanded(
                child:
                    widget.categories.isEmpty
                        ? InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Category',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.category_outlined),
                            isDense: true,
                          ),
                          child: Text(
                            'No categories',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.disabledColor,
                            ),
                          ),
                        )
                        : DropdownButtonFormField<String>(
                          value: _selectedCategory,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Category',
                            hintText: 'All categories',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.category_outlined),
                            isDense: true,
                          ),
                          items: [
                            const DropdownMenuItem<String>(
                              value: null,
                              child: Text('All categories'),
                            ),
                            ...widget.categories.map((category) {
                              return DropdownMenuItem<String>(
                                value: category,
                                child: Text(
                                  category,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _selectedCategory = value;
                            });

                            // Category selection is immediately applied.
                            _triggerSearch();
                          },
                        ),
              ),

              const SizedBox(width: 8),

              // -------------------------------------------------------------
              // Search button
              // -------------------------------------------------------------
              FilledButton(
                onPressed: _triggerSearch,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(52, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: const Icon(Icons.search),
              ),

              const SizedBox(width: 4),

              // -------------------------------------------------------------
              // Clear button
              // -------------------------------------------------------------
              IconButton(
                onPressed: _hasFilters ? _clearAll : null,
                tooltip: 'Clear filters',
                icon: const Icon(Icons.clear_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
