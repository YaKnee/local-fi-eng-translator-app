import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_sentencepiece_tokenizer/dart_sentencepiece_tokenizer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

class OnnxTestService {
  final OnnxRuntime _ort = OnnxRuntime();

  Future<void> testDecoderGeneration() async {
    const encoderModelPath =
        'assets/models/opus-mt-tc-big-en-fi/encoder_model.onnx';

    const decoderModelPath =
        'assets/models/opus-mt-tc-big-en-fi/decoder_model_merged.onnx';

    const sourceSpmPath =
        'assets/models/opus-mt-tc-big-en-fi/source.spm';

    const targetSpmPath =
        'assets/models/opus-mt-tc-big-en-fi/target.spm';

    const vocabPath =
        'assets/models/opus-mt-tc-big-en-fi/vocab.json';

    // ------------------------------------------------------------
    // Configuration
    // ------------------------------------------------------------

    const numberOfLayers = 6;
    const numberOfHeads = 16;
    const headDimension = 64;
    const vocabularySize = 57849;

    const decoderStartToken = 57848;
    const eosToken = 42657;

    const maxNewTokens = 50;

    // ------------------------------------------------------------
    // Test input
    // ------------------------------------------------------------

    const inputText = 'Hello, how are you?';

    // ------------------------------------------------------------
    // Load tokenizers and vocabulary
    // ------------------------------------------------------------

    print('Loading source SentencePiece model...');

    final sourceSpmData = await rootBundle.load(sourceSpmPath);

    final sourceTokenizer = SentencePieceTokenizer.fromBytes(
      sourceSpmData.buffer.asUint8List(
        sourceSpmData.offsetInBytes,
        sourceSpmData.lengthInBytes,
      ),
    );

    print('Source SentencePiece model loaded.');

    print('Loading target SentencePiece model...');

    final targetSpmData = await rootBundle.load(targetSpmPath);

    final targetTokenizer = SentencePieceTokenizer.fromBytes(
      targetSpmData.buffer.asUint8List(
        targetSpmData.offsetInBytes,
        targetSpmData.lengthInBytes,
      ),
    );

    print('Target SentencePiece model loaded.');

    print('Loading Marian vocabulary...');

    final vocabData = await rootBundle.loadString(vocabPath);

    final vocab = Map<String, dynamic>.from(
      jsonDecode(vocabData) as Map,
    );

    final reverseVocab = <int, String>{};

    for (final entry in vocab.entries) {
      final token = entry.key;
      final id = entry.value as int;
      reverseVocab[id] = token;
    }

    print('Marian vocabulary loaded.');

    // ------------------------------------------------------------
    // Encode input text
    // ------------------------------------------------------------

    print('');
    print('Input text: "$inputText"');

    final encoding = sourceTokenizer.encode(
      inputText,
      addSpecialTokens: false,
    );

    print('SentencePiece IDs: ${encoding.ids}');
    print('SentencePiece pieces: ${encoding.tokens}');

    final mappedIds = encoding.tokens.map((token) {
      final id = vocab[token];

      if (id == null) {
        throw StateError(
          'Token "$token" was not found in vocab.json.',
        );
      }

      return id as int;
    }).toList();

    mappedIds.add(eosToken);

    print('Marian encoder IDs: $mappedIds');

    final sourceIds = Int64List.fromList(mappedIds);

    final encoderSequenceLength = sourceIds.length;

    final attentionMask = Int64List.fromList(
      List<int>.filled(
        encoderSequenceLength,
        1,
      ),
    );

    // ------------------------------------------------------------
    // Load models
    // ------------------------------------------------------------

    print('');
    print('Loading encoder...');

    final encoderSession =
        await _ort.createSessionFromAsset(encoderModelPath);

    print('Encoder loaded.');

    print('Loading decoder...');

    final decoderSession =
        await _ort.createSessionFromAsset(decoderModelPath);

    print('Decoder loaded.');

    // ------------------------------------------------------------
    // Encoder
    // ------------------------------------------------------------

    print('');
    print('Creating encoder tensors...');

    final sourceIdsTensor = await OrtValue.fromList(
      sourceIds,
      [1, encoderSequenceLength],
    );

    final attentionMaskTensor = await OrtValue.fromList(
      attentionMask,
      [1, encoderSequenceLength],
    );

    print('Running encoder...');

    final encoderOutputs = await encoderSession.run({
      'input_ids': sourceIdsTensor,
      'attention_mask': attentionMaskTensor,
    });

    final encoderHiddenStates =
        encoderOutputs['last_hidden_state'];

    if (encoderHiddenStates == null) {
      throw StateError(
        'Encoder did not return last_hidden_state.',
      );
    }

    print(
      'Encoder output: ${encoderHiddenStates.shape}',
    );

    // ------------------------------------------------------------
    // Decoder generation
    // ------------------------------------------------------------

    final generatedTokens = <int>[];

    var decoderInputIds = Int64List.fromList([
      decoderStartToken,
    ]);

    // Encoder cross-attention cache.
    //
    // These are produced by the first decoder call and then
    // remain unchanged for the rest of generation.
    final encoderKeyCache = <OrtValue>[];
    final encoderValueCache = <OrtValue>[];

    // Decoder self-attention cache.
    //
    // These are replaced after every decoder call.
    final decoderKeyCache = <OrtValue>[];
    final decoderValueCache = <OrtValue>[];

    var useCacheBranch = false;

    try {
      for (int step = 0; step < maxNewTokens; step++) {
        print('');
        print('--- Decoder step $step ---');
        print('Input token: ${decoderInputIds[0]}');
        print('use_cache_branch: $useCacheBranch');

        final decoderInputTensor = await OrtValue.fromList(
          decoderInputIds,
          [1, decoderInputIds.length],
        );

        final useCacheTensor = await OrtValue.fromList(
          [useCacheBranch],
          [1],
        );

        final decoderInputs = <String, OrtValue>{
          'encoder_attention_mask':
              await OrtValue.fromList(
            attentionMask,
            [1, encoderSequenceLength],
          ),
          'input_ids': decoderInputTensor,
          'encoder_hidden_states': encoderHiddenStates,
          'use_cache_branch': useCacheTensor,
        };

        // ----------------------------------------------------------
        // Cache inputs
        // ----------------------------------------------------------

        for (int layer = 0; layer < numberOfLayers; layer++) {
          if (!useCacheBranch) {
            // First decoder call.
            //
            // Decoder self-attention cache:
            // [1, 16, 0, 64]
            //
            // Encoder attention cache:
            // [1, 16, encoderSequenceLength, 64]

            decoderInputs[
                'past_key_values.$layer.decoder.key'] =
                await OrtValue.fromList(
              Float32List(0),
              [1, numberOfHeads, 0, headDimension],
            );

            decoderInputs[
                'past_key_values.$layer.decoder.value'] =
                await OrtValue.fromList(
              Float32List(0),
              [1, numberOfHeads, 0, headDimension],
            );

            decoderInputs[
                'past_key_values.$layer.encoder.key'] =
                await OrtValue.fromList(
              Float32List(
                1 *
                    numberOfHeads *
                    encoderSequenceLength *
                    headDimension,
              ),
              [
                1,
                numberOfHeads,
                encoderSequenceLength,
                headDimension,
              ],
            );

            decoderInputs[
                'past_key_values.$layer.encoder.value'] =
                await OrtValue.fromList(
              Float32List(
                1 *
                    numberOfHeads *
                    encoderSequenceLength *
                    headDimension,
              ),
              [
                1,
                numberOfHeads,
                encoderSequenceLength,
                headDimension,
              ],
            );
          } else {
            decoderInputs[
                'past_key_values.$layer.decoder.key'] =
                decoderKeyCache[layer];

            decoderInputs[
                'past_key_values.$layer.decoder.value'] =
                decoderValueCache[layer];

            decoderInputs[
                'past_key_values.$layer.encoder.key'] =
                encoderKeyCache[layer];

            decoderInputs[
                'past_key_values.$layer.encoder.value'] =
                encoderValueCache[layer];
          }
        }

        // ----------------------------------------------------------
        // Run decoder
        // ----------------------------------------------------------

        print('Running decoder...');

        final outputs = await decoderSession.run(
          decoderInputs,
        );

        print('Decoder completed.');

        final logits = outputs['logits'];

        if (logits == null) {
          throw StateError(
            'Decoder did not return logits.',
          );
        }

        print('Logits shape: ${logits.shape}');

        final logitsValues =
            await logits.asFlattenedList();

        if (logitsValues.length != vocabularySize) {
          throw StateError(
            'Expected $vocabularySize logits, '
            'got ${logitsValues.length}.',
          );
        }

        // ----------------------------------------------------------
        // Greedy selection
        // ----------------------------------------------------------

        var bestToken = 0;
        var bestLogit =
            (logitsValues[0] as num).toDouble();

        for (int i = 1; i < logitsValues.length; i++) {
          final value =
              (logitsValues[i] as num).toDouble();

          if (value > bestLogit) {
            bestLogit = value;
            bestToken = i;
          }
        }

        print(
          'Best token: $bestToken '
          '(logit $bestLogit)',
        );

        // ----------------------------------------------------------
        // EOS
        // ----------------------------------------------------------

        if (bestToken == eosToken) {
          print('EOS reached.');

          await _disposeOutputs(
            outputs,
            except: {
              ...decoderKeyCache,
              ...decoderValueCache,
              ...encoderKeyCache,
              ...encoderValueCache,
            },
          );

          await decoderInputTensor.dispose();
          await useCacheTensor.dispose();

          break;
        }

        generatedTokens.add(bestToken);

        print(
          'Generated tokens: $generatedTokens',
        );

        // ----------------------------------------------------------
        // Save cache
        // ----------------------------------------------------------

        final newDecoderKeys = <OrtValue>[];
        final newDecoderValues = <OrtValue>[];

        final newEncoderKeys = <OrtValue>[];
        final newEncoderValues = <OrtValue>[];

        for (int layer = 0; layer < numberOfLayers; layer++) {
          final decoderKey =
              outputs[
                  'present.$layer.decoder.key'];

          final decoderValue =
              outputs[
                  'present.$layer.decoder.value'];

          final encoderKey =
              outputs[
                  'present.$layer.encoder.key'];

          final encoderValue =
              outputs[
                  'present.$layer.encoder.value'];

          if (decoderKey == null ||
              decoderValue == null ||
              encoderKey == null ||
              encoderValue == null) {
            throw StateError(
              'Missing cache output for layer $layer.',
            );
          }

          newDecoderKeys.add(decoderKey);
          newDecoderValues.add(decoderValue);

          if (!useCacheBranch) {
            newEncoderKeys.add(encoderKey);
            newEncoderValues.add(encoderValue);
          }
        }

        // Dispose the old decoder cache after the new outputs
        // have been obtained.
        for (final tensor in decoderKeyCache) {
          await tensor.dispose();
        }

        for (final tensor in decoderValueCache) {
          await tensor.dispose();
        }

        decoderKeyCache
          ..clear()
          ..addAll(newDecoderKeys);

        decoderValueCache
          ..clear()
          ..addAll(newDecoderValues);

        if (!useCacheBranch) {
          encoderKeyCache.addAll(newEncoderKeys);
          encoderValueCache.addAll(newEncoderValues);
        }

        // Dispose outputs that are not being retained as cache.
        final retained = <OrtValue>{
          ...decoderKeyCache,
          ...decoderValueCache,
          ...encoderKeyCache,
          ...encoderValueCache,
        };

        for (final entry in outputs.entries) {
          if (!retained.contains(entry.value)) {
            await entry.value.dispose();
          }
        }

        await decoderInputTensor.dispose();
        await useCacheTensor.dispose();

        // Next decoder call receives only the newly generated token.
        decoderInputIds = Int64List.fromList([
          bestToken,
        ]);

        useCacheBranch = true;
      }

      // ------------------------------------------------------------
      // Decode generated Marian IDs
      // ------------------------------------------------------------

      print('');
      print('================================');
      print('Generation complete.');
      print('Generated Marian token IDs:');
      print(generatedTokens);

      final generatedPieces = generatedTokens.map((id) {
        final piece = reverseVocab[id];

        if (piece == null) {
          throw StateError(
            'Generated Marian ID $id was not found '
            'in vocab.json.',
          );
        }

        return piece;
      }).toList();

      print('Generated SentencePiece pieces:');
      print(generatedPieces);

      final rawSentencePieceIds =
          generatedPieces.map((piece) {
        final rawId =
            targetTokenizer.vocab.pieceToId(piece);

        if (rawId < 0) {
          throw StateError(
            'SentencePiece piece "$piece" has no '
            'raw SentencePiece ID.',
          );
        }

        return rawId;
      }).toList();

      print('Raw SentencePiece IDs:');
      print(rawSentencePieceIds);

      final translatedText =
          targetTokenizer.decode(rawSentencePieceIds);

      print('Translated text:');
      print('"$translatedText"');

      print('================================');

      if (translatedText != 'Hei, mitä kuuluu?') {
        throw StateError(
          'Unexpected translation.\n'
          'Expected: "Hei, mitä kuuluu?"\n'
          'Actual:   "$translatedText"',
        );
      }

      print('ENGLISH -> FINNISH TRANSLATION TEST SUCCESS.');
    } finally {
      for (final tensor in decoderKeyCache) {
        await tensor.dispose();
      }

      for (final tensor in decoderValueCache) {
        await tensor.dispose();
      }

      for (final tensor in encoderKeyCache) {
        await tensor.dispose();
      }

      for (final tensor in encoderValueCache) {
        await tensor.dispose();
      }

      await encoderHiddenStates.dispose();

      for (final tensor in encoderOutputs.values) {
        if (tensor != encoderHiddenStates) {
          await tensor.dispose();
        }
      }

      await sourceIdsTensor.dispose();
      await attentionMaskTensor.dispose();

      await encoderSession.close();
      await decoderSession.close();

      print('Sessions closed.');
    }
  }

  Future<void> _disposeOutputs(
    Map<String, OrtValue> outputs, {
    Set<OrtValue> except = const {},
  }) async {
    for (final tensor in outputs.values) {
      if (!except.contains(tensor)) {
        await tensor.dispose();
      }
    }
  }
}