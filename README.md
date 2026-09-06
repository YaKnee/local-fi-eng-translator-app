# Offline English ↔ Finnish Translation for Android

A Flutter application for fully offline English ↔ Finnish translation using ONNX versions of the Helsinki-NLP OPUS-MT models.

Two translation models are bundled with the application:

| Direction         | Model                                                                                         |
| ----------------- | --------------------------------------------------------------------------------------------- |
| English → Finnish | [Helsinki-NLP/opus-mt-tc-big-en-fi](https://huggingface.co/Helsinki-NLP/opus-mt-tc-big-en-fi) |
| Finnish → English | [Helsinki-NLP/opus-mt-tc-big-fi-en](https://huggingface.co/Helsinki-NLP/opus-mt-tc-big-fi-en) |

Inference runs locally on the Android device through ONNX Runtime. No translation server or translation API is required.

## Features

* English → Finnish translation
* Finnish → English translation
* Fully offline inference
* ONNX Runtime inference on Android
* Bundled translation models
* Local SentencePiece tokenization
* Separate model for each translation direction
* No network connection required for translation
* Persistent local model caching to avoid extracting large ONNX files on every startup

## Architecture

The translation pipeline is:

```text
Input text
    │
    ▼
SentencePiece tokenizer
    │
    ▼
Marian vocabulary mapping
    │
    ▼
ONNX encoder
    │
    ▼
ONNX decoder
    │
    │  autoregressive token generation
    ▼
Generated token IDs
    │
    ▼
Marian vocabulary
    │
    ▼
SentencePiece decoder
    │
    ▼
Translated text
```

Each translation direction has its own encoder, decoder, vocabulary, and SentencePiece models.

The application keeps loaded ONNX inference sessions alive so that subsequent translations do not need to recreate the sessions.

See [`TranslationService`](lib/services/translation_service.dart) for the implementation.

## Models

### English → Finnish

[Helsinki-NLP/opus-mt-tc-big-en-fi](https://huggingface.co/Helsinki-NLP/opus-mt-tc-big-en-fi)

Translates English text into Finnish.

### Finnish → English

[Helsinki-NLP/opus-mt-tc-big-fi-en](https://huggingface.co/Helsinki-NLP/opus-mt-tc-big-fi-en)

Translates Finnish text into English.

The original Hugging Face models are converted to ONNX before being bundled as Flutter assets.

## ONNX Model Conversion

The original Transformers models are not loaded directly by Flutter. They are converted to ONNX first:

```text
Hugging Face / Transformers model
              │
              ▼
         ONNX export
              │
              ▼
       ONNX model files
              │
              ▼
       Flutter application
              │
              ▼
        ONNX Runtime
```

Each model directory contains the files required for local inference, including:

```text
encoder_model.onnx
decoder_model_merged.onnx
source.spm
target.spm
vocab.json
config.json
generation_config.json
tokenizer_config.json
special_tokens_map.json
```

The encoder and decoder are loaded as separate ONNX Runtime sessions.

## Model Loading and Caching

The translation models are large, so model loading is treated separately from individual translation requests.

At startup, the application prioritizes the **Finnish → English** model because it is the primary translation direction. The English → Finnish model can be loaded in the background afterward.

The application also maintains a local cache of the ONNX files. This avoids repeatedly copying hundreds of megabytes of model data from Flutter's bundled assets into temporary files on every application startup.

Conceptually:

```text
Application startup
       │
       ▼
Check local ONNX cache
       │
       ├── Cached ──────────────┐
       │                       │
       └── Not cached          │
               │               │
               ▼               │
       Extract from assets     │
               │               │
               ▼               │
          Cache files          │
               │               │
               └───────────────┤
                               ▼
                    Create ONNX sessions
                               │
                               ▼
                    FI → EN ready first
                               │
                               ▼
                    EN → FI loads in
                    background
```

A startup loading screen reports model-loading progress so the user can see which stage is currently being performed.

See [`TranslationService`](lib/services/translation_service.dart) for model initialization, caching, and session management.

## Offline Operation

After installation, translation itself does not require network connectivity.

```text
┌─────────────────────────────────────┐
│             Flutter App             │
│                                     │
│  Text                               │
│   │                                 │
│   ▼                                 │
│  SentencePiece                      │
│   │                                 │
│   ▼                                 │
│  ONNX Runtime                       │
│   │                                 │
│   ▼                                 │
│  Translation Model                  │
│   │                                 │
│   ▼                                 │
│  Translated Text                    │
│                                     │
└─────────────────────────────────────┘
                  │
                  X
            No network required
```

This makes the application suitable for situations where network access is unavailable, restricted, unreliable, or intentionally avoided.

## Project Structure

```text
.
├── assets/
│   └── models/
│       ├── opus-mt-tc-big-en-fi/
│       │   ├── encoder_model.onnx
│       │   ├── decoder_model_merged.onnx
│       │   ├── source.spm
│       │   ├── target.spm
│       │   ├── vocab.json
│       │   └── ...
│       │
│       └── opus-mt-tc-big-fi-en/
│           ├── encoder_model.onnx
│           ├── decoder_model_merged.onnx
│           ├── source.spm
│           ├── target.spm
│           ├── vocab.json
│           └── ...
│
├── lib/
│   ├── main.dart
│   ├── models/
│   ├── screens/
│   └── services/
│       └── translation_service.dart
│
├── android/
├── pubspec.yaml
└── README.md
```

## Setup

Install the Flutter dependencies:

```bash
flutter pub get
```

The ONNX model directories must be present under `assets/models/`.

The assets are registered in `pubspec.yaml`:

```yaml
flutter:
  assets:
    - assets/models/opus-mt-tc-big-en-fi/
    - assets/models/opus-mt-tc-big-fi-en/
```

Then run the application:

```bash
flutter run
```

Because the model files are large, the first startup can take considerably longer than subsequent startups while the local model cache is created.

## Usage

The translation service exposes a direction-based API:

```dart
final result = await translationService.translate(
  'Hello, how are you?',
  TranslationDirection.englishToFinnish,
);
```

Finnish → English:

```dart
final result = await translationService.translate(
  'Hei, mitä kuuluu?',
  TranslationDirection.finnishToEnglish,
);
```

Convenience methods are also available:

```dart
final finnish =
    await translationService.translateEnglishToFinnish(
  'Hello, how are you?',
);

final english =
    await translationService.translateFinnishToEnglish(
  'Hei, mitä kuuluu?',
);
```

The service handles:

1. Selecting the appropriate translation model.
2. Tokenizing the input with SentencePiece.
3. Mapping tokens through the Marian vocabulary.
4. Running the ONNX encoder.
5. Running autoregressive decoder inference.
6. Maintaining decoder key/value caches during generation.
7. Selecting generated tokens.
8. Converting generated tokens back to SentencePiece pieces.
9. Decoding the pieces into text.

## Dependencies

The main runtime dependencies are:

[flutter_onnxruntime](https://pub.dev/packages/flutter_onnxruntime)
[dart_sentencepiece_tokenizer](https://pub.dev/packages/dart_sentencepiece_tokenizer)
[provider](https://pub.dev/packages/provider)
[shared_preferences](https://pub.dev/packages/shared_preferences)
[path_provider](https://pub.dev/packages/path_provider)
[record](https://pub.dev/packages/record)
[audioplayers](https://pub.dev/packages/audioplayers)
[flutter_tts](https://pub.dev/packages/flutter_tts)
[speech_to_text](https://pub.dev/packages/speech_to_text)

The complete dependency list and version constraints are defined in [`pubspec.yaml`](pubspec.yaml).

## Memory and Storage

The translation models are large and have a significant memory footprint.

Resource usage is affected by:

* ONNX model size
* ONNX Runtime
* Encoder intermediate tensors
* Decoder key/value caches
* Tokenizer and vocabulary data
* Input sequence length
* Maximum generated token count
* Number of loaded translation models

The application may have both translation models loaded simultaneously once background loading has completed.

The bundled model files also substantially increase application size.

Potential future optimizations include:

* ONNX graph optimization
* Model quantization
* Reduced-precision inference
* More efficient model loading
* Loading only one translation direction when memory is constrained
* Further reducing unnecessary tensor allocations

Any optimization must be validated against translation quality and runtime compatibility on target Android devices.

## Limitations

Translation quality and performance depend on the underlying OPUS-MT models and the device running inference.

Known limitations include:

* Translation quality is not equivalent to every cloud translation service.
* Inference speed varies significantly between Android devices.
* Lower-end devices may take longer to generate translations.
* Large model files increase application size and storage requirements.
* Long input sequences may require additional handling or truncation.
* Loading both models simultaneously increases memory usage.
* ONNX conversion must preserve the original encoder/decoder behavior.
* SentencePiece tokenization and Marian vocabulary mappings must remain compatible with the corresponding model.
* CPU inference may be relatively expensive for long translations.

## Development Workflow

When updating or replacing a translation model, the general workflow is:

```text
Hugging Face model
       │
       ▼
Convert to ONNX
       │
       ▼
Validate ONNX inputs/outputs
       │
       ▼
Validate vocabulary/tokenizer compatibility
       │
       ▼
Add model assets to Flutter
       │
       ▼
Test Android inference
       │
       ▼
Measure memory and performance
       │
       ▼
Validate translation quality
```

The ONNX model's output vocabulary dimension must match the vocabulary configuration used by the corresponding translation direction.

For example, the two bundled decoder models have different vocabulary sizes, so the model configuration must not be shared blindly between directions.


