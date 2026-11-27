# Prova de conceito: widgets do Flutter pintados direto em PDF (etapa 1)

> **O que é:** o resultado da etapa 1 do plano: se a abordagem B (usar os widgets do Flutter de verdade e trocar só o destino do desenho) se sustenta
> **Para que serve:** registrar a decisão da etapa 1 e o que a prova descobriu, para as próximas etapas não redescobrirem
> **Quando consultar:** antes das etapas 4 a 9, que tratam dos pontos abertos listados na seção 5
> **Status:** concluída em 27/11/2026. Decisão: seguir com a abordagem B (seção 6).

## 1. O que foi feito

Um app Flutter em `poc/` (Flutter 3.47.1, o mesmo dos dois apps) com um motor mínimo de cerca de 1.650 linhas em `poc/lib/pdf/`:

| Arquivo | Papel |
|---|---|
| `pdf_writer.dart` | Escreve objetos, streams comprimidos, xref e trailer |
| `truetype.dart` | Lê o TrueType (métricas, `cmap`) e embute a fonte com `ToUnicode` |
| `pdf_canvas.dart` | Implementa o `Canvas` do Flutter escrevendo operadores PDF |
| `pdf_painting_context.dart` | Desvia a pintura da árvore de render objects para o canvas PDF |
| `pdf_text.dart` | Escreve `Text`/`RichText` como texto real, nas posições que o Flutter calculou |
| `pdf_document.dart` | Monta a árvore fora da tela, escolhe as quebras de página, pinta e grava |

O relatório de teste (`poc/lib/report/poc_report.dart`) imita o relatório de NOx do diagnox e foi escrito só com widgets do Flutter: `Column`, `Row`, `Container`, `Table`, `Text.rich`, `ClipRRect`, `Opacity`, `CustomPaint`, mais o `QrImageView` do `qr_flutter` e o `NoxGrafico` do diagnox **copiado sem nenhuma alteração** (`poc/lib/report/nox_chart_replica.dart`), que usa o `fl_chart`.

Para reproduzir:

```
cd poc
flutter test                      # gera build/poc/relatorio_poc.pdf
pdftotext -layout build/poc/relatorio_poc.pdf -
```

## 2. Respostas às perguntas da etapa

| Pergunta | Resultado |
|---|---|
| Dá para montar e medir a árvore fora da tela? | **Sim.** A lib cria a própria árvore (`RenderView` + `PipelineOwner` + `BuildOwner`), fornece `MediaQuery` e `Directionality`, e mede o conteúdo na largura útil da página. Nada aparece na tela e nada precisa rolar. |
| A pintura pode ser desviada para PDF? | **Sim.** Uma subclasse de `PaintingContext` troca o `canvas`, sobrescreve `paintChild` e `pushLayer`, e trata as fronteiras de repintura pela camada que elas mesmas criam (`updateCompositedLayer`). |
| `Text` sai como texto real? | **Sim.** Texto selecionável, copiável e pesquisável, com a Montserrat embutida, acentos e o "₂" de O₂. As quebras de linha são as do Flutter, porque cada caractere vai para a posição que o Flutter mediu. |
| Um gráfico do `fl_chart` que já existe sai em vetor? | **Sim, inclusive os rótulos dos eixos.** O `fl_chart` 0.68 monta os rótulos como widgets, então eles saem como texto real. Linhas, curvas, grade, eixo secundário amarelo e o ponto final saem em vetor, nítidos a 400 dpi. |
| Quanto tempo leva? | Seção 3. |

Também funcionaram sem nenhuma adaptação: o QR do `qr_flutter` (em vetor), cantos arredondados, `ClipRRect`, `Opacity`, bordas de `Table`, `CustomPaint` com área preenchida e transparência.

## 3. Tempo e tamanho

Medido em 27/11/2026 no tablet SM-X133 (Galaxy Tab A11, Android, build `--profile`), com a mediana de 5 gerações depois de uma de aquecimento. O app de medida está em `poc/lib/main.dart` e já foi desinstalado do tablet.

| | Método atual (foto do gráfico + `package:pdf`) | Lib nova (widgets pintados em PDF) |
|---|---|---|
| Tempo total | **1.453 ms**, dos quais 717 ms só na captura do gráfico (`toImage` com `pixelRatio: 3` e PNG) | **207 ms** (layout 36, pintura 111, escrita 50) |
| Tamanho | 85 KB | 469 KB (fontes inteiras, sem subset) |
| Gráfico | Imagem: pixela ao ampliar, rótulos não pesquisáveis | Vetor, rótulos como texto real |
| Conteúdo | Só tabelas e gráficos | Tudo do método atual, mais cabeçalho com QR, texto corrido, recorte, opacidade e desenho livre |

A lib nova foi **cerca de 7 vezes mais rápida** e gerou um relatório mais completo. A comparação ainda favorece o método atual: o diagnox e o valvulas fazem mais do que esta medida. O valvulas, por exemplo, rola até cada card e espera pelo menos 400 ms antes de capturar, e o diagnox captura mais de um gráfico. O tempo dos apps de verdade é a linha de base da etapa 0.

O tamanho maior é só fonte: as três Montserrat vão inteiras (cerca de 440 KB). Com o subset, previsto na etapa 5, o arquivo deve ficar abaixo do atual.

O PDF gerado no tablet saiu idêntico ao do `flutter test`.

O tempo absoluto varia com o estado do tablet. Uma hora depois, o mesmo APK mediu 593 ms para a lib e 3.091 ms para o método atual, e o pacote da etapa 2 mediu 572 a 596 ms contra 2.305 a 2.328 ms (`benchmark/run_android.sh`). A lib ficou entre 4 e 7 vezes mais rápida conforme a rodada, então só vale comparar números da mesma rodada.

Observação sobre gráficos que dependem da tela: o `NoxGrafico` calcula o tamanho dos rótulos com `MediaQuery.of(context).size.height * 0.017`. No PDF, a lib entrega o tamanho da página como `MediaQuery`, então os rótulos ficam proporcionais à página, e não à tela do aparelho. Para o relatório isso é melhor (o resultado não muda de um aparelho para outro), mas a migração precisa revisar os widgets que fazem esse tipo de conta.

## 4. Quebra de página

A prova já quebra página pelo método previsto no plano: o conteúdo é medido como uma faixa contínua, e a quebra cai no maior ponto da página que não corta linha de texto, linha de tabela, desenho, imagem nem bloco marcado com `KeepTogether`. No relatório de teste, a tabela de 40 leituras foi inteira para a página 2, sem cortar nenhuma linha.

Defeito visto: o título "Leituras" ficou sozinho no fim da página 1. Falta a regra "manter o título com o que vem depois" (etapa 7).

## 5. Pontos abertos que a prova encontrou

| Ponto | O que acontece hoje na prova | Etapa |
|---|---|---|
| Tamanho do arquivo | 469 KB, dos quais cerca de 440 KB são as três fontes inteiras (sem subset) | 5 |
| Texto pintado por `TextPainter` dentro de painter | Rasterizado em 4×; aconteceu uma vez, no desenho livre de teste | 5 e 9 |
| Gradiente (`BoxDecoration.gradient`, `Paint.shader`) | O shader do `dart:ui` é opaco: sai em cor sólida. Solução: ler o gradiente no render object (`RenderDecoratedBox`), como já é feito com o texto | 4 |
| Sombra (`drawShadow`, elevação de `Card` e `Material`) | Ignorada | 4 |
| `drawPicture` | Ignorado. O `flutter_svg` (via `vector_graphics`) pinta com `Picture`, então SVG precisa de tratamento próprio | 6 |
| Ícones (`Icon`) | Não testados: a fonte MaterialIcons precisa ser registrada como as outras | 5 |
| Sublinhado, `WidgetSpan`, reticências | Não tratados | 5 |
| Título órfão no fim da página | Seção 4 | 7 |
| Aviso de troca de fontes do sistema durante a geração | Deixa um callback pendente para o próximo frame e quebra a desmontagem da árvore. A prova espera o frame antes de desmontar; a lib precisa tratar isso de vez | 2 |
| `Path` livre | Amostrado e simplificado, como previsto. Visualmente correto a 400 dpi; cantos de caminhos retos podem deslocar até 0,25 pt | 4 |
| Dependência de detalhes internos do Flutter | O `Opacity` mudou de `pushOpacity` para `updateCompositedLayer` em alguma versão recente. A lib precisa de testes que peguem esse tipo de mudança a cada atualização do Flutter | 2 |

## 6. Decisão

**Seguir com a abordagem B.** As quatro perguntas da etapa tiveram resposta positiva, e o texto dentro de painters de terceiros, que era o maior risco, se mostrou menor que o previsto: no `fl_chart` 0.68 os rótulos são widgets e saem como texto real. A etapa 9 (gráficos nativos) continua no plano para o pilar de gráficos, mas não precisa vir antes da migração.

O código da prova fica em `poc/` como referência e é descartável: a etapa 2 cria o pacote e reaproveita o que funcionou.
