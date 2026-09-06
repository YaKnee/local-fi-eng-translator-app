# Offline English ↔ Finnish Translation for Android

A Flutter application that performs English ↔ Finnish translation entirely offline using ONNX versions of the Helsinki-NLP OPUS-MT translation models.

The app uses two separate neural machine translation models:

English → Finnish: Helsinki-NLP/opus-mt-tc-big-en-fi
Finnish → English: Helsinki-NLP/opus-mt-tc-big-fi-en

The original models are converted to ONNX and bundled with the Flutter application. Translation is performed locally on the Android device, without requiring an internet connection or external translation API.

## Features

English → Finnish translation
Finnish → English translation
Fully offline inference
ONNX Runtime inference inside Flutter
Models bundled with the Android application
No translation API or server required
Works without network connectivity after installation
Separate model for each translation direction

## Models

### English → Finnish

[Helsinki-NLP/opus-mt-tc-big-en-fi](https://huggingface.co/Helsinki-NLP/opus-mt-tc-big-en-fi)

The model translates text from English into Finnish.

### Finnish → English

[Helsinki-NLP/opus-mt-tc-big-fi-en](https://huggingface.co/Helsinki-NLP/opus-mt-tc-big-fi-en)

The model translates text from Finnish into English.

The original Hugging Face models are converted to ONNX so they can be executed locally from the Flutter Android application.

## ONNX Conversion

The original Hugging Face models are not loaded directly by Flutter. They are first converted to ONNX.

The general conversion pipeline is:

```text
Hugging Face model
       │
       ▼
PyTorch / Transformers
       │
       ▼
ONNX export
       │
       ▼
ONNX model files
       │
       ▼
Flutter assets
```

The resulting ONNX files are included in the Flutter application's assets.

## Project Structure

Structure is:

```text
.
├── assets/
│   └── models/
│       ├── opus-mt-tc-big-en-fi/
│       │   ├── encoder_model.onnx
│       │   ├── decoder_model_merged.onnx
│       │   ├── tokenizer_config.json
│       │   └── ...
│       │
│       └── opus-mt-tc-big-fi-en/
│           ├── encoder_model.onnx
│           ├── decoder_model_merged.onnx
│           ├── tokenizer_config.json
│           └── ...
│
├── lib/
│   ├── main.dart
│   ├── models/
│   ├── services/
│   │   └── translation_service.dart
│   └── ...
│
├── android/
├── pubspec.yaml
└── README.md
```

## Flutter Setup

Clone the repository and install the Flutter dependencies:

```bash
flutter pub get
```

Make sure the ONNX model files are available under the configured assets directory.

For example:

```yaml
flutter:
  assets:
    - assets/models/opus-mt-tc-big-en-fi/
    - assets/models/opus-mt-tc-big-fi-en/
```

## ONNX Runtime

The Flutter application uses an ONNX Runtime Flutter/Dart binding to execute the models locally.

The general inference flow is:

```text
Input text
    │
    ▼
Tokenizer
    │
    ▼
Input IDs / attention mask
    │
    ▼
ONNX Runtime
    │
    ▼
Generated token IDs
    │
    ▼
Tokenizer decoder
    │
    ▼
Translated text
```

The application selects the appropriate ONNX model based on the requested translation direction.

## Translation Flow

### English → Finnish

```text
English text
     │
     ▼
English tokenizer
     │
     ▼
EN → FI ONNX model
     │
     ▼
Generated token IDs
     │
     ▼
Finnish decoding
     │
     ▼
Finnish text
```

### Finnish → English

```text
Finnish text
     │
     ▼
Finnish tokenizer
     │
     ▼
FI → EN ONNX model
     │
     ▼
Generated token IDs
     │
     ▼
English decoding
     │
     ▼
English text
```

## Offline Operation

Translation does not require a network connection once the application and model assets are installed.

```text
┌─────────────────────────────┐
│       Flutter App           │
│                             │
│  ┌───────────────────────┐  │
│  │ Tokenizer             │  │
│  └───────────┬───────────┘  │
│              │              │
│              ▼              │
│  ┌───────────────────────┐  │
│  │ ONNX Runtime          │  │
│  └───────────┬───────────┘  │
│              │              │
│              ▼              │
│  ┌───────────────────────┐  │
│  │ Translation Model     │  │
│  └───────────────────────┘  │
│                             │
└─────────────────────────────┘
              │
              X
        No network required
```

This makes the application suitable for environments where network access is unavailable, restricted, unreliable, or undesirable.

## Example Usage

Translation service exposes a simple API:

```dart
final result = await translationService.translate(
  'Hello, how are you?',
  TranslationDirection.englishToFinnish,
);
```

For Finnish → English:

```dart
final result = await translationService.translate(
  'Hei, mitä kuuluu?',
  TranslationDirection.finnishToEnglish,
);
```

The service is responsible for:

1. Selecting the correct model.
2. Tokenizing the input.
3. Creating ONNX Runtime tensors.
4. Running model inference.
5. Performing token generation.
6. Decoding the generated tokens.
7. Returning the translated text.

> See more at [TranslationService.translate](./lib/services/translation_service.dart#L666)

## Model Loading

Models are loaded from Flutter assets rather than downloaded at runtime.

```

```text
Application startup
       │
       ▼
Load FI → EN model
       │
       ▼
Create inference session
       │
       ▼
Keep session alive
       │
       ▼
Translate multiple inputs
       │
       ▼
Load EN → FI model if required
       │
       ▼
Create inference session
```

This avoids repeatedly loading large model files and creating inference sessions for every translation request.

> See example at [TranslationService._loadModel](./lib/services/translation_service.dart#L237)


## Memory Usage

Because the models are bundled with the application, the installed application size is larger than a typical Flutter application.

The runtime memory footprint is also affected by:

- Model size
- ONNX Runtime
- Intermediate tensors
- Tokenizer data
- Decoder state
- Maximum sequence length

If application size or memory usage becomes a concern, the ONNX models can potentially be optimized or quantized, provided that translation quality remains acceptable.

## Limitations

The application is designed for offline translation, so it does not provide the same capabilities as cloud translation services.

Limitations include:

- Translation quality depends on the underlying OPUS-MT models.
- Long inputs may require truncation or special handling.
- Inference speed varies significantly between Android devices.
- Model files increase application size.
- CPU inference may be relatively slow on lower-end devices.
- ONNX conversion must preserve the model's encoder/decoder behavior correctly.
- Tokenization must match the model used during training.


## Development Workflow

```text
1. Download Hugging Face models
             │
             ▼
2. Convert models to ONNX
             │
             ▼
3. Validate ONNX output
             │
             ▼
4. Add ONNX/tokenizer assets to Flutter
             │
             ▼
5. Initialize ONNX Runtime
             │
             ▼
6. Tokenize input
             │
             ▼
7. Run encoder/decoder inference
             │
             ▼
8. Decode generated tokens
             │
             ▼
9. Display translation
```

## Dependencies

The project requires Flutter and an ONNX Runtime package capable of running ONNX models on Android.

The exact dependencies are defined in [`pubspec.yaml`](pubspec.yaml).