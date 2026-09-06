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
