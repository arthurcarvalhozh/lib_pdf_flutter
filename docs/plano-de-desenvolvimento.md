# Plano de desenvolvimento: lib de PDF própria para o diagnox e o ACTUALL (valvulas)

> **O que é:** a análise de como o `package:pdf` (com o `package:printing`) é usado hoje nos dois apps e o plano, dividido em etapas, para escrever uma lib de PDF nossa que o substitua
> **Para que serve:** alinhar a abordagem, a ordem de trabalho e as decisões em aberto antes de escrever código, e acompanhar o andamento etapa por etapa
> **Quando consultar:** antes de começar cada etapa (seção 7), e sempre que uma pergunta da seção 11 for respondida
> **Status:** 27/11/2026. Análise feita (seção 2); pilares definidos pelo usuário (seção 3); abordagem B confirmada pelo usuário (seção 4.2); etapa 1 concluída com a decisão de seguir com B ([prova-de-conceito.md](prova-de-conceito.md)); etapa 2 pronta localmente, falta o CI rodar no GitHub (tabela da seção 7.1).

## 1. Contexto

Os dois apps geram o relatório de teste em PDF com o `package:pdf` e mostram, salvam e compartilham o arquivo com o `package:printing` e o `share_plus`. A lib nova se apoia em três pilares (seção 3):

1. **Personalização.** Muitos widgets do Flutter não existem na lib atual, e o time contorna a lib para chegar ao layout que quer.
2. **Sintaxe.** Escrever o PDF deve ser igual a escrever uma tela em Flutter, sem precisar aprender uma API nova.
3. **Gráficos.** Hoje o gráfico do teste é capturado da tela como PNG e colado no PDF: é uma prática ruim e deixa a geração lenta. O gráfico deve ser desenhado direto no PDF, em vetor.

## 2. Como a lib atual é usada hoje

### 2.1 Inventário

| App | Arquivo | Linhas | O que faz |
|---|---|---|---|
| diagnox | `lib/src/core/services/pdf/relatorio_pdf_service_nox.dart` | 840 | Relatório do sensor de NOx |
| diagnox | `lib/src/core/services/pdf/relatorio_pdf_service_eficiencia.dart` | 1100 | Relatório de eficiência do catalisador (SCR) |
| diagnox | `lib/src/core/services/pdf/relatorio_pdf_service_bomba_arla.dart` | 1001 | Relatório da bomba de ARLA |
| diagnox | `lib/src/core/services/pdf/relatorio_pdf_service_testes_especiais.dart` | 997 | Relatório dos testes por rotinas (inclui temperatura) |
| diagnox | `lib/src/core/services/pdf/pdf_viewer_service.dart` | 342 | Escolhe o serviço, gera, mostra o `PdfPreview`, salva e compartilha |
| valvulas | `lib/src/features/app/relatorios/services/pdf/relatorio_pdf_service_generico.dart` | 1158 | Relatório único (EBS/ECA), com fallback de gráfico nativo |
| valvulas | `lib/src/features/app/relatorios/services/pdf/sections/relatorio_graph_pdf_section.dart` | 89 | Seção "Gráficos" montada com as capturas |
| valvulas | `lib/src/features/app/relatorios/services/pdf/relatorio_pdf_viewer_service.dart` | 551 | Gera, mostra o `PdfPreview`, salva e compartilha, com diagnóstico de erro |
| valvulas | `lib/src/features/app/relatorios/presentation/ui/pages/relatorio_detail_page.dart` | — | Captura e fatia as imagens dos gráficos (seção 2.4.3) |

Ao todo são cerca de 6.000 linhas nos arquivos de PDF. Dependências envolvidas: `pdf`, `printing`, `share_plus`, `path_provider`, `qr_flutter` (QR do cabeçalho), `fl_chart` (gráficos da tela que viram imagem) e, no valvulas, `image` (para fatiar as capturas).

### 2.2 O fluxo de geração

**diagnox** (botão PDF em `relatorio_floating_buttons_widget.dart:49`):

1. `captureGraphImage()` tira uma foto do `RepaintBoundary` do gráfico com `pixelRatio: 3.0` e gera um PNG (`relatorio_detail_widget.dart:320`).
2. `PdfViewerService.generateAndShowPdf` escolhe o serviço pelo tipo de teste numa cadeia de `if`, com `late final dynamic pdfService` (`pdf_viewer_service.dart:66`), e passa a largura e a altura da tela.
3. O serviço busca a empresa num Cubit, lê o logo do cliente do disco e o logo do diagnox do `rootBundle`, gera o QR como PNG via `QrPainter.toImageData` e monta a árvore de widgets do `package:pdf`.
4. `pdf.save()` grava o arquivo no diretório temporário, e o `PdfPreview` do `printing` o mostra num `Dialog`.

**valvulas** (`_generatePdf` em `relatorio_detail_page.dart`):

1. Para cada card de gráfico: rola a tela até ele, espera dois frames e mais 180 ms, e captura o PNG (seção 2.4.3).
2. Decodifica cada PNG em Dart, reduz para 1.600 px de largura no release, fatia em pedaços e codifica de novo em PNG.
3. `RelatorioPdfServiceGenerico.generatePdf` carrega a Montserrat, o logo e o QR e monta o `MultiPage`. Sem capturas, cai no gráfico nativo do `package:pdf` com um aviso no papel.
4. Salva no temporário e mostra no `PdfPreview`.

### 2.3 Sintaxe de uso

#### 2.3.1 Como o código fica

Uma linha da tabela "Dados da empresa" no diagnox (`relatorio_pdf_service_nox.dart:494`):

```dart
Table(
  border: TableBorder.all(),
  children: [
    TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.all(2),
          child: Text('${textoDoApp('app:relatorios.pdf.address')}: ${empresa?.rua ?? textoDoApp('common:label.none')}', style: const TextStyle(fontSize: 12)),
        ),
        Padding(
          padding: const EdgeInsets.all(2),
          child: Text('${textoDoApp('app:relatorios.pdf.number')}: ${empresa?.numero ?? textoDoApp('common:label.none')}', style: const TextStyle(fontSize: 12)),
        ),
      ],
    ),
  ],
),
```

Cada célula repete `Padding` + `Text` + `TextStyle`, e cada seção repete a mesma faixa de título. Contagem nos quatro serviços do diagnox:

| Padrão | nox | eficiência | bomba ARLA | testes especiais |
|---|---|---|---|---|
| `Padding(` | 52 | 53 | 46 | 29 |
| `TextStyle(fontSize: 12` | 43 | 41 | 39 | 23 |
| `TableBorder.all()` | 12 | 21 | 15 | 12 |
| `PdfColor.fromInt(0xD9E1F3)` (faixa de título) | 4 | 5 | 4 | 3 |
| `'common:label.none'` | 18 | 13 | 15 | 15 |

#### 2.3.2 Problemas encontrados

- **Duplicação entre relatórios.** Cabeçalho (`_buildDescricao`), QR (`_qrCode`), dados da empresa (`_buildEmpresaInfo`), dados do veículo e `_savePdf` estão copiados nos quatro serviços do diagnox, com pequenas diferenças entre as cópias (por exemplo, o tamanho máximo do logo do cliente: 100×80 no NOx, 80×60 na eficiência).
- **"Tabela" feita de várias tabelas.** Uma seção é um `Container` com borda, contendo um `Column` de várias `Table` empilhadas, cada uma com larguras fixas mágicas para parecer alinhada com a de cima (`FixedColumnWidth(249.5)`, `FixedColumnWidth(55.4)` em `relatorio_pdf_service_eficiencia.dart:694` e `:822`). Não há célula que ocupe várias colunas (colspan).
- **Altura de linha estimada por contagem de caracteres.** O valvulas calcula a altura da linha contando caracteres por linha (`_labelColumnCharsPerLine = 22`, `_valueColumnCharsPerLine = 48`) em `_resolveInfoRowHeight` e `_estimateLineCount` (`relatorio_pdf_service_generico.dart:313`). O layout não mede o texto para o código.
- **Armadilha 1: a mesma instância em dois lugares sai em branco.** Um widget do `package:pdf` guarda a própria caixa de layout. Usar a mesma instância em três células fez as duas primeiras saírem vazias no papel, e o teste não pegou porque lia a árvore, não o resultado (comentário em `relatorio_pdf_service_bomba_arla.dart:829`, visto em bancada em 21/10/2026).
- **Armadilha 2: só o primeiro nível quebra página.** No `MultiPage`, só os filhos de primeiro nível que são `SpanningWidget` se dividem entre páginas. Uma `Table` dentro de um `Column` não quebra, e uma carga de 30 etapas lançava `TooManyPagesException`: o cliente ficava sem relatório (`relatorio_pdf_service_bomba_arla.dart:862`). O contorno é devolver listas de widgets e espalhar com `...` no `MultiPage`.
- **Armadilha 3: manter junto é o contrário.** Para impedir que o título fique numa página e o gráfico na outra, o valvulas embrulha a seção em `pw.Inseparable`. Aí a seção não pode passar de uma página, senão o `MultiPage` lança exceção, e por isso a altura dos gráficos é fixa em 240 pt (`relatorio_graph_pdf_section.dart`).
- **Limites defensivos espalhados.** O valvulas tem tetos para não estourar o motor: `_maxPages = 100`, `_maxExecutions = 24`, `_maxParametersPerExecution = 40`, `_maxCellChars = 240`, `_maxNativeGraphPoints = 160` e outros (`relatorio_pdf_service_generico.dart:24`).
- **Nomes que colidem com o Flutter.** O diagnox importa `package:pdf/widgets.dart` sem prefixo, então `Text`, `Table`, `Image` e `Container` são os do PDF e o arquivo não pode usar os do Flutter. O valvulas usa o prefixo `pw.` em tudo. As cores são outra API (`PdfColors.green200` em vez de `Colors.green.shade200`), e o mesmo código mistura cor sem alfa (`0xD9E1F3`) com cor ARGB (`0xFFE2E8F0`).
- **Lógica de dados misturada com layout.** Os serviços leem Cubits (`EmpresaCubit`, `HistoricoCubit`, `SessionCubit`) e calculam mínimo, máximo e média no meio da montagem das tabelas. Isso não é culpa da lib, mas uma lib com componentes de relatório prontos ajudaria a separar as duas coisas.

### 2.4 Como os gráficos chegam ao PDF hoje

#### 2.4.1 diagnox: NOx, eficiência (SCR) e bomba de ARLA — foto da tela

- Na tela, os gráficos são cards do `fl_chart` (`NoxGraphReport`, `CatalisadorGraphReport`, `BombaArlaGraphReport`) com fundo em SVG, título, valor atual e um `LineChart`: linha branca curva (`isCurved: true`, `barWidth: 2`), grade horizontal no intervalo configurado e, no card de tensão e corrente, **um segundo eixo Y** amarelo à direita, com a série secundária reescalada à mão para o eixo principal (`nox_grafico.dart`).
- Todos os tamanhos vêm do `MediaQuery`: o PNG muda de proporção conforme o aparelho.
- No PDF, a imagem entra com proporções diferentes em cada relatório:
  - NOx: `Image(MemoryImage(graphImage))` sem proporção definida (`relatorio_pdf_service_nox.dart:830`);
  - eficiência: `AspectRatio(aspectRatio: screenWidth / screenHeight * 2)` com `BoxFit.fill`, que **estica** a imagem (`relatorio_pdf_service_eficiencia.dart:909`);
  - bomba de ARLA: `AspectRatio(aspectRatio: screenWidth / screenHeight * 6)` com `BoxFit.fill` (`relatorio_pdf_service_bomba_arla.dart:725`).
- **Largura e altura estão trocadas na bomba de ARLA.** O `PdfViewerService` passa `(screenWidth, screenHeight)` (`pdf_viewer_service.dart:76`), mas o construtor de `RelatorioPdfServiceBombaArla` declara `(this.screenHeight, this.screenWidth)` (`relatorio_pdf_service_bomba_arla.dart:60`). O multiplicador `* 6` foi ajustado em cima desse valor trocado. O mesmo acontece com `RelatorioPdfServiceTestesEspeciais`, que porém não usa os dois campos.

#### 2.4.2 diagnox: testes especiais — já nativo, mas na unha

`_buildChartWidget` (`relatorio_pdf_service_testes_especiais.dart:616`) desenha o gráfico com `CustomPaint` e o `PdfGraphics` cru:

- origem do eixo Y **embaixo** (contrário do Flutter), então toda conta de posição é invertida à mão;
- rótulos do eixo Y feitos com um `Column` de cinco `Text` em `mainAxisAlignment.spaceBetween` e `fontSize: 5`, sem relação real com a escala;
- grade, borda, linha, área preenchida e o ponto final desenhados chamada a chamada (`moveTo`, `lineTo`, `strokePath`, `fillPath`);
- casas decimais decididas pela amplitude (`diff < 0.2 ? 2 : diff < 2 ? 1 : 0`);
- cards montados em linhas de três com `Expanded` e espaçadores vazios para completar a linha.

O resultado é vetorial e leve. Isso prova que o caminho nativo funciona; o problema é que não há componente de gráfico, só o canvas.

#### 2.4.3 valvulas — foto da tela, em pedaços

`relatorio_detail_page.dart:289` em diante:

1. Para cada card: `Scrollable.ensureVisible` (220 ms de animação), dois `endOfFrame` e mais 180 ms de espera. **Só as esperas fixas somam pelo menos 400 ms por card**, antes de qualquer captura.
2. `boundary.toImage` com tentativas decrescentes de `pixelRatio` (começa em até 3 no debug e até 1 no release, e desce até 0,45 se a captura falhar).
3. `_splitGraphImage`: decodifica o PNG com o `package:image`, reduz para 1.600 px no release, fatia em pedaços de proporção até 1,12 e codifica cada pedaço de novo em PNG.
4. No PDF, os pedaços entram em pares lado a lado, numa área de altura fixa de 240 pt com `BoxFit.contain` (`relatorio_graph_pdf_section.dart`). O `package:pdf` decodifica cada PNG mais uma vez para embuti-lo.

Quando não há captura, o relatório usa o `pw.Chart` do `package:pdf` (`relatorio_pdf_service_generico.dart:797`): `LineDataSet` azul fixo, cinco marcas por eixo, sem curva, sem área, reduzido a 160 pontos e **sem a série secundária** (`secondaryKey` do `RelatorioGraphConfig` é ignorado). Uma faixa no papel diz que são "gráficos nativos". O papel fica diferente da tela.

#### 2.4.4 Resumo dos problemas dos gráficos

- **Lento:** rolar, esperar, rasterizar, codificar, decodificar, fatiar, codificar de novo e decodificar mais uma vez no `package:pdf`.
- **Depende da tela:** o gráfico precisa estar montado e visível; a proporção muda com o aparelho; há parâmetros trocados ajustados com multiplicadores mágicos.
- **Qualidade:** imagem rasterizada (pixeliza no zoom e na impressão), esticada com `BoxFit.fill` em dois relatórios.
- **Tamanho do arquivo:** PNGs de até 1.600 px por pedaço, contra alguns KB de vetor.
- **Visual inconsistente:** quatro jeitos diferentes de pôr gráfico no papel (foto sem proporção, foto esticada, canvas na unha, `pw.Chart` genérico).

#### 2.4.5 O que o gráfico nativo precisa suportar (tirado das telas de hoje)

- Gráfico de linha com uma ou mais séries, X pelo índice da amostra.
- Linha reta ou curva, espessura e cor por série; área preenchida abaixo da linha; ponto no último valor.
- Eixo Y com `minY`, `maxY` e `interval` configuráveis (hoje vêm de `RelatorioGraphConfig` no valvulas e de `valorMinimoExibicao`/`valorMaximoExibicao` no diagnox), com escala automática quando não configurados.
- **Eixo Y secundário** com escala, intervalo, unidade e cor próprios (tensão × corrente).
- Grade horizontal no intervalo, linhas de eixo, rótulos com casas decimais configuráveis.
- Card em volta: título, valor atual com unidade, média, fundo colorido (no diagnox, o SVG do card).
- Séries longas sem precisar reduzir para 160 pontos (vetor aguenta milhares de pontos; redução, se houver, deve preservar picos).

### 2.5 Outros pontos observados

- **Fontes e idiomas.** O diagnox não carrega fonte no PDF e usa a Helvetica padrão do `package:pdf`. O valvulas carrega a Montserrat Regular e Bold (`_loadPdfTheme`, `relatorio_pdf_service_generico.dart:1076`). Os dois apps têm `zh-CN` entre os idiomas suportados, e nem a Helvetica padrão nem a Montserrat têm glifos chineses, então **o relatório em chinês provavelmente sai com o texto quebrado**. Não gerei um PDF em `zh-CN` para confirmar.
- **QR raster.** Os dois apps geram o QR como PNG de 100 px via `qr_flutter`. Um QR desenhado em vetor sai nítido em qualquer tamanho.
- **Preview, salvar e compartilhar** estão duplicados nos dois `*_viewer_service.dart`, com a mesma lógica de pasta de downloads e nome de arquivo sem repetição.
- **Plataformas.** O valvulas tem as pastas `web/`, `linux/` e `macos/`; o diagnox só `android/` e `ios/`. Falta confirmar se o PDF precisa ser gerado também no web (pergunta 6 da seção 11).

### 2.6 O que da tela não pode ser reaproveitado no PDF

Evidência para o pilar de personalização (seção 3.1). Hoje nada do que o time já construiu para as telas entra no PDF como está:

- **Gráficos do `fl_chart`:** viram foto (seção 2.4).
- **SVG** (fundo dos cards de gráfico do diagnox, via `flutter_svg`): só chega ao papel dentro da foto.
- **QR:** a tela usa o widget `QrImageView`; o PDF precisa rasterizar o QR à parte com o `QrPainter`.
- **Componentes e tema do app:** `RelatorioSection`, `AppTextStyles`, `AppTheme.getColor`, `Theme.of(context)` não existem no `package:pdf`. As cores e os estilos são redeclarados à mão em cada serviço.
- **Widgets do Flutter sem equivalente** precisam de contorno: tabela com colspan vira várias tabelas empilhadas, altura de linha é estimada por caracteres, quebra de página exige espalhar listas no primeiro nível (seção 2.3.2).

## 3. Os três pilares

Definidos pelo usuário em 27/11/2026. Cada pilar tem um critério de pronto verificável; as etapas da seção 7 dizem qual pilar cada uma atende.

### 3.1 Personalização

**O problema:** muitos widgets do Flutter não existem no `package:pdf`, e o time contorna a lib para conseguir o layout que quer (seções 2.3.2 e 2.6).

**Pronto quando:**

- os widgets do Flutter usados nas telas de relatório dos dois apps funcionam no PDF sem adaptação (o catálogo é levantado na etapa 8);
- componentes próprios do app (`StatelessWidget`, `StatefulWidget` no estado inicial) e o `Theme` do app funcionam no PDF;
- o que não tiver equivalente vetorial em PDF tem um comportamento definido e documentado (seção 4.4), em vez de quebrar;
- nenhuma das armadilhas da seção 2.3.2 existe: a mesma instância pode aparecer em vários lugares, qualquer bloco quebra página em qualquer profundidade, e um bloco maior que a página quebra em vez de lançar exceção.

### 3.2 Sintaxe

**O problema:** a lib atual tem nomes parecidos com os do Flutter, mas é outra API (`PdfColors`, `pw.`, `TableBorder.all()` sem os mesmos parâmetros), com comportamentos diferentes, e exige muito código repetido.

**Pronto quando:**

- o relatório é escrito com os widgets do próprio Flutter (`import 'package:flutter/material.dart'`), e não com uma cópia de nomes parecidos;
- o que a lib acrescenta é pouco e com cara de Flutter: o documento, a página, cabeçalho e rodapé, quebra de página, manter junto e o registro das fontes;
- quem sabe Flutter escreve um relatório lendo uma página de guia.

### 3.3 Gráficos

**O problema:** o gráfico é capturado da tela como PNG e colado no PDF. É lento, depende da tela estar aberta e do tamanho do aparelho, pixeliza e aumenta o arquivo (seção 2.4).

**Pronto quando:**

- nenhum gráfico chega ao PDF como imagem: linhas, áreas, grade e rótulos são vetor e texto;
- o gráfico é gerado a partir dos dados, sem a tela do relatório estar aberta e sem rolar nada;
- o que as telas de hoje mostram é suportado (seção 2.4.5), incluindo o eixo Y secundário;
- o mesmo widget de gráfico pode ser usado na tela e no PDF;
- a geração do relatório fica mais rápida que a linha de base medida na etapa 0.

## 4. Abordagem

### 4.1 Duas formas de construir a lib

**A. Recriar os widgets com os nomes do Flutter.** É o que o `package:pdf` faz: um motor de layout próprio e uma coleção de widgets que imitam os do Flutter. Mesmo feito com mais cuidado, cada widget precisa ser reescrito, então o catálogo vive atrás do Flutter, e os widgets do app, o `fl_chart`, o `flutter_svg` e o `qr_flutter` continuam de fora. Resolve pouco do pilar 3.1.

**B. Usar os widgets do Flutter de verdade e trocar só o destino do desenho.** O Flutter monta e mede a árvore de widgets fora da tela, como já faz para qualquer tela. Na hora de pintar, em vez de virar pixels, cada comando de desenho (retângulo, caminho, texto, imagem) é traduzido para um comando vetorial do PDF. O layout é o do Flutter, então qualquer widget que pinta pelo canvas funciona.

### 4.2 Decisão

**Abordagem B, confirmada pelo usuário em 27/11/2026**, porque é a única que atende os três pilares de uma vez: a sintaxe é o próprio Flutter, os widgets do app funcionam, e os gráficos são pintados em vetor a partir dos dados, sem foto.

O risco técnico é maior, e por isso a **etapa 1 é uma prova de conceito que decide** se B se sustenta antes de qualquer outra coisa. Saídas possíveis da etapa 1:

- **B se sustenta:** segue o plano como está.
- **B se sustenta, mas o texto pintado dentro de painters de terceiros fica ruim** (seção 4.4): segue B, e os gráficos nativos da etapa 9 passam a ser obrigatórios antes da migração.
- **Desviar a pintura do Flutter não é viável:** volta para a abordagem A, e o plano é refeito a partir da etapa 2.

### 4.3 Como a abordagem B funciona

```
árvore de widgets do relatório (Flutter puro)
  → montagem e layout fora da tela, na largura da página    (Flutter)
  → paginação: escolha dos pontos de quebra seguros          (lib)
  → pintura de cada página num canvas que escreve PDF        (lib)
  → escritor PDF: fontes embutidas, imagens, compressão      (lib)
  → bytes do arquivo
```

A árvore não aparece na tela e não precisa de rolagem: a lib cria a própria árvore de renderização, fornece `MediaQuery`, `Directionality`, `Theme` e `Localizations`, espera as imagens carregarem e pinta.

### 4.4 Desafios conhecidos da abordagem B

| Ponto | O que acontece | Como a lib trata |
|---|---|---|
| Texto de `Text` e `RichText` | O Flutter pinta o texto com um `Paragraph` fechado, que não deixa ler o conteúdo | A lib lê o texto direto do widget de texto já medido, mantém as quebras de linha do Flutter e escreve texto real no PDF (copiável e pesquisável) |
| Texto pintado dentro de um `CustomPainter` | Mesmo `Paragraph` fechado, e aqui não há widget de onde ler o texto (é o caso dos rótulos do `fl_chart`) | Plano B: só aquele trecho de texto é rasterizado em alta resolução. Os gráficos da lib (etapa 9) escrevem texto real |
| Caminhos (`Path`) | O `dart:ui` não expõe os segmentos de um `Path` | Retângulo, retângulo arredondado, oval, círculo, arco e linha saem exatos. `Path` livre sai como polilinha amostrada em passo fino, invisível na impressão. Os gráficos da lib escrevem as curvas exatas |
| Fontes | O Flutter não entrega o arquivo da fonte que usou | O app registra os bytes de cada família usada (os mesmos arquivos do `pubspec.yaml`), com cadeia de fallback para chinês |
| Imagens | O Flutter entrega a imagem já decodificada | A lib espera o carregamento antes de pintar e embute os pixels comprimidos. JPEG vindo de asset ou arquivo entra sem decodificar |
| Opacidade, recorte, transformação, gradiente | Têm equivalente em PDF | Traduzidos para vetor |
| Blur, `BackdropFilter`, `ShaderMask`, alguns modos de mistura | Não têm equivalente em PDF | Só aquela subárvore é rasterizada, com aviso no log |
| Widgets que não fazem sentido no papel | Animação, rolagem, campo de texto, `PlatformView` | Animação sai no estado inicial; conteúdo rolável precisa ser montado sem rolagem (a etapa 8 documenta como); `PlatformView` não é suportado |
| Paginação | O layout do Flutter é uma faixa contínua, sem páginas | A lib monta o conteúdo como uma faixa na largura da página e escolhe pontos de quebra seguros (entre linhas de tabela, entre filhos de `Column`, entre linhas de texto). Cada página é uma janela sobre essa faixa. Widgets da lib marcam "manter junto", "quebrar aqui" e "repetir este cabeçalho" |
| Motor do Flutter | A geração precisa do Flutter rodando | Gera na isolate da interface, como hoje, cedendo a vez entre páginas para não travar a tela. Testes com `flutter test`. Os dois apps estão no Flutter 3.47.1; a lib fixa essa versão e é retestada a cada atualização |

### 4.5 Fora do escopo (proposta)

Ler ou editar PDFs existentes, formulários preenchíveis, assinatura digital, texto com shaping complexo (árabe, devanágari).

## 5. Como fica o uso

Ilustração da intenção, não implementação: o relatório é uma árvore de widgets do Flutter, e a lib entra só no começo e no fim.

```dart
final bytes = await PdfDocument(
  fonts: fontesDoApp,
  pages: [
    MultiPage(
      header: (page) => CabecalhoDoRelatorio(relatorio, page: page),
      children: [
        RelatorioSection(title: 'Dados da empresa', child: ...), // widget do próprio app
        Table(...),                                              // Table do Flutter
        KeepTogether(child: CardDoGrafico(...)),
        LineChart(...),                                          // gráfico da lib, o mesmo da tela
      ],
    ),
  ],
).build();
```

O que a lib acrescenta ao Flutter:

| Peça | Para que serve |
|---|---|
| `PdfDocument` | Junta páginas, fontes e metadados e gera os bytes |
| `Page` / `MultiPage` | Página única ou conteúdo que flui por várias páginas, com formato e margens |
| cabeçalho e rodapé | Construídos por página, com número da página e total |
| `PageBreak`, `KeepTogether`, `RepeatOnEachPage` | Controle da paginação |
| registro de fontes | Liga o nome da família no `TextStyle` aos bytes da fonte |
| gráficos | Widgets de gráfico que funcionam na tela e no PDF (seção 6) |
| preview | Mostra as páginas na tela desenhadas pelo próprio Flutter, sem rasterizar o PDF (etapa 10) |

## 6. Gráficos

- **São widgets do Flutter.** O mesmo `LineChart` aparece na tela do relatório e no PDF. Na tela, pinta como qualquer widget; no PDF, a lib reconhece o gráfico e escreve curvas exatas e texto real.
- **API inspirada no `fl_chart`**, que o time já conhece: séries, `minY`/`maxY`/`interval`, eixo secundário, curva, área, pontos, grade, rótulos, legenda.
- **Escopo inicial:** o que as telas usam hoje (seção 2.4.5). Barra e outros tipos dependem da pergunta 3 da seção 11.
- **Caminho intermediário:** com a abordagem B, os gráficos de `fl_chart` que já existem também podem ser pintados no PDF fora da tela, com linhas em vetor e só os rótulos rasterizados (seção 4.4). Isso já elimina a captura da tela visível e a rolagem, e pode ser usado na migração enquanto os gráficos da lib não ficam prontos.

## 7. Etapas

Cada etapa termina com testes e com um PDF de exemplo conferido em três leitores (Chrome, Acrobat e o visualizador padrão do Android). Pilares: **P** personalização, **S** sintaxe, **G** gráficos.

### 7.1 Acompanhamento

| Etapa | Nome | Pilares | Status |
|---|---|---|---|
| 0 | Linha de base | G | aguardando o usuário (precisa dos apps com relatórios reais no aparelho) |
| 1 | Prova de conceito (decide a abordagem) | P S G | concluída em 27/11/2026: seguir com B ([resultado](prova-de-conceito.md)) |
| 2 | Fundação do pacote | — | pronta localmente; falta o CI rodar no GitHub (precisa de push) |
| 3 | Escritor PDF | — | não iniciada |
| 4 | Canvas PDF | P G | não iniciada |
| 5 | Texto e fontes | P S | não iniciada |
| 6 | Imagens, SVG e QR | P | não iniciada |
| 7 | Paginação | P S | não iniciada |
| 8 | Cobertura de widgets | P S | não iniciada |
| 9 | Gráficos nativos | G | não iniciada |
| 10 | Preview, salvar e compartilhar | S | não iniciada |
| 11 | Migração do diagnox | P S G | não iniciada |
| 12 | Migração do valvulas | P S G | não iniciada |
| 13 | Retirada do `pdf`/`printing` e guia de uso | S | não iniciada |

### 7.2 Etapa 0: linha de base

**Objetivo:** ter os números de hoje para comparar depois.

- [ ] Escolher o aparelho de referência (pergunta 9 da seção 11).
- [ ] Medir nos dois apps, para cada tipo de relatório: tempo do toque no botão até o preview aberto, separado em captura dos gráficos, montagem, `save()` e escrita do arquivo.
- [ ] Registrar o tamanho do arquivo de um relatório típico de cada tipo.
- [ ] Guardar um PDF de referência de cada tipo de relatório para a comparação visual.
- [ ] Registrar tudo em `docs/linha-de-base.md`.

**Pronto quando:** existe um número de tempo e de tamanho para cada um dos cinco tipos de relatório (quatro do diagnox, um do valvulas).

### 7.3 Etapa 1: prova de conceito

**Objetivo:** provar ou descartar a abordagem B (seção 4.2) com o mínimo de código. O código da prova fica em `poc/`, separado do pacote, e é descartável: a etapa 2 cria o pacote de verdade e aproveita o que funcionou.

- [x] Montar fora da tela uma árvore com `Container`, `Row`, `Column`, `Padding`, `Text`, `Table` e um `CustomPaint`, dentro de um app Flutter de exemplo.
- [x] Desviar a pintura para um canvas que escreve um PDF de uma página com retângulos, linhas e caminhos em vetor.
- [x] Escrever o texto de um `Text` como texto real, com a Montserrat embutida, e confirmar que dá para copiar e pesquisar.
- [x] Pintar um gráfico do `fl_chart` que já existe (o card de NOx do diagnox) e ver como saem as linhas e os rótulos.
- [x] Medir o tempo da prova contra a captura de hoje.
- [x] Escrever o resultado em `docs/prova-de-conceito.md`, com a decisão.

**Pronto quando:** a decisão está registrada: seguir com B, seguir com B tornando a etapa 9 obrigatória antes da migração, ou voltar para a abordagem A.

### 7.4 Etapa 2: fundação do pacote

**Objetivo:** o pacote existe, compila e roda testes no CI.

- [x] `pubspec.yaml`, `analysis_options.yaml`, estrutura de pastas (seção 8).
- [x] App Flutter de exemplo em `example/`.
- [ ] CI com `flutter analyze` e `flutter test` (`.github/workflows/ci.yml` escrito e conferido localmente; roda no GitHub no primeiro push).
- [x] Harness de benchmark que gera um relatório de exemplo e mede tempo e tamanho (`benchmark/run_android.sh`: no SM-X133, 572 a 596 ms com a lib contra 2.305 a 2.328 ms com o método atual).
- [x] Desmontagem segura da árvore fora da tela, inclusive quando o sistema avisa troca de fontes durante a geração (visto na prova de conceito).
- [x] Testes que travam os pontos em que a lib depende de detalhes internos do Flutter (como `updateCompositedLayer` no `Opacity`), para a atualização do Flutter quebrar o teste e não o relatório.

**Pronto quando:** o CI passa e o benchmark roda com o app de exemplo.

### 7.5 Etapa 3: escritor PDF

**Objetivo:** gerar um arquivo PDF válido a partir de objetos.

- [ ] Documento, páginas, tabela xref, trailer, metadados (título, autor, data).
- [ ] Streams de conteúdo comprimidos.
- [ ] Formatos de página (A4, Carta), retrato e paisagem.

**Pronto quando:** um PDF gerado por teste abre nos três leitores e passa num validador de PDF.

### 7.6 Etapa 4: canvas PDF

**Objetivo:** todo comando de desenho do canvas do Flutter tem tradução, vetorial ou rasterizada.

- [ ] Retângulo, retângulo arredondado, retângulo duplo, oval, círculo, arco, linha, pontos.
- [ ] `Path` livre por amostragem; tipo de preenchimento (par-ímpar e não-zero).
- [ ] Cor, espessura, ponta e junção de linha, tracejado.
- [ ] Opacidade, gradiente linear e radial.
- [ ] Transformação, recorte, `save`/`restore`.
- [ ] Camadas do Flutter (opacidade, recorte, transformação) e rasterização da subárvore para efeitos sem equivalente.
- [ ] Gradientes lidos no render object (`RenderDecoratedBox`), porque o shader do `dart:ui` é opaco (visto na prova de conceito).
- [ ] Sombra de elevação (`drawShadow`), usada por `Card` e `Material`.

**Pronto quando:** um teste que pinta cada comando gera um PDF que, conferido nos três leitores, bate com a mesma pintura na tela.

### 7.7 Etapa 5: texto e fontes

**Objetivo:** texto real no PDF, com as fontes do app.

- [ ] Registro de fontes por família e peso.
- [ ] Leitura do arquivo TrueType, subset dos glifos usados, mapeamento para Unicode (copiar e pesquisar).
- [ ] `Text` e `RichText`: quebras de linha do Flutter, peso, itálico, cor, sublinhado, alinhamento, `maxLines` e reticências.
- [ ] Fallback para chinês, com fonte definida na pergunta 5 da seção 11.
- [ ] Texto dentro de painters de terceiros: rasterização só do trecho.
- [ ] Comportamento para família não registrada (erro claro ou fonte padrão, a decidir na etapa).
- [ ] Subset das fontes: na prova, as três Montserrat inteiras eram 440 dos 469 KB do arquivo.
- [ ] Ícones (`Icon`, fonte MaterialIcons), sublinhado, `WidgetSpan` e reticências.

**Pronto quando:** um relatório em português e um em chinês saem com o texto certo, copiável, e com as mesmas quebras de linha da tela.

### 7.8 Etapa 6: imagens, SVG e QR

**Objetivo:** o que o relatório mostra além de texto e formas.

- [ ] `Image.asset`, `Image.memory`, `Image.file`, com espera do carregamento antes de pintar.
- [ ] JPEG sem decodificar; demais formatos pelos pixels comprimidos.
- [ ] `SvgPicture` (`flutter_svg`) em vetor. Atenção: o `flutter_svg` pinta com `drawPicture`, que é opaco (visto na prova de conceito).
- [ ] `QrImageView` (`qr_flutter`) em vetor.

**Pronto quando:** o cabeçalho do diagnox (logo do diagnox, logo do cliente e QR) sai igual ao de hoje, com o QR nítido em qualquer zoom.

### 7.9 Etapa 7: paginação

**Objetivo:** conteúdo de qualquer tamanho flui pelas páginas sem armadilha.

- [ ] `Page` e `MultiPage` com formato e margens.
- [ ] Pontos de quebra seguros: entre linhas de `Table`, entre filhos de `Column`, entre linhas de texto, em qualquer profundidade.
- [ ] `KeepTogether`, `PageBreak` e cabeçalho de tabela repetido na página seguinte.
- [ ] Cabeçalho e rodapé por página, com número da página e total.
- [ ] Bloco maior que a página quebra em vez de lançar exceção.
- [ ] Título mantido com o conteúdo seguinte (na prova, o título de uma seção ficou sozinho no fim da página).

**Pronto quando:** a lista de 30 etapas da bomba de ARLA (o caso que derrubava o relatório, seção 2.3.2) e um relatório com 100 parâmetros quebram página corretamente, com o cabeçalho da tabela repetido.

### 7.10 Etapa 8: cobertura de widgets

**Objetivo:** fechar o pilar de personalização com uma lista verificada.

- [ ] Levantar o catálogo de widgets usados nas telas de relatório dos dois apps (incluindo os componentes próprios do app).
- [ ] Um teste por widget, comparando PDF e tela.
- [ ] Publicar a tabela de suporte em `docs/widgets-suportados.md`: vetor, rasterizado ou não suportado, com a alternativa para cada caso.
- [ ] Documentar como montar conteúdo que na tela é rolável.

**Pronto quando:** todo widget do catálogo está na tabela, e nenhum dos usados nos relatórios atuais está como "não suportado".

### 7.11 Etapa 9: gráficos nativos

**Objetivo:** o gráfico de linha da lib, na tela e no PDF.

- [ ] `LineChart` com várias séries, reta ou curva, área, ponto no último valor.
- [ ] Eixo Y com `minY`, `maxY`, `interval` e escala automática; casas decimais configuráveis.
- [ ] Eixo Y secundário com escala, unidade e cor próprias.
- [ ] Grade, linhas de eixo, rótulos e legenda.
- [ ] No PDF: curvas exatas e texto real (nenhuma imagem).
- [ ] Séries longas (milhares de pontos) sem reduzir para 160 pontos; se houver redução, preservando picos.
- [ ] Card de gráfico com título, valor atual, unidade e média.

**Pronto quando:** os gráficos de NOx, O₂, tensão × corrente (diagnox) e de um relatório EBS (valvulas) saem no PDF sem nenhuma imagem e com o visual aprovado pelo usuário.

### 7.12 Etapa 10: preview, salvar e compartilhar

**Objetivo:** substituir o `PdfPreview` do `printing` e o código duplicado dos dois `*_viewer_service.dart`.

- [ ] Preview que desenha as páginas com o próprio Flutter (as páginas já são widgets), com zoom.
- [ ] Salvar e compartilhar, no lugar decidido na pergunta 4 da seção 11.

**Pronto quando:** o fluxo de preview, salvar e compartilhar dos dois apps funciona sem o `printing`.

### 7.13 Etapa 11: migração do diagnox

**Objetivo:** os quatro relatórios do diagnox na lib nova, sem captura de tela.

- [ ] NOx (o menor).
- [ ] Eficiência do catalisador.
- [ ] Bomba de ARLA.
- [ ] Testes especiais.
- [ ] Remover `captureGraphImage`, o `RepaintBoundary` do gráfico e os parâmetros de tamanho da tela.
- [ ] Comparar tempo, tamanho e linhas de código com a linha de base.

**Pronto quando:** os quatro relatórios saem pela lib nova, aprovados lado a lado com o PDF de referência da etapa 0.

### 7.14 Etapa 12: migração do valvulas

**Objetivo:** o relatório genérico na lib nova, sem captura nem fatiamento.

- [ ] Relatório genérico (EBS e ECA).
- [ ] Remover a captura por card, o fatiamento, o `package:image` do fluxo e o fallback `pw.Chart`.
- [ ] Comparar tempo, tamanho e linhas de código com a linha de base.

**Pronto quando:** o relatório sai pela lib nova, aprovado lado a lado com o PDF de referência.

### 7.15 Etapa 13: retirada do `pdf`/`printing` e guia de uso

- [ ] Remover `pdf` e `printing` dos `pubspec.yaml` dos dois apps.
- [ ] Guia de uso em `docs/guia-de-uso.md`, escrito para quem já sabe Flutter.

**Pronto quando:** nenhum dos dois apps depende mais do `pdf` nem do `printing`.

## 8. Estrutura proposta do repositório

```
lib_pdf/
  lib/
    lib_pdf.dart          API pública
    src/
      document/           escritor PDF: objetos, xref, compressão
      canvas/             tradução dos comandos de desenho para PDF
      text/               fontes, subset, texto real
      image/              imagens e rasterização de subárvore
      render/             montagem e layout fora da tela
      pagination/         pontos de quebra, páginas, cabeçalho e rodapé
      widgets/            PdfDocument, Page, MultiPage, PageBreak, KeepTogether
      charts/             LineChart e eixos
      preview/            preview das páginas na tela
  test/
  example/                app Flutter de exemplo
  benchmark/
  docs/
```

## 9. Como medir

| Pilar | Medida | Fonte |
|---|---|---|
| Personalização | Widgets do catálogo suportados em vetor, rasterizados e não suportados | Etapa 8 |
| Sintaxe | Linhas de código por relatório (hoje de 840 a 1.158); quantidade de peças novas que o time precisa aprender (seção 5) | Etapas 11 e 12 |
| Gráficos | Tempo de geração e tamanho do arquivo contra a linha de base; zero imagens de gráfico no PDF | Etapas 0, 11 e 12 |

## 10. Riscos

- **A pintura não poder ser desviada por completo.** É o maior risco da abordagem B, e a etapa 1 existe para descobri-lo cedo.
- **Texto em painters de terceiros.** Sai rasterizado (seção 4.4). Os gráficos da lib resolvem o caso principal; outros painters ficam com texto em imagem.
- **Acoplamento à versão do Flutter.** A lib usa a montagem e a pintura do Flutter por dentro, e uma atualização pode mudar algo. Mitigação: fixar a versão (hoje 3.47.1 nos dois apps) e rodar a suíte de testes a cada atualização.
- **Tela travando durante a geração.** A geração roda na isolate da interface. Mitigação: ceder a vez entre páginas e medir com relatórios grandes.
- **Fontes.** O app precisa registrar os bytes de cada fonte usada; fonte baixada em tempo de execução (`google_fonts`) precisa de tratamento à parte.
- **Paridade visual.** O cliente conhece o papel atual. Mudança de visual precisa ser aprovada antes de migrar cada relatório.
- **Tamanho do trabalho.** Escritor PDF, canvas, texto e paginação são muitas peças. A ordem das etapas põe a prova de conceito primeiro e o relatório de NOx de pé o quanto antes.

## 11. Perguntas em aberto

1. ~~**Abordagem:** você confirma a abordagem B (seção 4.2), com a etapa 1 decidindo se ela se sustenta?~~ **Respondida em 27/11/2026:** sim, abordagem B.
2. **Dependências:** a lib pode depender de outros pacotes (por exemplo `share_plus` e `path_provider` para compartilhar), ou deve depender só do Flutter?
3. **Gráficos:** além de linha, quais tipos são necessários (barra, pizza, gauge)? O visual no papel deve ser igual ao da tela (card colorido, linha branca) ou próprio para papel (fundo branco)?
4. **Preview, salvar e compartilhar:** ficam na lib ou em cada app?
5. **Fontes:** quais famílias os PDFs vão usar? De onde vem a fonte para chinês?
6. **Plataformas:** o PDF precisa ser gerado também no web e no desktop do valvulas?
7. **Componentes de relatório:** com a abordagem B, cada app pode usar os próprios componentes de tela no PDF. Ainda vale ter componentes compartilhados (cabeçalho, seção, tabela chave/valor) na lib?
8. **Nome e distribuição:** nome do pacote e como os apps vão depender dele (git, pub privado).
9. **Aparelho de referência** para a linha de base (etapa 0).
10. **Paridade visual:** o papel pode mudar de visual na migração, ou deve ficar igual ao de hoje?
