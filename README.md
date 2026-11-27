# lib_pdf

> **O que é:** lib de PDF para Flutter: o relatório é escrito com widgets comuns do Flutter, e a lib desenha esses widgets direto em PDF, em vetor e com texto real
> **Para que serve:** substituir o `package:pdf` na geração dos relatórios do diagnox e do valvulas. O visualizador dos apps (`PdfPreview` do `printing`) continua o mesmo
> **Quando consultar:** para usar a lib, rodar os testes ou medir o desempenho
> **Status:** em desenvolvimento, ainda não usada nos apps. Andamento por etapa na seção 7.1 do [plano](docs/plano-de-desenvolvimento.md).

## Uso

```dart
import 'package:lib_pdf/lib_pdf.dart';

final bytes = await PdfDocument(
  fonts: [
    await PdfFont.asset('assets/fonts/Montserrat-Regular.ttf', family: 'Montserrat'),
    await PdfFont.asset('assets/fonts/Montserrat-Bold.ttf', family: 'Montserrat', weight: FontWeight.bold),
  ],
  title: 'Relatório',
  creator: 'diagnox 3.7.3',
  pages: [
    MultiPage(children: [
      const Text('Relatório do sensor de NOx', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      Table(border: TableBorder.all(), children: [...]),
      KeepTogether(child: MeuCardDeGrafico(...)), // fl_chart, CustomPaint, o que a tela já usa
    ]),
  ],
).build();
```

- Os `children` são widgets do Flutter: `Text`, `Table`, `Row`, `Container`, `ClipRRect`, `Opacity`, `CustomPaint`, gráficos do `fl_chart`, `QrImageView`...
- A lib quebra a página entre linhas de texto e de tabela, nunca no meio delas. `KeepTogether` mantém um bloco inteiro na mesma página.
- Cada família e peso usado num `TextStyle` precisa estar registrado em `fonts` e também declarado no `pubspec.yaml` do app, porque quem mede o texto é o Flutter.
- Os metadados (`title`, `author`, `subject`, `keywords`, `creator`, `creationDate`) aparecem nas propriedades do arquivo. `PdfPageFormat` tem A3, A4, A5, Carta e Legal, `.landscape`, `.portrait` e `PdfPageFormat.millimeters(largura, altura)`; cada `MultiPage` pode ter o seu.
- Com a mesma `creationDate`, o mesmo documento gera sempre os mesmos bytes.
- Gradientes lineares e radiais, opacidade (como grupo, igual à camada do Flutter), modos de mistura, recortes e transformações saem em vetor. Sombras, desfoques, filtros de cor e gradientes de varredura saem como imagem só naquele trecho.
- `buildWithReport()` devolve, além dos bytes, os tempos e os avisos: o que não saiu em vetor ou não saiu fiel ao Flutter, como uma sombra rasterizada. Em modo debug, `build()` escreve esses avisos no console.

O que ainda falta (cabeçalho e rodapé por página, subset de fontes, SVG, o tema do app dentro do PDF) está nas etapas do plano.

## Desenvolvimento

O Flutter está fixado em 3.47.1 (`.fvmrc`), a mesma versão do diagnox e do valvulas.

```
fvm flutter test                    # testes do pacote; PDFs em build/pdfs/ e build/visual/
python3 tool/visual_diff.py         # compara build/visual/ com a pintura do Flutter (precisa de pdftoppm ou gs e do Pillow)
cd example && fvm flutter test      # gera example/build/exemplo/relatorio_exemplo.pdf
benchmark/run_android.sh            # mede num aparelho Android conectado (instala e desinstala o app de exemplo)
```

`test/flutter_contract_test.dart` trava os pontos em que a lib depende de detalhes internos do Flutter. Se ele falhar depois de atualizar o Flutter, a lib precisa de ajuste antes de a versão nova ir para os apps.

| Pasta | Conteúdo |
|---|---|
| `lib/` | O pacote. API pública em `lib/lib_pdf.dart` |
| `example/` | App de exemplo com um relatório no molde do relatório de NOx, também usado para medir |
| `benchmark/` | Script de medida em aparelho |
| `tool/` | Comparação visual dos PDFs com a pintura do Flutter |
| `docs/` | [Plano](docs/plano-de-desenvolvimento.md), [resultado da prova de conceito](docs/prova-de-conceito.md) e [linha de base](docs/linha-de-base.md) |
| `poc/` | Prova de conceito da etapa 1, mantida só como referência |
