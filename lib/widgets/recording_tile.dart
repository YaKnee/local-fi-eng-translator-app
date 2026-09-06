import 'package:flutter/material.dart';

import '../models/translated_model.dart';

class RecordingTile extends StatelessWidget {
  final Translated obj;
  final bool isSelected;
  final bool isPlaying;
  final ValueChanged<bool> onSelectionChanged;
  final VoidCallback onPlay;

  const RecordingTile({
    super.key,
    required this.obj,
    required this.isSelected,
    required this.isPlaying,
    required this.onSelectionChanged,
    required this.onPlay,
  });

  Future<void> _showDetails(BuildContext context) async {
    final theme = Theme.of(context);

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Translation details'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DetailSection(
                  label: 'Original',
                  value: obj.originalText,
                  theme: theme,
                ),
                const SizedBox(height: 20),
                _DetailSection(
                  label: 'Translation',
                  value: obj.translatedText,
                  theme: theme,
                ),
                const SizedBox(height: 20),
                _DetailRow(
                  label: 'Language',
                  value:
                      '${_languageName(obj.sourceLanguage)} → '
                      '${_languageName(obj.targetLanguage)}',
                  theme: theme,
                ),
                if (obj.category != null &&
                    obj.category!.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _DetailRow(
                    label: 'Category',
                    value: obj.category!.trim(),
                    theme: theme,
                  ),
                ],
                const SizedBox(height: 12),
                _DetailRow(
                  label: 'Created',
                  value: _formatDateTime(obj.createdAt),
                  theme: theme,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  static String _languageName(String language) {
    final normalized = language.trim().toLowerCase().replaceAll('_', '-');

    if (normalized == 'fi' || normalized.startsWith('fi-')) {
      return 'Finnish';
    }

    if (normalized == 'en' || normalized.startsWith('en-')) {
      return 'English';
    }

    return language;
  }

  static String _formatDateTime(DateTime dateTime) {
    final local = dateTime.toLocal();

    String twoDigits(int value) => value.toString().padLeft(2, '0');

    return '${local.day}.${local.month}.${local.year} '
        '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      color:
          isSelected
              ? Colors.lightBlueAccent
              : isPlaying
              ? Colors.greenAccent
              : theme.cardColor,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        onLongPress: () => _showDetails(context),
        leading: Transform.scale(
          scale: 0.75,
          child: Checkbox(
            value: isSelected,
            visualDensity: VisualDensity.compact,
            onChanged: (value) {
              onSelectionChanged(value ?? false);
            },
          ),
        ),
        title: Text(
          obj.originalText,
          maxLines: 2,
          style: const TextStyle(fontSize: 12),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          obj.translatedText,
          maxLines: 2,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          overflow: TextOverflow.ellipsis,
        ),
        trailing: IconButton(
          onPressed: onPlay,
          tooltip: isPlaying ? 'Stop' : 'Play',
          icon: Icon(isPlaying ? Icons.stop_rounded : Icons.play_arrow_rounded),
        ),
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  final String label;
  final String value;
  final ThemeData theme;

  const _DetailSection({
    required this.label,
    required this.value,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        SelectableText(
          value.isEmpty ? '—' : value,
          style: theme.textTheme.bodyMedium,
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final ThemeData theme;

  const _DetailRow({
    required this.label,
    required this.value,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Expanded(
          child: SelectableText(
            value.isEmpty ? '—' : value,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}
