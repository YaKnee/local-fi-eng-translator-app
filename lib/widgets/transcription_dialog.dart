import 'package:flutter/material.dart';

class TranscriptionDialogResult {
  final String text;
  final String? category;

  const TranscriptionDialogResult({
    required this.text,
    required this.category,
  });
}

class TranscriptionDialog extends StatefulWidget {
  final String initialText;
  final List<String> categories;

  const TranscriptionDialog({
    super.key,
    required this.initialText,
    required this.categories,
  });

  @override
  State<TranscriptionDialog> createState() => _TranscriptionDialogState();
}

class _TranscriptionDialogState extends State<TranscriptionDialog> {
  late final TextEditingController _textController;
  late final TextEditingController _categoryController;

  late final List<String> _categories;

  String? _selectedCategory;

  @override
  void initState() {
    super.initState();

    _textController = TextEditingController(
      text: widget.initialText,
    );

    _categoryController = TextEditingController();

    _categories = List<String>.from(widget.categories);

    _categoryController.addListener(_onCategoryTextChanged);
  }

  @override
  void dispose() {
    _categoryController.removeListener(_onCategoryTextChanged);

    _textController.dispose();
    _categoryController.dispose();

    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Category
  // ---------------------------------------------------------------------------

  void _onCategoryTextChanged() {
    final text = _categoryController.text.trim();

    String? matchingCategory;

    if (text.isNotEmpty) {
      for (final category in _categories) {
        if (category.toLowerCase() == text.toLowerCase()) {
          matchingCategory = category;
          break;
        }
      }
    }

    if (_selectedCategory == matchingCategory) {
      return;
    }

    setState(() {
      _selectedCategory = matchingCategory;
    });
  }

  void _selectCategory(String category) {
    _categoryController.text = category;

    setState(() {
      _selectedCategory = category;
    });
  }

  String? _getCategoryForResult() {
    final typedCategory = _categoryController.text.trim();

    if (typedCategory.isEmpty) {
      return null;
    }

    // Use the existing stored spelling/capitalization if the typed
    // category matches an existing category.
    for (final category in _categories) {
      if (category.toLowerCase() == typedCategory.toLowerCase()) {
        return category;
      }
    }

    // This is a new category. RecordScreen will persist it.
    return typedCategory;
  }

  // ---------------------------------------------------------------------------
  // Continue
  // ---------------------------------------------------------------------------

  void _continue() {
    final text = _textController.text.trim();

    if (text.isEmpty) {
      return;
    }

    Navigator.of(context).pop(
      TranscriptionDialogResult(
        text: text,
        category: _getCategoryForResult(),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final canContinue = _textController.text.trim().isNotEmpty;

    return AlertDialog(
      title: const Text('Review recording'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Transcription',
                style: theme.textTheme.titleSmall,
              ),

              const SizedBox(height: 8),

              TextField(
                controller: _textController,
                autofocus: true,
                minLines: 4,
                maxLines: 8,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Edit the transcription if needed',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                onChanged: (_) {
                  setState(() {});
                },
              ),

              const SizedBox(height: 20),

              Text(
                'Category',
                style: theme.textTheme.titleSmall,
              ),

              const SizedBox(height: 8),

              Autocomplete<String>(
                optionsBuilder: (TextEditingValue value) {
                  final query = value.text.trim().toLowerCase();

                  if (query.isEmpty) {
                    return _categories;
                  }

                  return _categories.where(
                    (category) =>
                        category.toLowerCase().contains(query),
                  );
                },
                displayStringForOption: (category) => category,
                onSelected: _selectCategory,
                fieldViewBuilder: (
                  context,
                  autocompleteController,
                  focusNode,
                  onFieldSubmitted,
                ) {
                  // Keep the Autocomplete controller and our result controller
                  // pointing at the same current value.
                  if (autocompleteController.text !=
                      _categoryController.text) {
                    autocompleteController.value =
                        _categoryController.value;
                  }

                  return TextField(
                    controller: autocompleteController,
                    focusNode: focusNode,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.category_outlined),
                      hintText: 'Select or type a category',
                    ),
                    onChanged: (value) {
                      _categoryController.value =
                          autocompleteController.value;

                      final trimmed = value.trim();

                      String? matchingCategory;

                      for (final category in _categories) {
                        if (category.toLowerCase() ==
                            trimmed.toLowerCase()) {
                          matchingCategory = category;
                          break;
                        }
                      }

                      if (_selectedCategory != matchingCategory) {
                        setState(() {
                          _selectedCategory = matchingCategory;
                        });
                      }
                    },
                    onSubmitted: (_) {
                      onFieldSubmitted();
                    },
                  );
                },
                optionsViewBuilder: (
                  context,
                  onSelected,
                  options,
                ) {
                  return Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(8),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: 500,
                          maxHeight: 220,
                        ),
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(
                            vertical: 8,
                          ),
                          shrinkWrap: true,
                          itemCount: options.length,
                          itemBuilder: (context, index) {
                            final category = options.elementAt(index);

                            return ListTile(
                              leading: const Icon(
                                Icons.folder_outlined,
                              ),
                              title: Text(category),
                              onTap: () {
                                onSelected(category);
                              },
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 6),

              Builder(
                builder: (context) {
                  final categoryText =
                      _categoryController.text.trim();

                  if (categoryText.isEmpty) {
                    return Text(
                      'Optional. Type a new category or choose an existing one.',
                      style: theme.textTheme.bodySmall,
                    );
                  }

                  if (_selectedCategory == null) {
                    return Text(
                      'New category will be created when you continue.',
                      style: theme.textTheme.bodySmall,
                    );
                  }

                  return Text(
                    'Existing category selected.',
                    style: theme.textTheme.bodySmall,
                  );
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text('Discard'),
        ),
        FilledButton.icon(
          onPressed: canContinue ? _continue : null,
          icon: const Icon(Icons.arrow_forward),
          label: const Text('Continue'),
        ),
      ],
    );
  }
}
