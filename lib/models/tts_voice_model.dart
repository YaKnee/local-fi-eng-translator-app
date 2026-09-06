class TtsVoice {
  final String name;
  final String locale;
  final String? gender;
  final String? identifier;

  const TtsVoice({
    required this.name,
    required this.locale,
    this.gender,
    this.identifier,
  });

  factory TtsVoice.fromJson(Map<String, dynamic> json) {
    return TtsVoice(
      name: json['name'] as String,
      locale: json['locale'] as String,
      gender: json['gender'] as String?,
      identifier: json['identifier'] as String?,
    );
  }

  factory TtsVoice.fromPlatformMap(Map<dynamic, dynamic> map) {
    return TtsVoice(
      name: map['name']?.toString() ?? '',
      locale: map['locale']?.toString() ?? '',
      gender: map['gender']?.toString(),
      identifier: map['identifier']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'locale': locale,
      'gender': gender,
      'identifier': identifier,
    };
  }

  /// Human-readable voice name.
  String get displayName {
    return name.isEmpty ? 'Unknown voice' : name;
  }

  /// Human-readable language name.
  ///
  /// Examples:
  /// - en-GB -> English
  /// - fr-CA -> French
  /// - de-DE -> German
  String get displayLanguage {
    final languageCode = _languageCode;

    if (languageCode == null) {
      return locale;
    }

    return _languageNames[languageCode] ?? languageCode;
  }

  /// Human-readable region name.
  ///
  /// Returns null when the locale does not contain a
  /// recognizable region.
  ///
  /// Examples:
  /// - en-GB -> United Kingdom
  /// - fr-CA -> Canada
  /// - de-DE -> Germany
  String? get displayRegion {
    final regionCode = _regionCode;

    if (regionCode == null) {
      return null;
    }

    return _regionNames[regionCode] ?? regionCode;
  }

  /// Formats the locale for compact display.
  ///
  /// Examples:
  /// - en-gb -> en-GB
  /// - fr-ca -> fr-CA
  String get displayLocale {
    final parts = locale.split('-');

    if (parts.length < 2) {
      return locale;
    }

    return '${parts[0].toLowerCase()}-'
        '${parts[1].toUpperCase()}';
  }

  /// Human-readable gender.
  ///
  /// Gender is only displayed when the TTS engine provides it.
  /// The voice name itself is not used to guess gender because
  /// Android does not standardize gender information in voice names.
  String get displayGender {
    switch (gender?.toLowerCase()) {
      case 'male':
        return 'Male';

      case 'female':
        return 'Female';

      default:
        return gender ?? '';
    }
  }

  /// Human-readable description of the voice.
  ///
  /// Examples:
  /// - English (United Kingdom) • Female
  /// - French (Canada)
  /// - German
  String get displaySubtitle {
    final location =
        displayRegion == null
            ? displayLanguage
            : '$displayLanguage ($displayRegion)';

    if (displayGender.isNotEmpty) {
      return '$location • $displayGender';
    }

    return location;
  }

  String? get _languageCode {
    if (locale.isEmpty) {
      return null;
    }

    final parts = locale.split('-');

    if (parts.isEmpty || parts.first.isEmpty) {
      return null;
    }

    return parts.first.toLowerCase();
  }

  String? get _regionCode {
    if (locale.isEmpty) {
      return null;
    }

    final parts = locale.split('-');

    if (parts.length < 2) {
      return null;
    }

    final candidate = parts[1];

    // BCP-47 regions are normally either:
    // - two alphabetic characters, e.g. GB
    // - three numeric digits, e.g. 419
    if (candidate.length == 2 && RegExp(r'^[A-Za-z]{2}$').hasMatch(candidate)) {
      return candidate.toUpperCase();
    }

    if (candidate.length == 3 && RegExp(r'^\d{3}$').hasMatch(candidate)) {
      return candidate;
    }

    return null;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }

    return other is TtsVoice &&
        other.name == name &&
        other.locale == locale &&
        other.identifier == identifier;
  }

  @override
  int get hashCode {
    return Object.hash(name, locale, identifier);
  }

  static const Map<String, String> _languageNames = {
    'ar': 'Arabic',
    'bn': 'Bengali',
    'ca': 'Catalan',
    'cs': 'Czech',
    'da': 'Danish',
    'de': 'German',
    'doi': 'Dogri',
    'el': 'Greek',
    'en': 'English',
    'es': 'Spanish',
    'fi': 'Finnish',
    'fr': 'French',
    'gu': 'Gujarati',
    'he': 'Hebrew',
    'hi': 'Hindi',
    'hr': 'Croatian',
    'hu': 'Hungarian',
    'id': 'Indonesian',
    'it': 'Italian',
    'ja': 'Japanese',
    'jv': 'Javanese',
    'kn': 'Kannada',
    'ko': 'Korean',
    'lt': 'Lithuanian',
    'lv': 'Latvian',
    'ml': 'Malayalam',
    'mr': 'Marathi',
    'ms': 'Malay',
    'nb': 'Norwegian Bokmål',
    'ne': 'Nepali',
    'nl': 'Dutch',
    'no': 'Norwegian',
    'or': 'Odia',
    'pa': 'Punjabi',
    'pl': 'Polish',
    'pt': 'Portuguese',
    'ro': 'Romanian',
    'ru': 'Russian',
    'sk': 'Slovak',
    'sl': 'Slovenian',
    'sr': 'Serbian',
    'sv': 'Swedish',
    'sw': 'Swahili',
    'ta': 'Tamil',
    'te': 'Telugu',
    'th': 'Thai',
    'tr': 'Turkish',
    'uk': 'Ukrainian',
    'ur': 'Urdu',
    'vi': 'Vietnamese',
    'zh': 'Chinese',
  };

  static const Map<String, String> _regionNames = {
    'AU': 'Australia',
    'AT': 'Austria',
    'BE': 'Belgium',
    'BR': 'Brazil',
    'CA': 'Canada',
    'CH': 'Switzerland',
    'CN': 'China',
    'CZ': 'Czechia',
    'DE': 'Germany',
    'DK': 'Denmark',
    'ES': 'Spain',
    'FI': 'Finland',
    'FR': 'France',
    'GB': 'United Kingdom',
    'GR': 'Greece',
    'HK': 'Hong Kong',
    'HU': 'Hungary',
    'IE': 'Ireland',
    'IN': 'India',
    'IT': 'Italy',
    'JP': 'Japan',
    'KR': 'South Korea',
    'MX': 'Mexico',
    'MY': 'Malaysia',
    'NL': 'Netherlands',
    'NO': 'Norway',
    'NZ': 'New Zealand',
    'PH': 'Philippines',
    'PL': 'Poland',
    'PT': 'Portugal',
    'RO': 'Romania',
    'RU': 'Russia',
    'SE': 'Sweden',
    'SG': 'Singapore',
    'SK': 'Slovakia',
    'TH': 'Thailand',
    'TR': 'Türkiye',
    'TW': 'Taiwan',
    'UA': 'Ukraine',
    'US': 'United States',
    'VN': 'Vietnam',
    'ZA': 'South Africa',
  };
}
