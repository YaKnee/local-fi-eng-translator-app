import 'package:flutter/material.dart';

import '../models/translated_model.dart';

class PlaybackMiniPlayer extends StatelessWidget {
  final Translated item;
  final int currentIndex;
  final int totalItems;

  final VoidCallback onStop;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  const PlaybackMiniPlayer({
    super.key,
    required this.item,
    required this.currentIndex,
    required this.totalItems,
    required this.onStop,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final hasPrevious = currentIndex > 1;
    final hasNext = currentIndex < totalItems;

    return Material(
      elevation: 8,
      color: theme.colorScheme.surfaceContainerHighest,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(
            children: [
              // -----------------------------------------------------------
              // Playing indicator
              // -----------------------------------------------------------
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.volume_up_rounded,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),

              const SizedBox(width: 12),

              // -----------------------------------------------------------
              // Current recording
              // -----------------------------------------------------------
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Playing $currentIndex of $totalItems',
                      style: theme.textTheme.labelSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.originalText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      item.translatedText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 4),

              // -----------------------------------------------------------
              // Previous
              // -----------------------------------------------------------
              IconButton(
                onPressed: hasPrevious ? onPrevious : null,
                tooltip: 'Previous',
                icon: const Icon(Icons.skip_previous_rounded),
              ),

              // -----------------------------------------------------------
              // Next
              // -----------------------------------------------------------
              IconButton(
                onPressed: hasNext ? onNext : null,
                tooltip: 'Next',
                icon: const Icon(Icons.skip_next_rounded),
              ),

              // -----------------------------------------------------------
              // Stop
              // -----------------------------------------------------------
              IconButton(
                onPressed: onStop,
                tooltip: 'Stop',
                icon: const Icon(Icons.stop_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
