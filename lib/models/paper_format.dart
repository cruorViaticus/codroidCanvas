/// Formáty papiera, na ktoré vie plotter kresliť.
///
/// Súradnicový systém je v celej appke rovnaký ako pri S Pen canvase: canvas
/// (aj náhľad) je **na výšku**, takže `x` = 0 je ľavý okraj, `y` = 0 je horný
/// okraj. Robot potom kreslí takto:
///
/// * **X robota** = zvislá os canvasu (`y`) → vždy **dlhšia** strana papiera,
/// * **Y robota** = vodorovná os canvasu (`x`) → kratšia strana papiera.
///
/// Papier sa preto nikdy neotáča – pri každom formáte leží dlhšia strana
/// pozdĺž osi X.
enum PaperFormat {
  /// A4 – 210 × 297 mm (predvolený formát).
  a4(label: 'A4', longSideMm: 297, shortSideMm: 210),

  /// A3 – 297 × 420 mm.
  a3(label: 'A3', longSideMm: 420, shortSideMm: 297),

  /// A5 – 148 × 210 mm.
  a5(label: 'A5', longSideMm: 210, shortSideMm: 148),

  /// Fotopapier 10 × 15 cm – 100 × 150 mm.
  photo10x15(label: '10 × 15', longSideMm: 150, shortSideMm: 100);

  const PaperFormat({
    required this.label,
    required this.longSideMm,
    required this.shortSideMm,
  });

  /// Krátky popis pre UI (`A4`, `10 × 15`).
  final String label;

  /// Dlhšia strana papiera v mm – leží v smere **X** robota.
  final double longSideMm;

  /// Kratšia strana papiera v mm – leží v smere **Y** robota.
  final double shortSideMm;

  /// Šírka papiera v mm = kratšia strana (vodorovná os canvasu).
  double get widthMm => shortSideMm;

  /// Výška papiera v mm = dlhšia strana (zvislá os canvasu).
  double get heightMm => longSideMm;

  /// Pomer strán papiera na výšku – pre canvas a náhľad
  /// (`widthMm / heightMm`, pre A4 = `210 / 297`).
  double get aspectRatio => widthMm / heightMm;

  /// Popis rozmerov pre UI (`210 × 297 mm`).
  String get sizeLabel =>
      '${widthMm.toStringAsFixed(0)} × ${heightMm.toStringAsFixed(0)} mm';

  /// `true`, ak ide o fotopapier 10 × 15 cm.
  bool get isPhotoPaper => this == PaperFormat.photo10x15;

  /// Nájde formát podľa [name]; neznámy (alebo chýbajúci) vstup = [a4].
  ///
  /// Používa sa pri načítaní z `SharedPreferences`, aby staršie uložené
  /// nastavenia (bez formátu papiera) fungovali ako doteraz.
  static PaperFormat fromName(String? name) => values.firstWhere(
        (format) => format.name == name,
        orElse: () => PaperFormat.a4,
      );
}

/// Predvolený formát papiera (A4) – používajú ho služby, ktoré formát nedostanú.
const PaperFormat kDefaultPaperFormat = PaperFormat.a4;
