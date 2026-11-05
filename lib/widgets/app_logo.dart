import 'package:flutter/material.dart';

/// Farby ikony – zladené s témou aplikácie (indigo AppBar).
const Color kIconIndigoLight = Color(0xFF3949AB); // indigo 600
const Color kIconIndigoDark = Color(0xFF1A237E); // indigo 900
const Color kIconRobot = Color(0xFFF7F9FF); // "biela" konštrukcia robota
const Color kIconJoint = Color(0xFF1A237E); // tmavé kĺby
const Color kIconPen = Color(0xFFFFC23C); // jantárové pero
const Color kIconInk = Color(0xFF7DE3F4); // tyrkysová vykreslená čiara

/// Vykreslí ikonu plotra – priemyselné rameno Codroid s perom nad papierom.
///
/// Kreslí sa v normalizovaných súradniciach (0..1), takže ten istý kód slúži
/// pre launcher ikony (`tool/generate_app_icons.dart`) aj pre logo priamo
/// v aplikácii ([AppLogo]).
///
/// * [background] – áno = indigo štvorcové pozadie, nie = priehľadné (AppBar).
/// * [rounded] – zaoblené rohy (klasické launcher ikony, favicon).
/// * [contentScale] – aká časť plochy je vyplnená kresbou (maskable ikony
///   potrebujú menší obsah kvôli orezaniu systémovou maskou).
void paintCodroidIcon(
  Canvas canvas,
  Size size, {
  bool background = true,
  bool rounded = true,
  double contentScale = 0.94,
}) {
  final shortest = size.shortestSide;
  final rect = Offset.zero & size;

  canvas.save();

  if (background) {
    if (rounded) {
      canvas.clipRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(shortest * 0.22)),
      );
    }
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [kIconIndigoLight, kIconIndigoDark],
        ).createShader(rect),
    );
    // jemný svetelný odlesk v ľavom hornom rohu
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.6, -0.75),
          radius: 1.15,
          colors: [Color(0x2EFFFFFF), Color(0x00FFFFFF)],
        ).createShader(rect),
    );
  }

  // Robot sa kreslí v jednotkovom štvorci – vycentrujeme a oškálujeme.
  canvas.translate(size.width / 2, size.height / 2);
  canvas.scale(shortest * contentScale);
  canvas.translate(-0.5, -0.5);
  _paintRobot(canvas);

  canvas.restore();
}

/// Samotná kresba robota (jednotkové súradnice 0..1).
void _paintRobot(Canvas c) {
  final fill = Paint()
    ..color = kIconRobot
    ..style = PaintingStyle.fill;
  final joint = Paint()
    ..color = kIconJoint
    ..style = PaintingStyle.fill;
  final bar = Paint()
    ..color = kIconRobot
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  // --- papier / podložka (mierne natočený list) ---
  c.save();
  c.translate(0.50, 0.815);
  c.rotate(-0.055);
  final paper = RRect.fromRectAndRadius(
    Rect.fromCenter(center: Offset.zero, width: 0.86, height: 0.15),
    const Radius.circular(0.03),
  );
  c.drawRRect(paper, Paint()..color = const Color(0x30FFFFFF));
  c.drawRRect(
    paper,
    Paint()
      ..color = const Color(0x59FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.012,
  );
  c.restore();

  // --- vykreslená čiara na papieri ---
  c.drawPath(
    Path()
      ..moveTo(0.655, 0.782)
      ..cubicTo(0.710, 0.750, 0.775, 0.800, 0.860, 0.755),
    Paint()
      ..color = kIconInk
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.024
      ..strokeCap = StrokeCap.round,
  );

  // --- základňa ramena ---
  c.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: const Offset(0.285, 0.735),
        width: 0.30,
        height: 0.088,
      ),
      const Radius.circular(0.03),
    ),
    fill,
  );

  // stĺpik ramena
  bar.strokeWidth = 0.125;
  c.drawLine(const Offset(0.285, 0.715), const Offset(0.285, 0.600), bar);

  // rameno 1 (rameno -> lakeť)
  bar.strokeWidth = 0.105;
  c.drawLine(const Offset(0.285, 0.600), const Offset(0.465, 0.305), bar);

  // kĺb v ramene
  c.drawCircle(const Offset(0.285, 0.608), 0.031, joint);

  // kĺb v lakti
  c.drawCircle(const Offset(0.465, 0.305), 0.078, fill);
  c.drawCircle(const Offset(0.465, 0.305), 0.036, joint);

  // rameno 2 (lakeť -> zápästie)
  bar.strokeWidth = 0.088;
  c.drawLine(const Offset(0.465, 0.305), const Offset(0.760, 0.395), bar);

  // zápästie
  c.drawCircle(const Offset(0.760, 0.395), 0.066, fill);
  c.drawCircle(const Offset(0.760, 0.395), 0.030, joint);

  // --- pero v uchopovači ---
  final pen = Paint()
    ..color = kIconPen
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  pen.strokeWidth = 0.058;
  c.drawLine(const Offset(0.731, 0.459), const Offset(0.624, 0.678), pen);
  // hrot pera (dotýka sa papiera)
  pen
    ..color = const Color(0xFF263238)
    ..strokeWidth = 0.038;
  c.drawLine(const Offset(0.624, 0.678), const Offset(0.600, 0.748), pen);
}

/// Logo plotra pre použitie priamo v UI (AppBar, hlavičky, splash…).
class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    this.size = 28,
    this.background = false,
    this.rounded = true,
    this.contentScale = 1.0,
    this.semanticLabel = 'Codroid pen plotter',
  });

  /// Veľkosť (štvorec) v logických pixeloch.
  final double size;

  /// Vykresliť indigo pozadie (launcher-style) alebo len samotného robota.
  final bool background;

  /// Zaoblené rohy pozadia.
  final bool rounded;

  /// Mierka obsahu voči ploche.
  final double contentScale;

  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      image: true,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          size: Size.square(size),
          painter: _CodroidIconPainter(
            background: background,
            rounded: rounded,
            contentScale: contentScale,
          ),
        ),
      ),
    );
  }
}

class _CodroidIconPainter extends CustomPainter {
  const _CodroidIconPainter({
    required this.background,
    required this.rounded,
    required this.contentScale,
  });

  final bool background;
  final bool rounded;
  final double contentScale;

  @override
  void paint(Canvas canvas, Size size) => paintCodroidIcon(
        canvas,
        size,
        background: background,
        rounded: rounded,
        contentScale: contentScale,
      );

  @override
  bool shouldRepaint(covariant _CodroidIconPainter oldDelegate) =>
      oldDelegate.background != background ||
      oldDelegate.rounded != rounded ||
      oldDelegate.contentScale != contentScale;
}

/// Titulok `AppBar` s logom plotra – jednotné brandovanie všetkých obrazoviek.
class AppBarTitle extends StatelessWidget {
  const AppBarTitle(this.text, {super.key, this.logoSize = 30});

  final String text;
  final double logoSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppLogo(size: logoSize),
        const SizedBox(width: 10),
        Flexible(
          child: Text(text, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}
