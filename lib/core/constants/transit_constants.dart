class TransitConstants {
  static const Map<String, String> lineNames = {
    'AGL': 'LRT Ampang Line',
    'SPL': 'LRT Sri Petaling Line',
    'KJL': 'LRT Kelana Jaya Line',
    'MRL': 'KL Monorail',
    'KGL': 'MRT Kajang Line',
    'PYL': 'MRT Putrajaya Line',
    'BRT': 'BRT Sunway Line',
  };

  static const Map<String, String> linePrefixes = {
    'AGL': 'LRT',
    'SPL': 'LRT',
    'KJL': 'LRT',
    'MRL': 'Monorail',
    'KGL': 'MRT',
    'PYL': 'MRT',
    'BRT': 'BRT',
  };

  static String formatStationName(String name, String shortName) {
    String cleanName = name
        .replaceAll(RegExp(r'\b(lrt|mrt|mrl|monorail|brt|station)\b', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final formattedName = cleanName.split(' ').map((word) {
      if (word.isEmpty) return '';
      if (word == word.toUpperCase()) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');

    final prefix = linePrefixes[shortName.toUpperCase()];
    return prefix != null ? '$prefix $formattedName' : formattedName;
  }

  static String getLineName(String shortName, String fallback) {
    return lineNames[shortName.toUpperCase()] ?? fallback;
  }
}