import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lib_pdf/lib_pdf.dart';
import 'package:lib_pdf/src/document/pdf_writer.dart';

import 'support/pdf_validator.dart';

void main() {
  group('codificação de valores', () {
    test('nomes escapam espaço, delimitadores, # e não-ASCII', () {
      expect(PdfWriter.name('Montserrat-Bold'), '/Montserrat-Bold');
      expect(PdfWriter.name('A B#(x)'), '/A#20B#23#28x#29');
      expect(PdfWriter.name('Ação'), '/A#C3#A7#C3#A3o');
    });

    test('strings ASCII escapam parênteses e barra; o resto vai em UTF-16BE', () {
      expect(PdfWriter.encode(const PdfString(r'a (b) \c')), r'(a \(b\) \\c)');
      expect(PdfWriter.encode(const PdfString('Válvula')), '<FEFF005600e1006c00760075006c0061>');
      expect(PdfWriter.encode(const PdfString('linha\nnova')), startsWith('<FEFF'));
    });

    test('números com até 4 casas, sem zeros sobrando', () {
      expect(PdfWriter.num(1.0), '1');
      expect(PdfWriter.num(-2.5), '-2.5');
      expect(PdfWriter.num(0.123456), '0.1235');
      expect(PdfWriter.num(595.28), '595.28');
      expect(PdfWriter.num(-0.00001), '0');
      expect(PdfWriter.num(double.nan), '0');
    });

    test('dicionários, arrays, referências e booleanos', () {
      expect(
        PdfWriter.encode(<String, Object>{
          'Type': const PdfName('Page'),
          'Kids': [const PdfRef(3), 1.5, true],
        }),
        '<< /Type /Page /Kids [3 0 R 1.5 true] >>',
      );
    });

    test('datas no formato PDF, com fuso', () {
      expect(PdfWriter.date(DateTime.utc(2026, 11, 27, 13, 14, 5)).value, '(D:20261127131405Z)');
      final local = DateTime(2026, 1, 2, 3, 4, 5);
      expect(PdfWriter.date(local).value, matches(RegExp(r"^\(D:20260102030405([+-]\d\d'\d\d'|Z)\)$")));
    });
  });

  group('arquivo', () {
    Uint8List minimal() {
      final w = PdfWriter();
      final catalog = w.reserve();
      final pages = w.reserve();
      final contents = w.addStream({}, latin1.encode('q 0 0 1 rg 10 10 100 100 re f Q\n'));
      final page = w.add(<String, Object>{
        'Type': const PdfName('Page'),
        'Parent': pages,
        'MediaBox': [0, 0, 595.28, 841.89],
        'Contents': contents,
        'Resources': <String, Object>{},
      });
      w.set(pages, <String, Object>{
        'Type': const PdfName('Pages'),
        'Kids': [page],
        'Count': 1,
      });
      w.set(catalog, <String, Object>{'Type': const PdfName('Catalog'), 'Pages': pages});
      final info = w.add(<String, Object>{'Title': const PdfString('Teste')});
      return w.build(root: catalog, info: info);
    }

    test('sai bem formado', () {
      expect(validatePdf(minimal()), isEmpty);
    });

    test('o mesmo conteúdo gera os mesmos bytes, com o mesmo /ID', () {
      expect(minimal(), minimal());
    });

    test('objeto reservado e nunca preenchido é erro', () {
      final w = PdfWriter();
      final catalog = w.reserve();
      w.reserve();
      expect(() => w.build(root: catalog), throwsStateError);
    });

    test('o validador acusa /Length errado e xref deslocada', () {
      final good = latin1.decode(minimal());
      // Mesmo número de dígitos, para não deslocar a xref.
      final badLength = good.replaceFirstMapped(
        RegExp(r'/Length (\d+)'),
        (m) => '/Length ${'1'.padLeft(m[1]!.length, '0')}',
      );
      expect(validatePdf(latin1.encode(badLength)), contains(contains('/Length')));
      final shifted = good.replaceFirst('%PDF-1.7\n', '%PDF-1.7\n\n');
      expect(validatePdf(latin1.encode(shifted)), isNotEmpty);
    });
  });

  group('formatos de página', () {
    test('A4, Carta e Legal em pontos', () {
      expect(PdfPageFormat.a4.width, closeTo(595.28, 0.01));
      expect(PdfPageFormat.letter, const PdfPageFormat(612, 792));
      expect(PdfPageFormat.legal, const PdfPageFormat(612, 1008));
    });

    test('milímetros viram pontos', () {
      final a4 = PdfPageFormat.millimeters(210, 297);
      expect(a4.width, closeTo(PdfPageFormat.a4.width, 0.01));
      expect(a4.height, closeTo(PdfPageFormat.a4.height, 0.01));
    });

    test('retrato e paisagem', () {
      expect(PdfPageFormat.a4.landscape, const PdfPageFormat(841.89, 595.28));
      expect(PdfPageFormat.a4.landscape.portrait, PdfPageFormat.a4);
      expect(PdfPageFormat.a4.portrait, PdfPageFormat.a4);
    });
  });
}
