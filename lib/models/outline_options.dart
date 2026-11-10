import 'package:flutter/foundation.dart';

/// Poradie, v akom pero obrysové ťahy (*Outline* / *Sketch*) prejde.
///
/// Obrázok s textom má na papieri stovky drobných obrysov. Poradie rozhoduje
/// o tom, koľko pero prejde so zdvihnutým perom – a práve prejazdy „tam a hneď
/// späť“ controller odmieta (`Cannot transition! ... collinear and in opposite
/// directions`). Preto sa obrysy dajú zoradiť tak, aby pero vždy pokračoval
/// tým najbližším.
enum OutlineOrder {
  /// Presne v poradí, v akom generátor hrany našiel (zhora dole).
  asFound('As found'),

  /// Pero vždy pokračuje obrysom, ktorý začína najbližšie k miestu, kde práve
  /// stojí – prejazdy sú krátke a nevedú cez celú kresbu.
  nearest('Nearest'),

  /// Ako [nearest], ale otvorený obrys sa smie začať aj z druhého konca, takže
  /// pero nemusí prejsť okolo celého útvaru, aby ho začalo kresliť.
  ///
  /// Uzavretý obrys (krúžok, písmeno `O`) je z oboch koncov totožný – tam
  /// rozhoduje [OutlineOptions.rotateStart].
  nearestFlipped('Nearest + flip');

  const OutlineOrder(this.label);

  /// Krátky popis pre chip v UI.
  final String label;

  /// Jednoriadkové vysvetlenie pre UI.
  String get description => switch (this) {
        OutlineOrder.asFound =>
          'Strokes stay in the order the edges were found (top-down)',
        OutlineOrder.nearest =>
          'Each stroke continues with the closest one – short traverses',
        OutlineOrder.nearestFlipped =>
          'Closest stroke, drawn from whichever end is nearer',
      };
}

/// Ako veľmi sa má obrys vyhladiť pred bodovaním.
///
/// Obrys z pixelových hrán je „schodisko“ – každý pixel pridá odbočenie o 90°.
/// Vyhladenie (Douglas–Peucker) z neho spraví rovné úseky, takže robot nemá
/// tisíce krátkych segmentov, na ktorých musí zastavovať.
enum OutlineSmoothing {
  /// Presne po pixelových hranách (najvernejšie, ale najviac bodov).
  off('Off'),

  /// Predvolené správanie patternu – *Sketch* vyhladzuje, *Outline* nie.
  auto('Auto'),

  /// Vyhladí aj *Outline*: tolerancia `max(pen width, 2 px)`.
  ///
  /// Hodí sa na naskenované predlohy s roztrasenými hranami – kresba je
  /// pokojnejšia a bodov je rádovo menej.
  strong('Strong');

  const OutlineSmoothing(this.label);

  /// Krátky popis pre chip v UI.
  final String label;

  /// Jednoriadkové vysvetlenie pre UI.
  String get description => switch (this) {
        OutlineSmoothing.off => 'Follows the pixel edges exactly',
        OutlineSmoothing.auto =>
          'Sketch smooths the staircase, Outline keeps it',
        OutlineSmoothing.strong =>
          'Rounds even the Outline – far fewer points',
      };
}

/// Nastavenia obrysových patternov (*Outline* = `PlotPattern.contour`,
/// *Sketch* = `PlotPattern.sketch`).
///
/// Platia pre obidva patterny – mení sa len to, čo si používateľ zvolí. Keď
/// ostane všetko na predvolených hodnotách, *Outline* kreslí presne po
/// pixelových hranách a *Sketch* si drží vlastný robot-safe krok
/// (`ImageStrokeGenerator.sketchStepMmFor`).
@immutable
class OutlineOptions {
  /// Krok bodov v mm; `0` = automaticky podľa patternu.
  ///
  /// * `Outline`: `pointSpacingMm` (presne po pixelových hranách),
  /// * `Sketch`: `sketchStepMmFor(...)` (nikdy pod
  ///   `ImageStrokeGenerator.minSketchStepMm`).
  ///
  /// Vlastná hodnota prepne obrys na robot-safe bodovanie s **tetivou** aspoň
  /// [stepMm] (`ImageStrokeGenerator._resamplePolyline`) – aj pre *Outline*.
  /// Pod `minSketchStepMm` sa hodnota nezoženie, aby controller nedostal
  /// segment, ktorý nevie prejsť.
  final double stepMm;

  /// Najkratší detail v mm, ktorý sa ešte kreslí; `0` = všetko.
  ///
  /// Obrys menší ako jedna stopa pera je len „štuch“ do papiera – pero klesne,
  /// posunie sa o pár desatín milimetra a zdvihne sa. Také detaily sa dajú
  /// vyhodiť skôr, než sa pošlú robotovi.
  final double minDetailMm;

  /// Vyhladenie obrysu pred bodovaním.
  final OutlineSmoothing smoothing;

  /// Poradie, v akom pero obrysy prejde.
  final OutlineOrder order;

  /// `true` = uzavretý obrys sa začne v bode najbližšom k prostrediu pera.
  ///
  /// Namiesto „prejdi na začiatok obrysu a kresli“ pero pokračuje presne tam,
  /// kde stojí – prejazd je krátky a nevedie späť po vlastnej čiare (presne to
  /// hlási `Cannot transition!`).
  final bool rotateStart;

  const OutlineOptions({
    this.stepMm = 0,
    this.minDetailMm = 0,
    this.smoothing = OutlineSmoothing.auto,
    this.order = OutlineOrder.nearest,
    this.rotateStart = true,
  });

  /// Predvolené nastavenia – to, čo sa osvedčilo pri obrázkoch s textom.
  static const OutlineOptions defaults = OutlineOptions();

  /// `true`, ak sú nastavenia nezmenené (UI potom nič nezvýrazňuje).
  bool get isDefault => this == defaults;

  /// `true`, ak si používateľ zvolil vlastný krok bodov.
  bool get hasCustomStep => stepMm > 0;

  OutlineOptions copyWith({
    double? stepMm,
    double? minDetailMm,
    OutlineSmoothing? smoothing,
    OutlineOrder? order,
    bool? rotateStart,
  }) =>
      OutlineOptions(
        stepMm: stepMm ?? this.stepMm,
        minDetailMm: minDetailMm ?? this.minDetailMm,
        smoothing: smoothing ?? this.smoothing,
        order: order ?? this.order,
        rotateStart: rotateStart ?? this.rotateStart,
      );

  @override
  bool operator ==(Object other) =>
      other is OutlineOptions &&
      other.stepMm == stepMm &&
      other.minDetailMm == minDetailMm &&
      other.smoothing == smoothing &&
      other.order == order &&
      other.rotateStart == rotateStart;

  @override
  int get hashCode =>
      Object.hash(stepMm, minDetailMm, smoothing, order, rotateStart);

  @override
  String toString() => 'OutlineOptions(stepMm: $stepMm, '
      'minDetailMm: $minDetailMm, smoothing: ${smoothing.name}, '
      'order: ${order.name}, rotateStart: $rotateStart)';
}
