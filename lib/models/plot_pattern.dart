/// Spôsob, akým pero obrázok vyplní („pattern“ plotra).
///
/// Obrázok sa dá prejsť rôznymi smermi – vodorovné riadky sú len jedna z
/// možností. Každý pattern má inú cenu: čím menej zdvihov pera a čím kratšia
/// dráha, tým rýchlejšie je kresba hotová.
///
/// * [horizontal] – vodorovné riadky (klasická ihličková tlačiareň, pôvodné
///   správanie),
/// * [vertical] – zvislé stĺpce (hodí sa na obrázky s výraznými zvislými
///   líniami),
/// * [diagonal] – šrafovanie pod 45° (prirodzenejší vzhľad pre fotky),
/// * [crossHatch] – dva priechody pod 45° a −45° (najtmavšia kresba, ale
///   dvojnásobok dráhy),
/// * [dots] – bodková matica: pero pri každom bode klesne a zdvihne sa
///   (najviac zdvihov, hodí sa na riedke predlohy),
/// * [zigzag] – **vlna**: riadky sú pospájané do jednej dlhej čiary, pero
///   takmer nezastavuje (najdlhšie ťahy pri vypĺňaní),
/// * [spiral] – špirála / kotúč: jedna čiara sa točí od okraja do stredu,
/// * [contour] – **obrys**: pero nekreslí výplň, ale obíde hrany tvarov, takže
///   obrázok naozaj „nakreslí“ (skica, dlhé línie po obvode),
/// * [auto] – pattern sa vyberie až pri generovaní podľa obsahu obrázka
///   (`ImageStrokeGenerator` ohodnotí všetkých kandidátov).
enum PlotPattern {
  /// Automatická voľba najlacnejšieho patternu pre konkrétny obrázok.
  auto(
    label: 'Auto',
    description: 'Picks the cheapest pattern for this image',
  ),

  /// Vodorovné riadky – pôvodné správanie generátora.
  horizontal(
    label: 'Horizontal',
    description: 'Horizontal scanlines, serpentine order',
  ),

  /// Zvislé stĺpce.
  vertical(
    label: 'Vertical',
    description: 'Vertical columns, serpentine order',
  ),

  /// Šrafovanie pod 45° (zľava dole doprava hore).
  diagonal(
    label: 'Diagonal',
    description: 'Hatching at 45°',
  ),

  /// Krížové šrafovanie – dva priechody (45° a −45°).
  crossHatch(
    label: 'Cross-hatch',
    description: 'Two 45° passes (darkest, twice the path)',
  ),

  /// Bodková matica – pero pri každom bode klesne a zdvihne sa.
  dots(
    label: 'Dots',
    description: 'Pen taps a short dot at every ink point',
  ),

  /// Vlna – riadky pospájané do jednej dlhej čiary (najmenej zdvihov).
  zigzag(
    label: 'Wave',
    description: 'Rows joined into one long zigzag (longest lines)',
  ),

  /// Špirála – jedna čiara sa točí od okraja kresby do stredu.
  spiral(
    label: 'Spiral',
    description: 'One coil from the outer edge inwards',
  ),

  /// Obrys – pero obíde hrany tvarov; kresba vyzerá ako skica.
  contour(
    label: 'Outline',
    description: 'Traces the shape edges – the robot draws the picture',
  );

  const PlotPattern({required this.label, required this.description});

  /// Krátky popis pre UI (`Horizontal`, `Cross-hatch`).
  final String label;

  /// Jednoriadkové vysvetlenie pre UI.
  final String description;

  /// `true`, ak ide o automatickú voľbu (pattern sa určí až pri generovaní).
  bool get isAutomatic => this == PlotPattern.auto;

  /// `true`, ak pattern kreslí bodky namiesto súvislých línií.
  bool get isDotPattern => this == PlotPattern.dots;

  /// `true`, ak pattern nekreslí výplň, ale len obrys tvarov (skica).
  bool get isOutline => this == PlotPattern.contour;

  /// `true`, ak pattern spája body do dlhých súvislých čiar (málo zdvihov).
  ///
  /// Používa to UI na vysvetlenie, prečo je pattern rýchly a prečo sa hodí
  /// nastaviť väčší zdvih pera (pero sa zdvihne len zriedka).
  bool get usesLongLines =>
      this == PlotPattern.zigzag ||
      this == PlotPattern.spiral ||
      this == PlotPattern.contour;

  /// `true`, ak sa pattern môže vybrať v režime `auto`.
  ///
  /// `auto` hľadá najlacnejší spôsob vyplnenia, preto do neho nepatrí
  /// [contour] (obrys nie je výplň) ani [spiral] (je to umelecký priechod).
  bool get isAutoCandidate =>
      !isAutomatic && this != PlotPattern.contour && this != PlotPattern.spiral;

  /// Nájde pattern podľa [name]; neznámy (alebo chýbajúci) vstup = [horizontal]
  /// (rovnaké správanie ako pred zavedením patternov).
  static PlotPattern fromName(String? name) => values.firstWhere(
        (pattern) => pattern.name == name,
        orElse: () => PlotPattern.horizontal,
      );
}

/// Predvolený pattern generátora – vodorovné riadky ako predtým.
const PlotPattern kDefaultPlotPattern = PlotPattern.horizontal;
