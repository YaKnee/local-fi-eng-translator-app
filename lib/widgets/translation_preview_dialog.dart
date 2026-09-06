import 'package:flutter/material.dart';

class TranslationPreviewDialog extends StatelessWidget {
  final String sourceLanguage;
  final String targetLanguage;
  final String originalText;
  final String translatedText;
  final String? category;

  const TranslationPreviewDialog({
    super.key,
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.originalText,
    required this.translatedText,
    required this.category,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Review translation'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$sourceLanguage → $targetLanguage',
                style: theme.textTheme.titleMedium,
              ),

              const SizedBox(height: 20),

              Text(sourceLanguage, style: theme.textTheme.titleSmall),

              const SizedBox(height: 8),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: theme.colorScheme.outline),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  originalText,
                  style: theme.textTheme.bodyLarge,
                ),
              ),

              const SizedBox(height: 20),

              Row(
                children: [
                  Icon(
                    Icons.translate,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(targetLanguage, style: theme.textTheme.titleSmall),
                ],
              ),

              const SizedBox(height: 8),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(
                    alpha: 0.35,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  translatedText,
                  style: theme.textTheme.bodyLarge,
                ),
              ),

              if (category != null) ...[
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Icon(Icons.category_outlined, size: 20),
                    const SizedBox(width: 8),
                    Text(category!, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(false);
          },
          child: const Text('Discard'),
        ),
        FilledButton.icon(
          onPressed: () {
            Navigator.of(context).pop(true);
          },
          icon: const Icon(Icons.save_outlined),
          label: const Text('Save'),
        ),
      ],
    );
  }
}
