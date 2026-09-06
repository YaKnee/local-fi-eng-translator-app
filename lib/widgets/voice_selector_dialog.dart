import 'package:flutter/material.dart';

import '../models/tts_voice_model.dart';

class VoiceSelectorDialog extends StatefulWidget {
  final List<TtsVoice> voices;
  final TtsVoice? selectedVoice;

  const VoiceSelectorDialog({
    super.key,
    required this.voices,
    required this.selectedVoice,
  });

  @override
  State<VoiceSelectorDialog> createState() => _VoiceSelectorDialogState();
}

class _VoiceSelectorDialogState extends State<VoiceSelectorDialog> {
  final GlobalKey _selectedVoiceKey = GlobalKey();

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToSelectedVoice();
    });
  }

  void _scrollToSelectedVoice() {
    if (!mounted || widget.selectedVoice == null) {
      return;
    }

    final selectedContext = _selectedVoiceKey.currentContext;

    if (selectedContext == null) {
      debugPrint('Could not find selected voice in dialog.');
      return;
    }

    Scrollable.ensureVisible(
      selectedContext,
      alignment: 0.5,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select voice'),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: ListView(
          children: [for (final voice in widget.voices) _buildVoiceTile(voice)],
        ),
      ),
    );
  }

  Widget _buildVoiceTile(TtsVoice voice) {
    final isSelected = voice == widget.selectedVoice;

    return ListTile(
      key: isSelected ? _selectedVoiceKey : null,
      title: Text(voice.displayName),
      subtitle: Text(voice.displaySubtitle),
      trailing: isSelected ? const Icon(Icons.check) : null,
      onTap: () {
        Navigator.of(context).pop(voice);
      },
    );
  }
}
