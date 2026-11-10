/// Odkiaľ pero začne kresliť obrázok.
///
/// Obrázok je na papieri vždy rovnako orientovaný (hore je hore) – nastavenie
/// mení len **poradie**, v akom pero línie prechádza:
///
/// * [top] – prvá línia je horná, pero postupuje nadol (pôvodné správanie),
/// * [bottom] – prvá línia je dolná, pero postupuje nahor.
///
/// Zrkadlenie obrázka rieši `PlotTransform` (Mirror vertically); toto
/// nastavenie je len o poradí ťahov – hodí sa, keď pero stojí pri spodnom
/// okraji papiera a nechceme, aby na začiatku prešlo celý hárok.
enum PlotStartSide {
  /// Začína sa hornou líniou a ide sa nadol.
  top(
    label: 'Top',
    description: 'First line is the top one, the pen works downwards',
  ),

  /// Začína sa dolnou líniou a ide sa nahor.
  bottom(
    label: 'Bottom',
    description: 'First line is the bottom one, the pen works upwards',
  );

  const PlotStartSide({required this.label, required this.description});

  /// Krátky popis pre UI (`Top`, `Bottom`).
  final String label;

  /// Jednoriadkové vysvetlenie pre UI.
  final String description;

  /// `true`, ak sa kreslí od spodnej línie nahor.
  bool get isBottom => this == PlotStartSide.bottom;

  /// Nájde stranu podľa [name]; neznámy (alebo chýbajúci) vstup = [top]
  /// (rovnaké správanie ako pred zavedením nastavenia).
  static PlotStartSide fromName(String? name) => values.firstWhere(
        (side) => side.name == name,
        orElse: () => PlotStartSide.top,
      );
}

/// Predvolené poradie kresby – zhora nadol ako predtým.
const PlotStartSide kDefaultPlotStartSide = PlotStartSide.top;
