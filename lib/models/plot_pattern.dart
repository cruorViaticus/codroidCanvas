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
/// * [antiDiagonal] – to isté zrkadlovo, teda pod −45°,
/// * [crossHatch] – dva priechody pod 45° a −45° (najtmavšia kresba, ale
///   dvojnásobok dráhy),
/// * [tripleHatch] – tri priechody (0°, 45°, −45°) – najhustejšia výplň,
/// * [dots] – bodková matica: pero pri každom bode klesne a zdvihne sa
///   (najviac zdvihov, hodí sa na riedke predlohy),
/// * [zigzag] – **vlna**: riadky sú pospájané do jednej dlhej čiary, pero
///   takmer nezastavuje (najdlhšie ťahy pri vypĺňaní),
/// * [spiral] – špirála / kotúč: jedna čiara sa točí od okraja do stredu,
/// * [rings] – sústredné kružnice od stredu k okraju,
/// * [contour] – **obrys**: pero nekreslí výplň, ale obíde hrany tvarov, takže
///   obrázok naozaj „nakreslí“ (skica, dlhé línie po obvode),
/// * [sketch] – **skica pre detail**: tie isté hrany ako [contour], ale body
///   ukladá v kroku, ktorý robot zvládne (nikdy bližšie ako
///   `ImageStrokeGenerator.minSketchStepMm`) – pre obrázky s textom a jemnými
///   líniami, kde by `contour` vyrobil tisíce bodov tesne pri sebe,
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

  /// Šrafovanie pod −45° (zľava hore doprava dole) – zrkadlo [diagonal].
  ///
  /// Hodí sa na obrázky, ktorým sedí opačný sklon šrafovania (šrafy tak
  /// idú „po“ tvare namiesto „proti“ nemu).
  antiDiagonal(
    label: 'Diagonal 2',
    description: 'Hatching at −45° (mirror of Diagonal)',
  ),

  /// Krížové šrafovanie – dva priechody (45° a −45°).
  crossHatch(
    label: 'Cross-hatch',
    description: 'Two 45° passes (darkest, twice the path)',
  ),

  /// Trojité šrafovanie – vodorovne, +45° a −45°.
  ///
  /// Najhustejšia (a najpomalšia) výplň: tri priechody prekryjú takmer celý
  /// papier, takže aj svetlé polotóny vyzerajú plné.
  tripleHatch(
    label: 'Triple hatch',
    description: 'Three passes (0°, +45°, −45°) – densest fill',
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
  ),

  /// Skica pre drobné detaily – obrys s krokom bodov, ktorý robot zvládne.
  ///
  /// Rovnaké hrany ako [contour], ale pero sa nezasekne na pixelových
  /// schodíkoch: čiara sa najprv zjednoduší a potom sa boduje tak, že
  /// **vzdušná** vzdialenosť dvoch susedných bodov je vždy aspoň
  /// `ImageStrokeGenerator.minSketchStepMm`. Controller totiž nevie plynulo
  /// prejsť veľmi krátky úsek (zastaví na ňom alebo odmietne prechod), preto
  /// `contour` na obrázkoch s textom vyrobí dráhu, ktorú robot nezvládne.
  sketch(
    label: 'Sketch',
    description: 'Outline with robot-safe point spacing – for text and detail',
  ),

  /// Sústredné kružnice – pero krúži od stredu kresby k okraju.
  rings(
    label: 'Rings',
    description: 'Concentric circles from the centre outwards',
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
  bool get isOutline =>
      this == PlotPattern.contour || this == PlotPattern.sketch;

  /// `true`, ak pattern spája body do dlhých súvislých čiar (málo zdvihov).
  ///
  /// Používa to UI na vysvetlenie, prečo je pattern rýchly a prečo sa hodí
  /// nastaviť väčší zdvih pera (pero sa zdvihne len zriedka).
  bool get usesLongLines =>
      this == PlotPattern.zigzag ||
      this == PlotPattern.spiral ||
      this == PlotPattern.rings ||
      this == PlotPattern.contour ||
      this == PlotPattern.sketch;

  /// `true`, ak sa pattern môže vybrať v režime `auto`.
  ///
  /// `auto` hľadá najlacnejší spôsob vyplnenia, preto do neho nepatrí
  /// [contour] ani [sketch] (obrys nie je výplň), [spiral] ani [rings]
  /// (umelecké priechody).
  bool get isAutoCandidate =>
      !isAutomatic &&
      this != PlotPattern.contour &&
      this != PlotPattern.sketch &&
      this != PlotPattern.spiral &&
      this != PlotPattern.rings;

  /// Nájde pattern podľa [name]; neznámy (alebo chýbajúci) vstup = [horizontal]
  /// (rovnaké správanie ako pred zavedením patternov).
  static PlotPattern fromName(String? name) => values.firstWhere(
        (pattern) => pattern.name == name,
        orElse: () => PlotPattern.horizontal,
      );
}

/// Predvolený pattern generátora – vodorovné riadky ako predtým.
const PlotPattern kDefaultPlotPattern = PlotPattern.horizontal;
