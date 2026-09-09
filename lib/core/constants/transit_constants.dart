class TransitConstants {
  // Pre-declared strict mapping for all RapidKL Lines
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

  // Helper method to format raw station names from GTFS data
  static String formatStationName(String name, String shortName) {
    // Case-insensitive removal of redundant transit keywords
    String cleanName = name
        .replaceAll(RegExp(r'\b(lrt|mrt|mrl|monorail|brt|station)\b', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final formattedName = cleanName.split(' ').map((word) {
      if (word.isEmpty) return '';
      // Preserve all-caps acronyms (e.g. KL, KLCC, TRX, USJ)
      if (word == word.toUpperCase()) return word;
      // Capitalize normal words
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');

    final prefix = linePrefixes[shortName.toUpperCase()];
    return prefix != null ? '$prefix $formattedName' : formattedName;
  }

  // Helper method to get the official line name
  static String getLineName(String shortName, String fallback) {
    return lineNames[shortName.toUpperCase()] ?? fallback;
  }
}