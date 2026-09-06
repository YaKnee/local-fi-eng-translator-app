import 'dart:convert';
import 'dart:io';

import 'package:dart_sentencepiece_tokenizer/dart_sentencepiece_tokenizer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:path_provider/path_provider.dart';

enum TranslationDirection { englishToFinnish, finnishToEnglish }

class TranslationService extends ChangeNotifier {
  // ---------------------------------------------------------------------------
  // Model configurations
  // ---------------------------------------------------------------------------

  static const _ModelConfig _englishToFinnish = _ModelConfig(
    sourceLanguage: 'en',
    targetLanguage: 'fi',
    modelDirectory: 'assets/models/opus-mt-tc-big-en-fi',
    vocabularySize: 57849,
    decoderStartToken: 57848,
    eosToken: 42657,
  );

  static const _ModelConfig _finnishToEnglish = _ModelConfig(
    sourceLanguage: 'fi',
    targetLanguage: 'en',
    modelDirectory: 'assets/models/opus-mt-tc-big-fi-en',
    vocabularySize: 57830,
    decoderStartToken: 57829,
    eosToken: 41756,
  );

  // ---------------------------------------------------------------------------
  // Shared model configuration
  // ---------------------------------------------------------------------------

  static const int _numberOfLayers = 6;
  static const int _numberOfHeads = 16;
  static const int _headDimension = 64;
  static const int _maxNewTokens = 50;

  // Increment this whenever the bundled ONNX models are replaced.
  static const String _modelCacheVersion = '1';

  // ---------------------------------------------------------------------------
  // Runtime
  // ---------------------------------------------------------------------------

  final OnnxRuntime _ort = OnnxRuntime();

  _LoadedModel? _englishToFinnishModel;
  _LoadedModel? _finnishToEnglishModel;

  Future<void>? _finnishToEnglishInitialization;
  Future<void>? _englishToFinnishInitialization;

  bool _initialized = false;

  // Persistent directory containing cached ONNX model files.
  Directory? _modelCacheDirectory;

  // ---------------------------------------------------------------------------
  // Loading state
  // ---------------------------------------------------------------------------

  double _loadingProgress = 0.0;
  String _loadingStatus = 'Preparing translation engine...';

  // The UI is only notified when the displayed percentage changes.
  //
  // Without this, copying an ~880 MB ONNX file in 4 MB chunks causes roughly
  // 220 ChangeNotifier notifications for a single file.
  int _lastNotifiedProgressPercent = -1;

  double get loadingProgress => _loadingProgress;

  String get loadingStatus => _loadingStatus;

  bool get isInitialized => _initialized;

  bool get isFinnishToEnglishLoaded => _finnishToEnglishModel != null;

  bool get isEnglishToFinnishLoaded => _englishToFinnishModel != null;

  void _setLoadingState(double progress, String status) {
    final clampedProgress = progress.clamp(0.0, 1.0).toDouble();

    final percent = (clampedProgress * 100).round();

    // Always keep the internal values current.
    _loadingProgress = clampedProgress;
    _loadingStatus = status;

    // But do not rebuild the Flutter UI unless the displayed percentage
    // actually changed.
    if (percent == _lastNotifiedProgressPercent) {
      return;
    }

    _lastNotifiedProgressPercent = percent;

    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Initialization
  // ---------------------------------------------------------------------------

  /// Initializes only the primary Finnish -> English model.
  ///
  /// The English -> Finnish model is intentionally NOT loaded here.
  /// It will be loaded lazily when it is actually requested.
  Future<void> initialize() {
    if (_initialized) {
      return Future.value();
    }

    return _finnishToEnglishInitialization ??= _initializePrimaryModel();
  }

  Future<void> _initializePrimaryModel() async {
    print('Initializing TranslationService...');

    // Reset progress notification state for a fresh initialization attempt.
    _lastNotifiedProgressPercent = -1;

    try {
      await _prepareCacheDirectory();

      _setLoadingState(0.02, 'Preparing Finnish → English...');

      print('Loading Finnish -> English model...');

      _finnishToEnglishModel = await _loadModel(
        _finnishToEnglish,
        modelPrefix: 'fi-en',
        progressStart: 0.05,
        progressEnd: 0.90,
      );

      print('Finnish -> English model loaded.');

      _initialized = true;

      _setLoadingState(1.0, 'Translation engine ready');

      print('Primary translation model initialized.');

    } catch (error) {
      await _disposeLoadedModels();

      _finnishToEnglishInitialization = null;

      _initialized = false;

      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Cache
  // ---------------------------------------------------------------------------

  Future<void> _prepareCacheDirectory() async {
    if (_modelCacheDirectory != null) {
      return;
    }

    final applicationDirectory = await getApplicationSupportDirectory();

    final directory = Directory(
      '${applicationDirectory.path}/'
      'translation_models/'
      '$_modelCacheVersion',
    );

    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    _modelCacheDirectory = directory;

    print(
      'ONNX persistent model cache: '
      '${directory.path}',
    );
  }

  // ---------------------------------------------------------------------------
  // Model loading
  // ---------------------------------------------------------------------------

  Future<_LoadedModel> _loadModel(
    _ModelConfig config, {
    required String modelPrefix,
    required double progressStart,
    required double progressEnd,
    bool reportProgress = true,
  }) async {
    final encoderModelAssetPath = '${config.modelDirectory}/encoder_model.onnx';

    final decoderModelAssetPath =
        '${config.modelDirectory}/decoder_model_merged.onnx';

    final sourceSpmPath = '${config.modelDirectory}/source.spm';

    final targetSpmPath = '${config.modelDirectory}/target.spm';

    final vocabPath = '${config.modelDirectory}/vocab.json';

    final modelCacheDirectory = _modelCacheDirectory;

    if (modelCacheDirectory == null) {
      throw StateError('ONNX model cache directory has not been created.');
    }

    // -------------------------------------------------------------------------
    // Source SentencePiece
    // -------------------------------------------------------------------------

    if (reportProgress) {
      _setLoadingState(
        progressStart,
        'Loading ${config.sourceLanguage} tokenizer...',
      );
    }

    print(
      'Loading ${config.sourceLanguage} '
      'SentencePiece model...',
    );

    final sourceSpmData = await rootBundle.load(sourceSpmPath);

    final sourceTokenizer = SentencePieceTokenizer.fromBytes(
      sourceSpmData.buffer.asUint8List(
        sourceSpmData.offsetInBytes,
        sourceSpmData.lengthInBytes,
      ),
    );

    // -------------------------------------------------------------------------
    // Target SentencePiece
    // -------------------------------------------------------------------------

    if (reportProgress) {
      _setLoadingState(
        progressStart + (progressEnd - progressStart) * 0.03,
        'Loading ${config.targetLanguage} tokenizer...',
      );
    }

    print(
      'Loading ${config.targetLanguage} '
      'SentencePiece model...',
    );

    final targetSpmData = await rootBundle.load(targetSpmPath);

    final targetTokenizer = SentencePieceTokenizer.fromBytes(
      targetSpmData.buffer.asUint8List(
        targetSpmData.offsetInBytes,
        targetSpmData.lengthInBytes,
      ),
    );

    // -------------------------------------------------------------------------
    // Vocabulary
    // -------------------------------------------------------------------------

    if (reportProgress) {
      _setLoadingState(
        progressStart + (progressEnd - progressStart) * 0.05,
        'Loading vocabulary...',
      );
    }

    print('Loading Marian vocabulary...');

    final vocabData = await rootBundle.loadString(vocabPath);

    final decoded = jsonDecode(vocabData) as Map;

    final vocab = <String, int>{};
    final reverseVocab = <int, String>{};

    for (final entry in decoded.entries) {
      final token = entry.key;
      final id = entry.value as int;

      vocab[token] = id;
      reverseVocab[id] = token;
    }

    // -------------------------------------------------------------------------
    // Persistent ONNX files
    // -------------------------------------------------------------------------

    final encoderModelFile = File(
      '${modelCacheDirectory.path}/'
      '${modelPrefix}_encoder_model.onnx',
    );

    final decoderModelFile = File(
      '${modelCacheDirectory.path}/'
      '${modelPrefix}_decoder_model_merged.onnx',
    );

    // -------------------------------------------------------------------------
    // Encoder asset
    // -------------------------------------------------------------------------

    if (reportProgress) {
      _setLoadingState(
        progressStart + (progressEnd - progressStart) * 0.08,
        'Preparing encoder model...',
      );
    }

    print(
      'Preparing encoder model:\n'
      '${encoderModelFile.path}',
    );

    await _ensureAssetCached(
      encoderModelAssetPath,
      encoderModelFile,
      progressStart: progressStart + (progressEnd - progressStart) * 0.08,
      progressEnd: progressStart + (progressEnd - progressStart) * 0.20,
      reportProgress: reportProgress,
      status: 'Copying encoder model...',
    );

    // -------------------------------------------------------------------------
    // Decoder asset
    // -------------------------------------------------------------------------

    if (reportProgress) {
      _setLoadingState(
        progressStart + (progressEnd - progressStart) * 0.20,
        'Preparing decoder model...',
      );
    }

    print(
      'Preparing decoder model:\n'
      '${decoderModelFile.path}',
    );

    await _ensureAssetCached(
      decoderModelAssetPath,
      decoderModelFile,
      progressStart: progressStart + (progressEnd - progressStart) * 0.20,
      progressEnd: progressStart + (progressEnd - progressStart) * 0.82,
      reportProgress: reportProgress,
      status: 'Copying decoder model...',
    );

    // -------------------------------------------------------------------------
    // ONNX encoder
    // -------------------------------------------------------------------------

    if (reportProgress) {
      _setLoadingState(
        progressStart + (progressEnd - progressStart) * 0.84,
        'Loading encoder into memory...',
      );
    }

    print(
      'Loading encoder model for '
      '${config.sourceLanguage} -> '
      '${config.targetLanguage}:',
    );

    print(
      'Encoder file: '
      '${encoderModelFile.path}',
    );

    print(
      'Expected vocabulary size: '
      '${config.vocabularySize}',
    );

    final encoderSession = await _ort.createSession(encoderModelFile.path);

    print(
      'Encoder session created for '
      '${config.sourceLanguage} -> '
      '${config.targetLanguage}.',
    );

    // -------------------------------------------------------------------------
    // ONNX decoder
    // -------------------------------------------------------------------------

    if (reportProgress) {
      _setLoadingState(
        progressStart + (progressEnd - progressStart) * 0.93,
        'Loading decoder into memory...',
      );
    }

    print(
      'Loading decoder model for '
      '${config.sourceLanguage} -> '
      '${config.targetLanguage}:',
    );

    print(
      'Decoder file: '
      '${decoderModelFile.path}',
    );

    print(
      'Expected vocabulary size: '
      '${config.vocabularySize}',
    );

    final decoderSession = await _ort.createSession(decoderModelFile.path);

    print(
      'Decoder session created for '
      '${config.sourceLanguage} -> '
      '${config.targetLanguage}.',
    );

    if (reportProgress) {
      _setLoadingState(progressEnd, 'Translation model ready');
    }

    return _LoadedModel(
      config: config,
      encoderSession: encoderSession,
      decoderSession: decoderSession,
      sourceTokenizer: sourceTokenizer,
      targetTokenizer: targetTokenizer,
      vocab: vocab,
      reverseVocab: reverseVocab,
    );
  }

  Future<void> _ensureAssetCached(
    String assetPath,
    File destination, {
    required double progressStart,
    required double progressEnd,
    required bool reportProgress,
    required String status,
  }) async {
    // A non-empty existing file is considered cached.
    //
    // The cache directory includes _modelCacheVersion, so replacing the
    // models can be handled simply by increasing that version.
    if (await destination.exists()) {
      final length = await destination.length();

      if (length > 0) {
        print(
          'Using cached model file: '
          '${destination.path}',
        );

        if (reportProgress) {
          _setLoadingState(progressEnd, 'Using cached model...');
        }

        return;
      }

      try {
        await destination.delete();
      } catch (_) {}
    }

    print(
      'Extracting asset "$assetPath" to:\n'
      '${destination.path}',
    );

    final data = await rootBundle.load(assetPath);

    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );

    // Keep the large-file write chunked.
    //
    // The important difference is that progress notifications are now
    // throttled by _setLoadingState(), so Flutter is not rebuilt for every
    // chunk.
    const chunkSize = 4 * 1024 * 1024;

    final sink = destination.openWrite();

    try {
      int written = 0;

      while (written < bytes.length) {
        final remaining = bytes.length - written;

        final length = remaining < chunkSize ? remaining : chunkSize;

        sink.add(bytes.sublist(written, written + length));

        written += length;

        if (reportProgress) {
          final fileProgress = written / bytes.length;

          final progress =
              progressStart + (progressEnd - progressStart) * fileProgress;

          // This may be called for every 4 MB chunk,
          // but _setLoadingState() only notifies
          // listeners when the displayed percentage
          // changes.
          _setLoadingState(progress, status);
        }
      }
    } finally {
      await sink.flush();
      await sink.close();
    }

    print(
      'Cached ${bytes.length} bytes at '
      '${destination.path}',
    );

    if (reportProgress) {
      _setLoadingState(progressEnd, status);
    }
  }

  // ---------------------------------------------------------------------------
  // Public translation API
  // ---------------------------------------------------------------------------

  Future<String> translate(
    String inputText,
    TranslationDirection direction,
  ) async {
    if (inputText.trim().isEmpty) {
      return '';
    }

    if (!_initialized) {
      await initialize();
    }

    final model = await _ensureModelLoaded(direction);

    return _translateWithModel(inputText, model);
  }

  Future<String> translateEnglishToFinnish(String inputText) {
    return translate(inputText, TranslationDirection.englishToFinnish);
  }

  Future<String> translateFinnishToEnglish(String inputText) {
    return translate(inputText, TranslationDirection.finnishToEnglish);
  }

  Future<_LoadedModel> _ensureModelLoaded(
    TranslationDirection direction,
  ) async {
    // -------------------------------------------------------------------------
    // Finnish -> English
    // -------------------------------------------------------------------------

    if (direction == TranslationDirection.finnishToEnglish) {
      final existing = _finnishToEnglishModel;

      if (existing != null) {
        return existing;
      }

      await initialize();

      final loaded = _finnishToEnglishModel;

      if (loaded == null) {
        throw StateError('Finnish -> English model failed to load.');
      }

      return loaded;
    }

    // -------------------------------------------------------------------------
    // English -> Finnish
    //
    // This model is deliberately lazy-loaded.
    // It is NOT loaded during application startup.
    // -------------------------------------------------------------------------

    final existing = _englishToFinnishModel;

    if (existing != null) {
      return existing;
    }

    // If another request is already loading the model,
    // wait for that same Future instead of starting another load.
    final existingInitialization = _englishToFinnishInitialization;

    if (existingInitialization != null) {
      await existingInitialization;

      final loaded = _englishToFinnishModel;

      if (loaded == null) {
        throw StateError('English -> Finnish model failed to load.');
      }

      return loaded;
    }

    await _prepareCacheDirectory();

    final initialization = _loadEnglishToFinnish();

    _englishToFinnishInitialization = initialization;

    try {
      await initialization;
    } finally {
      // Only clear the Future after this load has completed.
      //
      // Do not clear it before awaiting it, otherwise another caller could
      // start a second 880 MB model load.
      if (identical(_englishToFinnishInitialization, initialization)) {
        _englishToFinnishInitialization = null;
      }
    }

    final loaded = _englishToFinnishModel;

    if (loaded == null) {
      throw StateError('English -> Finnish model failed to load.');
    }

    return loaded;
  }

  Future<void> _loadEnglishToFinnish() async {
    print('Starting English -> Finnish model loading...');

    try {
      _englishToFinnishModel = await _loadModel(
        _englishToFinnish,
        modelPrefix: 'en-fi',
        progressStart: 0.0,
        progressEnd: 1.0,
        reportProgress: false,
      );

      print('English -> Finnish model loaded.');
    } catch (error, stackTrace) {
      print(
        'English -> Finnish model loading failed: '
        '$error',
      );

      print(stackTrace);

      _englishToFinnishModel = null;

      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Translation implementation
  // ---------------------------------------------------------------------------

  Future<String> _translateWithModel(
    String inputText,
    _LoadedModel model,
  ) async {
    final sourceTokenizer = model.sourceTokenizer;

    final targetTokenizer = model.targetTokenizer;

    final vocab = model.vocab;

    final reverseVocab = model.reverseVocab;

    final encoderSession = model.encoderSession;

    final decoderSession = model.decoderSession;

    final config = model.config;

    // -------------------------------------------------------------------------
    // Encode source text
    // -------------------------------------------------------------------------

    final encoding = sourceTokenizer.encode(inputText, addSpecialTokens: false);

    final mappedIds =
        encoding.tokens.map((token) {
          final id = vocab[token];

          if (id == null) {
            throw StateError(
              'Token "$token" was not found in '
              '${config.modelDirectory}/vocab.json.',
            );
          }

          return id;
        }).toList();

    mappedIds.add(config.eosToken);

    final sourceIds = Int64List.fromList(mappedIds);

    final encoderSequenceLength = sourceIds.length;

    final attentionMask = Int64List.fromList(
      List<int>.filled(encoderSequenceLength, 1),
    );

    // -------------------------------------------------------------------------
    // Encoder
    // -------------------------------------------------------------------------

    final sourceIdsTensor = await OrtValue.fromList(sourceIds, [
      1,
      encoderSequenceLength,
    ]);

    final attentionMaskTensor = await OrtValue.fromList(attentionMask, [
      1,
      encoderSequenceLength,
    ]);

    final encoderOutputs = await encoderSession.run({
      'input_ids': sourceIdsTensor,
      'attention_mask': attentionMaskTensor,
    });

    final encoderHiddenStates = encoderOutputs['last_hidden_state'];

    if (encoderHiddenStates == null) {
      await sourceIdsTensor.dispose();
      await attentionMaskTensor.dispose();

      for (final tensor in encoderOutputs.values) {
        await tensor.dispose();
      }

      throw StateError(
        'Encoder did not return '
        'last_hidden_state.',
      );
    }

    // -------------------------------------------------------------------------
    // Decoder generation
    // -------------------------------------------------------------------------

    final generatedTokens = <int>[];

    var decoderInputIds = Int64List.fromList([config.decoderStartToken]);

    final encoderKeyCache = <OrtValue>[];

    final encoderValueCache = <OrtValue>[];

    final decoderKeyCache = <OrtValue>[];

    final decoderValueCache = <OrtValue>[];

    var useCacheBranch = false;

    try {
      for (int step = 0; step < _maxNewTokens; step++) {
        final decoderInputTensor = await OrtValue.fromList(decoderInputIds, [
          1,
          decoderInputIds.length,
        ]);

        final useCacheTensor = await OrtValue.fromList([useCacheBranch], [1]);

        final encoderAttentionMaskTensor = await OrtValue.fromList(
          attentionMask,
          [1, encoderSequenceLength],
        );

        final decoderInputs = <String, OrtValue>{
          'encoder_attention_mask': encoderAttentionMaskTensor,
          'input_ids': decoderInputTensor,
          'encoder_hidden_states': encoderHiddenStates,
          'use_cache_branch': useCacheTensor,
        };

        // ---------------------------------------------------------------------
        // Cache inputs
        // ---------------------------------------------------------------------

        for (int layer = 0; layer < _numberOfLayers; layer++) {
          if (!useCacheBranch) {
            decoderInputs['past_key_values.$layer.decoder.key'] =
                await OrtValue.fromList(Float32List(0), [
                  1,
                  _numberOfHeads,
                  0,
                  _headDimension,
                ]);

            decoderInputs['past_key_values.$layer.decoder.value'] =
                await OrtValue.fromList(Float32List(0), [
                  1,
                  _numberOfHeads,
                  0,
                  _headDimension,
                ]);

            decoderInputs['past_key_values.$layer.encoder.key'] =
                await OrtValue.fromList(
                  Float32List(
                    _numberOfHeads * encoderSequenceLength * _headDimension,
                  ),
                  [1, _numberOfHeads, encoderSequenceLength, _headDimension],
                );

            decoderInputs['past_key_values.$layer.encoder.value'] =
                await OrtValue.fromList(
                  Float32List(
                    _numberOfHeads * encoderSequenceLength * _headDimension,
                  ),
                  [1, _numberOfHeads, encoderSequenceLength, _headDimension],
                );
          } else {
            decoderInputs['past_key_values.$layer.decoder.key'] =
                decoderKeyCache[layer];

            decoderInputs['past_key_values.$layer.decoder.value'] =
                decoderValueCache[layer];

            decoderInputs['past_key_values.$layer.encoder.key'] =
                encoderKeyCache[layer];

            decoderInputs['past_key_values.$layer.encoder.value'] =
                encoderValueCache[layer];
          }
        }

        // ---------------------------------------------------------------------
        // Run decoder
        // ---------------------------------------------------------------------

        final outputs = await decoderSession.run(decoderInputs);

        final logits = outputs['logits'];

        if (logits == null) {
          await decoderInputTensor.dispose();
          await useCacheTensor.dispose();
          await encoderAttentionMaskTensor.dispose();

          await _disposeOutputs(
            outputs,
            except: {
              ...decoderKeyCache,
              ...decoderValueCache,
              ...encoderKeyCache,
              ...encoderValueCache,
            },
          );

          throw StateError('Decoder did not return logits.');
        }

        final logitsValues = await logits.asFlattenedList();

        if (logitsValues.length != config.vocabularySize) {
          await decoderInputTensor.dispose();
          await useCacheTensor.dispose();
          await encoderAttentionMaskTensor.dispose();

          await _disposeOutputs(
            outputs,
            except: {
              ...decoderKeyCache,
              ...decoderValueCache,
              ...encoderKeyCache,
              ...encoderValueCache,
            },
          );

          throw StateError(
            'Expected '
            '${config.vocabularySize} logits, '
            'got ${logitsValues.length}.',
          );
        }

        // ---------------------------------------------------------------------
        // Greedy selection
        // ---------------------------------------------------------------------

        var bestToken = 0;

        var bestLogit = (logitsValues[0] as num).toDouble();

        for (int i = 1; i < logitsValues.length; i++) {
          final value = (logitsValues[i] as num).toDouble();

          if (value > bestLogit) {
            bestLogit = value;
            bestToken = i;
          }
        }

        // ---------------------------------------------------------------------
        // EOS
        // ---------------------------------------------------------------------

        if (bestToken == config.eosToken) {
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
          await encoderAttentionMaskTensor.dispose();

          break;
        }

        generatedTokens.add(bestToken);

        // ---------------------------------------------------------------------
        // Save cache
        // ---------------------------------------------------------------------

        final newDecoderKeys = <OrtValue>[];

        final newDecoderValues = <OrtValue>[];

        final newEncoderKeys = <OrtValue>[];

        final newEncoderValues = <OrtValue>[];

        for (int layer = 0; layer < _numberOfLayers; layer++) {
          final decoderKey = outputs['present.$layer.decoder.key'];

          final decoderValue = outputs['present.$layer.decoder.value'];

          final encoderKey = outputs['present.$layer.encoder.key'];

          final encoderValue = outputs['present.$layer.encoder.value'];

          if (decoderKey == null ||
              decoderValue == null ||
              encoderKey == null ||
              encoderValue == null) {
            await decoderInputTensor.dispose();
            await useCacheTensor.dispose();
            await encoderAttentionMaskTensor.dispose();

            await _disposeOutputs(
              outputs,
              except: {
                ...decoderKeyCache,
                ...decoderValueCache,
                ...encoderKeyCache,
                ...encoderValueCache,
              },
            );

            throw StateError(
              'Missing cache output '
              'for layer $layer.',
            );
          }

          newDecoderKeys.add(decoderKey);

          newDecoderValues.add(decoderValue);

          if (!useCacheBranch) {
            newEncoderKeys.add(encoderKey);

            newEncoderValues.add(encoderValue);
          }
        }

        // ---------------------------------------------------------------------
        // Replace decoder cache
        // ---------------------------------------------------------------------

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

        // Encoder cache only needs to be retained
        // after the first decoder call.
        if (!useCacheBranch) {
          encoderKeyCache.addAll(newEncoderKeys);

          encoderValueCache.addAll(newEncoderValues);
        }

        // ---------------------------------------------------------------------
        // Dispose outputs that aren't cached
        // ---------------------------------------------------------------------

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
        await encoderAttentionMaskTensor.dispose();

        // Next call only receives the newly
        // generated token.
        decoderInputIds = Int64List.fromList([bestToken]);

        useCacheBranch = true;
      }

      // -----------------------------------------------------------------------
      // Marian IDs -> SentencePiece pieces
      // -----------------------------------------------------------------------

      final generatedPieces =
          generatedTokens.map((id) {
            final piece = reverseVocab[id];

            if (piece == null) {
              throw StateError(
                'Generated Marian ID $id was not found '
                'in ${config.modelDirectory}/vocab.json.',
              );
            }

            return piece;
          }).toList();

      // -----------------------------------------------------------------------
      // SentencePiece pieces -> raw SentencePiece IDs
      // -----------------------------------------------------------------------

      final rawSentencePieceIds =
          generatedPieces.map((piece) {
            final rawId = targetTokenizer.vocab.pieceToId(piece);

            if (rawId < 0) {
              throw StateError(
                'SentencePiece piece "$piece" has no '
                'raw SentencePiece ID.',
              );
            }

            return rawId;
          }).toList();

      // -----------------------------------------------------------------------
      // SentencePiece IDs -> target text
      // -----------------------------------------------------------------------

      return targetTokenizer.decode(rawSentencePieceIds);
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
    }
  }

  // ---------------------------------------------------------------------------
  // Cleanup
  // ---------------------------------------------------------------------------

  @override
  Future<void> dispose() async {
    await _disposeLoadedModels();

    // IMPORTANT:
    // Do NOT delete _modelCacheDirectory here.
    //
    // The whole point of this directory is to survive app restarts.
    _modelCacheDirectory = null;

    _initialized = false;

    _finnishToEnglishInitialization = null;

    _englishToFinnishInitialization = null;

    super.dispose();
  }

  Future<void> _disposeLoadedModels() async {
    await _englishToFinnishModel?.dispose();

    await _finnishToEnglishModel?.dispose();

    _englishToFinnishModel = null;
    _finnishToEnglishModel = null;
  }

  // ---------------------------------------------------------------------------
  // Utility
  // ---------------------------------------------------------------------------

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

// =============================================================================
// Internal model classes
// =============================================================================

class _ModelConfig {
  final String sourceLanguage;
  final String targetLanguage;
  final String modelDirectory;
  final int vocabularySize;
  final int decoderStartToken;
  final int eosToken;

  const _ModelConfig({
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.modelDirectory,
    required this.vocabularySize,
    required this.decoderStartToken,
    required this.eosToken,
  });
}

class _LoadedModel {
  final _ModelConfig config;

  final OrtSession encoderSession;
  final OrtSession decoderSession;

  final SentencePieceTokenizer sourceTokenizer;
  final SentencePieceTokenizer targetTokenizer;

  final Map<String, int> vocab;
  final Map<int, String> reverseVocab;

  const _LoadedModel({
    required this.config,
    required this.encoderSession,
    required this.decoderSession,
    required this.sourceTokenizer,
    required this.targetTokenizer,
    required this.vocab,
    required this.reverseVocab,
  });

  Future<void> dispose() async {
    await encoderSession.close();
    await decoderSession.close();
  }
}
