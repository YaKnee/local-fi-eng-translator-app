class Translated {
  final int id;
  final DateTime createdAt;

  final String originalText;
  final String translatedText;

  final String sourceLanguage;
  final String targetLanguage;

  final String? category;

  Translated({
    required this.id,
    required this.createdAt,
    required this.originalText,
    required this.translatedText,
    required this.sourceLanguage,
    required this.targetLanguage,
    this.category,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'createdAt': createdAt.toIso8601String(),
      'originalText': originalText,
      'translatedText': translatedText,
      'sourceLanguage': sourceLanguage,
      'targetLanguage': targetLanguage,
      'category': category,
    };
  }

  factory Translated.fromJson(
    Map<String, dynamic> json,
  ) {
    final idValue = json['id'];

    final id = idValue is int
        ? idValue
        : int.tryParse(idValue?.toString() ?? '') ??
            DateTime.now().millisecondsSinceEpoch;

    final createdAtValue =
        json['createdAt']?.toString();

    final createdAt =
        DateTime.tryParse(
              createdAtValue ?? '',
            ) ??
            DateTime.now();

    final originalText =
        json['originalText']?.toString() ?? '';

    final translatedText =
        json['translatedText']?.toString() ?? '';

    final sourceLanguage =
        json['sourceLanguage']?.toString() ?? 'en';

    final targetLanguage =
        json['targetLanguage']?.toString() ?? 'fi';

    final categoryValue = json['category'];

    return Translated(
      id: id,
      createdAt: createdAt,
      originalText: originalText,
      translatedText: translatedText,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
      category: categoryValue?.toString(),
    );
  }
}