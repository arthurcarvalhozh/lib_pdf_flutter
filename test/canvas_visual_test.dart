// Comparação visual da etapa 4: cada caso é pintado duas vezes, pelo Flutter
// (PNG, a "mesma pintura na tela") e pela lib (PDF do mesmo tamanho). O
// `tool/visual_diff.py` rasteriza os PDFs com Poppler e Ghostscript e compara
// pixel a pixel com os PNGs.
//
// Os arquivos ficam em build/visual/. Para conferir:
//   flutter test test/canvas_visual_test.dart && python3 tool/visual_diff.py
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lib_pdf/lib_pdf.dart';

import 'support/pdf_validator.dart';
import 'support/shadows.dart';
import 'support/test_fonts.dart';

/// Pixels por ponto da imagem de referência (o script renderiza o PDF em
/// 72 × [_ratio] dpi).
const _ratio = 2.0;

void main() {
  late List<PdfFont> fonts;
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    fonts = await loadTestFonts();
  });

  final cases = <String, (Size, Widget Function())>{
    'formas': (const Size(320, 200), () => CustomPaint(painter: _Painter(_shapes))),
    'transformacoes_e_recortes': (const Size(320, 200), () => CustomPaint(painter: _Painter(_transformsAndClips))),
    'opacidade_e_mistura': (const Size(320, 200), _opacityAndBlend),
    'gradientes': (const Size(320, 240), _gradients),
    'sombras': (const Size(320, 200), _shadows),
    'imagens': (const Size(320, 160), _images),
    'camadas': (const Size(320, 200), _layers),
  };

  for (final MapEntry(key: name, value: (size, build)) in cases.entries) {
    testWidgets('caso visual: $name', (tester) async {
      await withShadows(() async {
        final png = await _reference(tester, size, build());
        final result = (await tester.runAsync(
          () => PdfDocument(
            fonts: fonts,
            creationDate: DateTime.utc(2026),
            pages: [
              MultiPage(
                format: PdfPageFormat(size.width, size.height),
                margin: EdgeInsets.zero,
                children: [SizedBox.fromSize(size: size, child: build())],
              ),
            ],
          ).buildWithReport(),
        ))!;
        expect(result.pageCount, 1);
        expect(validatePdf(result.bytes), isEmpty);
        Directory('build/visual').createSync(recursive: true);
        File('build/visual/$name.png').writeAsBytesSync(png);
        File('build/visual/$name.pdf').writeAsBytesSync(result.bytes);
        File('build/visual/$name.txt')
            .writeAsStringSync([for (final e in result.warnings.entries) '${e.value}x ${e.key}'].join('\n'));
      });
    });
  }
}

/// A pintura do Flutter, num `RepaintBoundary` do tamanho da página.
Future<List<int>> _reference(WidgetTester tester, Size size, Widget child) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(size: size),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: DefaultTextStyle(
          style: const TextStyle(fontFamily: 'Montserrat', fontSize: 10, color: Color(0xFF000000)),
          child: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: key,
              child: SizedBox.fromSize(size: size, child: child),
            ),
          ),
        ),
      ),
    ),
  );
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: _ratio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }))!;
}

// ------------------------------------------------------------------ casos

void _shapes(Canvas canvas, Size size) {
  final fill = Paint()..color = const Color(0xFF1E88E5);
  Paint stroke(Color color, double width, {StrokeCap cap = StrokeCap.butt, StrokeJoin join = StrokeJoin.miter}) =>
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = cap
        ..strokeJoin = join;

  canvas.drawRect(const Rect.fromLTWH(10, 10, 50, 35), fill);
  canvas.drawRRect(
    RRect.fromLTRBR(70, 10, 130, 45, const Radius.circular(10)),
    Paint()..color = const Color(0xFFE53935),
  );
  canvas.drawDRRect(
    RRect.fromLTRBR(140, 10, 200, 45, const Radius.circular(12)),
    RRect.fromLTRBR(150, 18, 190, 37, const Radius.circular(5)),
    Paint()..color = const Color(0xFF43A047),
  );
  canvas.drawOval(const Rect.fromLTWH(210, 10, 50, 35), Paint()..color = const Color(0xFFFB8C00));
  canvas.drawCircle(const Offset(290, 27), 17, stroke(const Color(0xFF8E24AA), 4));

  canvas.drawArc(const Rect.fromLTWH(10, 55, 45, 45), -math.pi / 2, math.pi * 1.4, true, fill);
  canvas.drawArc(
    const Rect.fromLTWH(65, 55, 45, 45),
    0,
    math.pi * 1.25,
    false,
    stroke(const Color(0xFF000000), 5, cap: StrokeCap.round),
  );
  for (final (i, cap) in StrokeCap.values.indexed) {
    canvas.drawLine(
      Offset(125, 62 + i * 14.0),
      Offset(175, 62 + i * 14.0),
      stroke(const Color(0xFF3949AB), 8, cap: cap),
    );
  }
  for (final (i, join) in StrokeJoin.values.indexed) {
    final x = 190 + i * 42.0;
    canvas.drawPath(
      Path()
        ..moveTo(x, 98)
        ..lineTo(x + 15, 60)
        ..lineTo(x + 30, 98),
      stroke(const Color(0xFF00897B), 7, join: join),
    );
  }

  canvas.drawPath(
    Path()
      ..fillType = PathFillType.evenOdd
      ..addOval(const Rect.fromLTWH(10, 115, 70, 70))
      ..addRect(const Rect.fromLTWH(30, 135, 30, 30)),
    Paint()..color = const Color(0xFF6D4C41),
  );
  canvas.drawPath(
    Path()
      ..moveTo(95, 180)
      ..cubicTo(110, 100, 150, 220, 175, 125)
      ..quadraticBezierTo(185, 100, 200, 140),
    stroke(const Color(0xFFD81B60), 3),
  );
  canvas.drawPoints(ui.PointMode.points, [
    for (var i = 0; i < 6; i++) Offset(215 + i * 10.0, 120),
  ], stroke(const Color(0xFF000000), 6, cap: StrokeCap.round));
  canvas.drawPoints(ui.PointMode.polygon, const [
    Offset(215, 140),
    Offset(235, 180),
    Offset(255, 140),
    Offset(275, 180),
  ], stroke(const Color(0xFF5E35B1), 2));
  canvas.drawRSuperellipse(
    RSuperellipse.fromLTRBR(280, 135, 315, 190, const Radius.circular(14)),
    Paint()..color = const Color(0xFF00ACC1),
  );
}

void _transformsAndClips(Canvas canvas, Size size) {
  final paint = Paint()..color = const Color(0xFF1E88E5);
  for (var i = 0; i < 4; i++) {
    canvas.save();
    canvas.translate(40 + i * 70.0, 45);
    canvas.rotate(i * math.pi / 8);
    canvas.scale(1 + i * 0.15, 1);
    if (i == 3) canvas.skew(0.3, 0);
    canvas.drawRect(const Rect.fromLTWH(-20, -20, 40, 40), paint);
    canvas.restore();
  }

  final stripes = Paint()..color = const Color(0xFFE53935);
  void stripesIn(Rect area) {
    for (var x = area.left - area.height; x < area.right; x += 8) {
      canvas.drawLine(Offset(x, area.bottom), Offset(x + area.height, area.top), stripes..strokeWidth = 3);
    }
  }

  canvas.save();
  canvas.clipRect(const Rect.fromLTWH(10, 100, 70, 80));
  stripesIn(const Rect.fromLTWH(0, 90, 100, 100));
  canvas.restore();

  canvas.save();
  canvas.clipRRect(RRect.fromLTRBR(90, 100, 160, 180, const Radius.circular(20)));
  stripesIn(const Rect.fromLTWH(80, 90, 100, 100));
  canvas.restore();

  canvas.save();
  final star = Path();
  for (var i = 0; i < 10; i++) {
    final r = i.isEven ? 40.0 : 17.0;
    final a = -math.pi / 2 + i * math.pi / 5;
    final p = Offset(210 + r * math.cos(a), 140 + r * math.sin(a));
    i == 0 ? star.moveTo(p.dx, p.dy) : star.lineTo(p.dx, p.dy);
  }
  star.close();
  canvas.clipPath(star);
  stripesIn(const Rect.fromLTWH(165, 95, 90, 90));
  canvas.restore();

  canvas.save();
  canvas.clipRect(const Rect.fromLTWH(270, 115, 30, 30), clipOp: ui.ClipOp.difference);
  canvas.drawRect(const Rect.fromLTWH(260, 100, 50, 80), Paint()..color = const Color(0xFF43A047));
  canvas.restore();
}

Widget _opacityAndBlend() => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Padding(
      padding: const EdgeInsets.all(10),
      child: Opacity(
        opacity: 0.45,
        child: Container(
          width: 300,
          padding: const EdgeInsets.all(8),
          color: const Color(0xFF1E88E5),
          child: const Text(
            'Opacity: texto sobre fundo, compostos antes do alfa',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFFFFEB3B)),
          ),
        ),
      ),
    ),
    SizedBox(
      height: 125,
      width: 320,
      child: CustomPaint(
        painter: _Painter((canvas, size) {
          // saveLayer com alfa: os dois quadrados se cobrem sem transparecer.
          canvas.saveLayer(null, Paint()..color = const Color(0x80000000));
          canvas.drawRect(const Rect.fromLTWH(10, 10, 60, 60), Paint()..color = const Color(0xFFE53935));
          canvas.drawRect(const Rect.fromLTWH(40, 40, 60, 60), Paint()..color = const Color(0xFF43A047));
          canvas.restore();
          // Mistura: multiplicar e tela.
          canvas.drawCircle(const Offset(160, 50), 35, Paint()..color = const Color(0xFFFFEB3B));
          canvas.drawCircle(
            const Offset(195, 50),
            35,
            Paint()
              ..color = const Color(0xFF00BCD4)
              ..blendMode = BlendMode.multiply,
          );
          canvas.drawRect(const Rect.fromLTWH(240, 15, 70, 70), Paint()..color = const Color(0xFF3949AB));
          canvas.drawCircle(
            const Offset(275, 85),
            30,
            Paint()
              ..color = const Color(0xFFFF7043)
              ..blendMode = BlendMode.screen,
          );
          canvas.drawRect(const Rect.fromLTWH(120, 95, 190, 25), Paint()..color = const Color(0x66000000));
        }),
      ),
    ),
  ],
);

Widget _gradients() {
  BoxDecoration box(Gradient g, {double radius = 8}) =>
      BoxDecoration(gradient: g, borderRadius: BorderRadius.circular(radius));
  const red = Color(0xFFE53935), blue = Color(0xFF1E88E5), yellow = Color(0xFFFDD835), green = Color(0xFF43A047);
  return Padding(
    padding: const EdgeInsets.all(10),
    child: Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Container(height: 60, decoration: box(const LinearGradient(colors: [red, blue]))),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                height: 60,
                decoration: box(
                  const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [red, yellow, green, blue],
                    stops: [0.1, 0.5, 0.5, 0.9],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                height: 60,
                decoration: box(const LinearGradient(colors: [yellow, red], transform: GradientRotation(math.pi / 3))),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Container(
                height: 70,
                decoration: box(const RadialGradient(colors: [yellow, red, blue], stops: [0, 0.6, 1])),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                height: 70,
                decoration: box(
                  const RadialGradient(
                    colors: [Color(0xFFFFFFFF), blue],
                    focal: Alignment(-0.4, -0.4),
                    focalRadius: 0.05,
                  ),
                  radius: 35,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                height: 70,
                decoration: box(const SweepGradient(colors: [red, yellow, green, blue, red])),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 70,
          child: CustomPaint(
            size: Size.infinite,
            painter: _Painter((canvas, size) {
              final rect = Rect.fromLTWH(0, 0, size.width / 2 - 5, size.height);
              canvas.drawOval(rect, Paint()..shader = const LinearGradient(colors: [green, blue]).createShader(rect));
              final line = Rect.fromLTWH(size.width / 2 + 5, 0, size.width / 2 - 5, size.height);
              canvas.drawPath(
                Path()
                  ..moveTo(line.left + 5, line.bottom - 5)
                  ..lineTo(line.center.dx, line.top + 5)
                  ..lineTo(line.right - 5, line.bottom - 5),
                Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = 8
                  ..shader = const LinearGradient(colors: [red, yellow]).createShader(line),
              );
              canvas.drawRect(
                Rect.fromLTWH(line.left + 60, line.top + 40, 80, 25),
                Paint()
                  ..shader = const LinearGradient(colors: [Color(0xFF000000), Color(0x00000000)]).createShader(line),
              );
            }),
          ),
        ),
      ],
    ),
  );
}

// Card e Material tiram a fonte do tema: sem este Theme, usariam Roboto, que
// não está registrada.
Widget _shadows() => Theme(
  data: ThemeData(fontFamily: 'Montserrat'),
  child: _shadowCards(),
);

Widget _shadowCards() => Padding(
  padding: const EdgeInsets.all(16),
  child: Column(
    children: [
      Row(
        children: [
          Expanded(
            child: Container(
              height: 60,
              decoration: BoxDecoration(
                color: const Color(0xFFFFFFFF),
                borderRadius: BorderRadius.circular(8),
                boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 8, offset: Offset(0, 4))],
              ),
              child: const Center(child: Text('BoxShadow')),
            ),
          ),
          const SizedBox(width: 20),
          const Expanded(
            child: Card(
              elevation: 6,
              margin: EdgeInsets.zero,
              child: SizedBox(height: 60, child: Center(child: Text('Card elevation 6'))),
            ),
          ),
        ],
      ),
      const SizedBox(height: 24),
      Row(
        children: [
          const PhysicalModel(
            color: Color(0xFFFDD835),
            elevation: 10,
            shape: BoxShape.circle,
            child: SizedBox(width: 60, height: 60),
          ),
          const SizedBox(width: 30),
          Material(
            elevation: 2,
            borderRadius: BorderRadius.circular(20),
            color: const Color(0xFF1E88E5),
            child: const SizedBox(
              width: 150,
              height: 40,
              child: Center(
                child: Text('Material', style: TextStyle(color: Color(0xFFFFFFFF))),
              ),
            ),
          ),
        ],
      ),
    ],
  ),
);

ui.Image? _checkerImage;
ui.Image _checker() => _checkerImage ??= () {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  for (var y = 0; y < 40; y += 5) {
    for (var x = 0; x < 40; x += 5) {
      final edge = x == 0 || y == 0 || x == 35 || y == 35;
      canvas.drawRect(
        Rect.fromLTWH(x.toDouble(), y.toDouble(), 5, 5),
        Paint()
          ..color = edge
              ? const Color(0xFF3949AB)
              : ((x + y) % 10 == 0 ? const Color(0xFF000000) : const Color(0xFFFDD835)),
      );
    }
  }
  final picture = recorder.endRecording();
  final image = picture.toImageSync(40, 40);
  picture.dispose();
  return image;
}();

Widget _images() {
  final image = _checker();
  return Padding(
    padding: const EdgeInsets.all(10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 60,
          height: 60,
          child: RawImage(image: image, fit: BoxFit.fill),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 60,
          height: 60,
          child: RawImage(image: image, opacity: const AlwaysStoppedAnimation(0.4)),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 60,
          height: 60,
          child: RawImage(image: image, color: const Color(0xFFE53935), colorBlendMode: BlendMode.modulate),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 90,
          height: 140,
          child: CustomPaint(
            painter: _Painter((canvas, size) {
              canvas.drawImageNine(
                image,
                const Rect.fromLTRB(5, 5, 35, 35),
                Rect.fromLTWH(0, 0, size.width, 70),
                Paint(),
              );
              canvas.drawImageRect(
                image,
                const Rect.fromLTWH(10, 10, 20, 20),
                const Rect.fromLTWH(0, 80, 60, 60),
                Paint(),
              );
            }),
          ),
        ),
      ],
    ),
  );
}

Widget _layers() => Padding(
  padding: const EdgeInsets.all(10),
  child: Column(
    children: [
      Row(
        children: [
          ColorFiltered(
            colorFilter: const ColorFilter.matrix([
              0.2126, 0.7152, 0.0722, 0, 0, //
              0.2126, 0.7152, 0.0722, 0, 0,
              0.2126, 0.7152, 0.0722, 0, 0,
              0, 0, 0, 1, 0,
            ]),
            child: Container(
              width: 140,
              height: 70,
              color: const Color(0xFFE53935),
              alignment: Alignment.center,
              child: const Text('em tons de cinza', style: TextStyle(color: Color(0xFFFDD835))),
            ),
          ),
          const SizedBox(width: 20),
          ShaderMask(
            shaderCallback: (r) => const LinearGradient(colors: [Color(0xFF000000), Color(0x00000000)]).createShader(r),
            child: Container(width: 140, height: 70, color: const Color(0xFF1E88E5)),
          ),
        ],
      ),
      const SizedBox(height: 20),
      Row(
        children: [
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 3, sigmaY: 3),
            child: Container(width: 100, height: 60, color: const Color(0xFF43A047)),
          ),
          const SizedBox(width: 30),
          ClipOval(child: Container(width: 80, height: 60, color: const Color(0xFFFB8C00))),
          const SizedBox(width: 30),
          Transform.rotate(angle: 0.3, child: Container(width: 50, height: 50, color: const Color(0xFF8E24AA))),
        ],
      ),
    ],
  ),
);

class _Painter extends CustomPainter {
  _Painter(this.onPaint);
  final void Function(Canvas canvas, Size size) onPaint;

  @override
  void paint(Canvas canvas, Size size) => onPaint(canvas, size);

  @override
  bool shouldRepaint(_Painter oldDelegate) => true;
}
