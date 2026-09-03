// Short "what to bring" list for a destination, derived from its tags
// and region rather than requiring a new backend field. Shared by the
// destination detail screen (rendered as chips) and the create-itinerary
// dialog (seeded into the notes so the same info follows the traveler
// into their plan).

import '../models/models.dart';

class Essential {
  final String emoji;
  final String label;
  const Essential(this.emoji, this.label);
}

// A tiny baseline every trip in Cameroon benefits from; everything else
// is layered on top based on what the destination itself is like, so
// e.g. a market gets "cash", a hike gets "sturdy shoes", the coast gets
// "swimwear", without any one destination getting an overwhelming list.
const _baseline = <Essential>[
  Essential('💧', 'Water'),
  Essential('💵', 'Cash (FCFA)'),
  Essential('🆔', 'ID'),
  Essential('🔋', 'Phone + charger'),
];

const _tagRules = <String, List<Essential>>{
  'market': [
    Essential('🛍️', 'Reusable bag'),
    Essential('🎒', 'Zipped bag (crowds)'),
  ],
  'shopping': [
    Essential('🛍️', 'Reusable bag'),
  ],
  'food': [
    Essential('🧻', 'Wet wipes'),
  ],
  'beach': [
    Essential('🩱', 'Swimwear'),
    Essential('🧴', 'Sunscreen'),
    Essential('🕶️', 'Sunglasses'),
    Essential('🩴', 'Sandals'),
  ],
  'mountain': [
    Essential('🥾', 'Sturdy shoes'),
    Essential('🧥', 'Warm layer'),
    Essential('🎒', 'Daypack'),
  ],
  'hiking': [
    Essential('🥾', 'Sturdy shoes'),
    Essential('🧢', 'Hat'),
    Essential('🎒', 'Daypack'),
  ],
  'waterfall': [
    Essential('🥾', 'Non-slip shoes'),
    Essential('🧥', 'Light rain jacket'),
  ],
  'nature': [
    Essential('🦟', 'Insect repellent'),
    Essential('🧴', 'Sunscreen'),
  ],
  'wildlife': [
    Essential('🦟', 'Insect repellent'),
    Essential('🔭', 'Binoculars (optional)'),
  ],
  'safari': [
    Essential('🦟', 'Insect repellent'),
    Essential('🧢', 'Hat'),
    Essential('🔭', 'Binoculars (optional)'),
  ],
  'culture': [
    Essential('👗', 'Modest clothing'),
  ],
  'religious': [
    Essential('👗', 'Modest clothing'),
    Essential('🧦', 'Easy-off shoes'),
  ],
  'museum': [
    Essential('📷', 'Camera'),
  ],
  'city': [
    Essential('👟', 'Comfortable shoes'),
  ],
  'nightlife': [
    Essential('🚕', 'Taxi app / number'),
  ],
  'family': [
    Essential('🧴', 'Sunscreen'),
    Essential('🍪', 'Snacks'),
  ],
};

// Coarse region → climate hint. Cameroon's north (Adamawa/Nord/
// Extrême-Nord) is hot/dry; the coast (Littoral/Sud-Ouest) is humid; the
// west highlands (Ouest/Nord-Ouest) get chilly at night. These are
// suggestions, not weather forecasts — the traveler still checks
// conditions themselves.
List<Essential> _regionExtras(String region) {
  final r = region.toLowerCase();
  if (r.contains('nord') || r.contains('north') || r.contains('adamawa')) {
    return const [
      Essential('🧢', 'Sun hat'),
      Essential('🧴', 'Sunscreen'),
    ];
  }
  if (r.contains('littoral') ||
      r.contains('sud-ouest') ||
      r.contains('south-west') ||
      r.contains('coast')) {
    return const [
      Essential('☂️', 'Compact umbrella'),
      Essential('🦟', 'Insect repellent'),
    ];
  }
  if (r.contains('ouest') || r.contains('west') || r.contains('bamenda')) {
    return const [
      Essential('🧥', 'Warm layer (evenings)'),
    ];
  }
  return const [];
}

List<Essential> essentialsForDestination(Destination d) {
  final seen = <String>{};
  final result = <Essential>[];

  void add(Essential e) {
    // De-duplicate by label so overlapping tag rules (e.g. "beach" and
    // "nature" both suggesting sunscreen) don't render the same chip
    // twice next to itself.
    if (seen.add(e.label)) result.add(e);
  }

  for (final e in _baseline) {
    add(e);
  }
  for (final tag in d.tags) {
    final extras = _tagRules[tag.toLowerCase()];
    if (extras != null) {
      for (final e in extras) {
        add(e);
      }
    }
  }
  for (final e in _regionExtras(d.region)) {
    add(e);
  }
  // Cap at 8 so the chip strip stays visually compact — the top items
  // (baseline first, then tag-driven) are the most relevant anyway.
  if (result.length > 8) return result.sublist(0, 8);
  return result;
}

// Plain-text version for pre-filling an itinerary's notes field. Kept
// short and scannable (single line of comma-separated items) so it fits
// naturally inside a multi-line notes textbox without dominating it.
String essentialsAsNoteText(List<Essential> items) {
  if (items.isEmpty) return '';
  final joined = items.map((e) => '${e.emoji} ${e.label}').join(', ');
  return 'What to bring: $joined';
}
