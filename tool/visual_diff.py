#!/usr/bin/env python3
"""Compara os PDFs da lib com a pintura do Flutter (etapa 4).

O teste `test/canvas_visual_test.dart` grava, para cada caso, `<caso>.png`
(a pintura do Flutter, 2 pixels por ponto) e `<caso>.pdf` (a mesma pintura
pela lib) em build/visual/. Este script rasteriza cada PDF com os leitores
disponíveis (Poppler e Ghostscript), na mesma resolução, e conta os pixels
que diferem.

Um pixel só conta como diferente se nenhum vizinho a até 1 pixel dele, na
imagem do leitor, chega perto da cor do Flutter: isso perdoa a suavização das
bordas, que cada rasterizador faz do seu jeito, e acusa formas, cores ou
posições erradas.

Uso: python3 tool/visual_diff.py [pasta] [--limite 0.5]
Sai com código 1 se algum caso passar do limite (em % de pixels).
Grava build/visual/diff_<caso>_<leitor>.png com os pixels acusados em vermelho.
"""
import argparse
import os
import shutil
import subprocess
import sys
import tempfile

from PIL import Image, ImageChops, ImageFilter

DPI = 144  # 2 pixels por ponto, como o PNG de referência
TOLERANCE = 48  # diferença máxima por canal, de 0 a 255


def render_poppler(pdf, out_png):
    base = out_png[:-4]
    subprocess.run(['pdftoppm', '-r', str(DPI), '-png', '-singlefile', pdf, base], check=True)


def render_ghostscript(pdf, out_png):
    subprocess.run(
        ['gs', '-q', '-dNOPAUSE', '-dBATCH', '-dSAFER', '-sDEVICE=png16m', f'-r{DPI}',
         '-dTextAlphaBits=4', '-dGraphicsAlphaBits=4', f'-sOutputFile={out_png}', pdf],
        check=True,
    )


RENDERERS = {'poppler': ('pdftoppm', render_poppler), 'ghostscript': ('gs', render_ghostscript)}


def load_reference(path):
    ref = Image.open(path).convert('RGBA')
    white = Image.new('RGBA', ref.size, (255, 255, 255, 255))
    return Image.alpha_composite(white, ref).convert('RGB')


def compare(ref, out):
    w, h = min(ref.width, out.width), min(ref.height, out.height)
    ref, out = ref.crop((0, 0, w, h)), out.crop((0, 0, w, h))
    low = out.filter(ImageFilter.MinFilter(3))
    high = out.filter(ImageFilter.MaxFilter(3))
    # Quanto o Flutter fica fora da faixa [mínimo, máximo] da vizinhança.
    above = ImageChops.subtract(ref, high)
    below = ImageChops.subtract(low, ref)
    worst = ImageChops.lighter(above, below)
    r, g, b = worst.split()
    worst = ImageChops.lighter(ImageChops.lighter(r, g), b)
    bad = worst.point(lambda v: 255 if v > TOLERANCE else 0)
    count = bad.histogram()[255]
    marked = ref.copy()
    marked.paste((255, 0, 0), mask=bad)
    return 100.0 * count / (w * h), marked


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('folder', nargs='?', default='build/visual')
    parser.add_argument('--limite', type=float, default=0.5, help='%% máximo de pixels diferentes por caso')
    args = parser.parse_args()

    renderers = {name: fn for name, (exe, fn) in RENDERERS.items() if shutil.which(exe)}
    if not renderers:
        sys.exit('nenhum leitor encontrado (pdftoppm ou gs)')
    cases = sorted(f[:-4] for f in os.listdir(args.folder) if f.endswith('.pdf'))
    if not cases:
        sys.exit(f'nenhum PDF em {args.folder}: rode antes o flutter test test/canvas_visual_test.dart')

    failed = False
    print(f'{"caso":28} ' + ' '.join(f'{n:>12}' for n in renderers) + '   (% de pixels diferentes)')
    with tempfile.TemporaryDirectory() as tmp:
        for case in cases:
            ref = load_reference(os.path.join(args.folder, case + '.png'))
            cells = []
            for name, render in renderers.items():
                out_png = os.path.join(tmp, f'{case}_{name}.png')
                render(os.path.join(args.folder, case + '.pdf'), out_png)
                pct, marked = compare(ref, Image.open(out_png).convert('RGB'))
                marked.save(os.path.join(args.folder, f'diff_{case}_{name}.png'))
                shutil.copy(out_png, os.path.join(args.folder, f'render_{case}_{name}.png'))
                flag = ' ' if pct <= args.limite else '!'
                failed |= pct > args.limite
                cells.append(f'{pct:11.3f}{flag}')
            print(f'{case:28} ' + ' '.join(cells))
    if failed:
        print(f'\nCasos marcados com ! passaram de {args.limite} %. Veja os diff_*.png em {args.folder}.')
        sys.exit(1)


if __name__ == '__main__':
    main()
