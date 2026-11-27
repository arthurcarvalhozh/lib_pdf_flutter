# Linha de base: tempo e tamanho dos PDFs de hoje (etapa 0)

> **O que é:** quanto os apps levam hoje para gerar cada relatório em PDF, e como é o arquivo, medidos no tablet
> **Para que serve:** ser a referência que as migrações (etapas 11 e 12) precisam bater
> **Quando consultar:** ao medir a lib nova num relatório migrado, e ao comparar o visual com o PDF de hoje
> **Status:** concluída em 27/11/2026 com um relatório de cada app: bomba de ARLA (diagnox) e EBS automático (valvulas). Os outros tipos são medidos quando forem migrados.

## 1. Como foi medido

- **Aparelho:** tablet Samsung SM-X133, o mesmo modelo usado na prova de conceito, controlado pelo adb.
- **Fluxo:** o teste roda até o fim, e o operador toca em "Gerar relatório" e depois no botão vermelho de PDF da tela "Detalhes do relatório".
- **Início:** o toque no botão de PDF, confirmado pelo log do Android (`ViewPostIme`).
- **Arquivo pronto:** o horário de gravação do PDF no cache do app, lido com `run-as`. Precisão de décimos de segundo.
- **Página visível:** o primeiro print da tela em que a página aparece no visualizador. Os prints saem a cada 0,4 a 0,7 s, então essa medida tem essa margem.
- **Etapas internas (só valvulas):** o actuall registra cada etapa da geração (`[RELATORIO][PDF]`) no log do Dart; em debug esse log vai para o VM service, que foi escutado durante a medida.

**Atenção:** os dois apps medidos são APKs de debug (diagnox 3.7.3-dev e actuall 0.1.10-dev, compilados em JIT). Em release, o tempo de hoje deve ser menor, então a comparação com a lib nova precisa usar o mesmo tipo de build dos dois lados. Os números da prova de conceito foram medidos em build `--profile` e em outra unidade do SM-X133, por isso não dá para compará-los direto com os desta página.

## 2. Resultados

### diagnox: bomba de ARLA (27/11/2026, dosagem curta)

| Medida | Valor |
|---|---|
| Toque → começo da montagem do PDF | 0,95 s (captura do gráfico com `pixelRatio: 3`, PNG, dados da empresa e QR) |
| Toque → arquivo gravado | **1,98 s** |
| Toque → página visível no `PdfPreview` | **entre 3,5 e 3,9 s** |
| Tamanho | 106 KB, 1 página |
| Imagens | Gráficos: uma imagem de 2930 × 1015 px (80 KB, mais 11 KB de máscara), cerca de 88 % do arquivo. Mais o logo e o QR |
| Fontes | Helvetica e Helvetica-Bold, não embutidas |

O que o PDF de hoje mostra:

- **Os três gráficos são uma única foto da tela**, colada na página. Ao ampliar, pixela, e os rótulos dos eixos não podem ser selecionados nem pesquisados.
- **A foto sai deformada:** a resolução é de 380 ppi na horizontal e 471 ppi na vertical. A imagem foi achatada cerca de 20 % na altura para caber no espaço (`BoxFit.fill`).
- **A fonte não é a do app:** o PDF usa Helvetica sem embutir, e o `package:pdf` avisa no log que ela não tem suporte a Unicode.
- **Possível erro de dado, fora do escopo da lib:** o diálogo de fim do teste mostrou "Quantidade dosada: 100 ml", mas o PDF diz "Volume dosado: Não informado".

Na primeira tentativa, com o app rodando em debug, a geração travou depois da montagem do documento e nunca gravou o arquivo. O usuário informou que é um problema conhecido do diagnox em debug. Com o APK, gerou normalmente.

O PDF de referência fica em `benchmark/results/diagnox_bomba_arla_2026-11-27.pdf`, fora do git porque tem dados do relatório.

### valvulas (actuall): EBS, teste automático de 10 bar (27/11/2026, Simulação Knorr dupla, 1 ciclo)

| Etapa | Tempo |
|---|---|
| Captura dos 4 gráficos: rola até cada card, espera, `toImage` com `pixelRatio: 3`, PNG | **4,27 s** (cerca de 0,9 s por card) |
| Montagem: fontes, logo, QR, `addPage` | 0,43 s |
| `pdf.save()` | **2,33 s** |
| Gravação do arquivo | 0,01 s |
| Toque → arquivo gravado | **7,1 s** |
| Toque → página visível no `PdfPreview` | **entre 8,7 e 9,1 s** |

| Arquivo | |
|---|---|
| Tamanho | 300 KB, 2 páginas |
| Imagens | Quatro gráficos de 1444 × 996 px (cerca de 168 KB com as máscaras, 56 % do arquivo) e o logo, de 1489 × 399 px (116 KB, 39 %) |
| Fontes | Montserrat Regular e Bold, embutidas |

O que o PDF de hoje mostra:

- **Dos cerca de 9 s, 6,6 s são a captura e o `save()`.** A captura dos gráficos sozinha leva quase metade do tempo, e o `save()` leva 2,3 s (o arquivo tem cinco imagens grandes para comprimir).
- **Cada gráfico é uma foto da tela**, capturada card a card. Não há deformação (388 ppi nas duas direções), mas pixela ao ampliar e os rótulos não são texto.
- **O logo pesa 116 KB:** é uma imagem de 1489 × 399 px desenhada com poucos centímetros (1218 ppi).
- A seção de gráficos ocupa a página 2 inteira, com espaço em branco abaixo de cada par de cards, e se divide em "Gráficos" e "Gráficos (continuação 2/2)".

O PDF de referência fica em `benchmark/results/actuall_ebs_automatico_10bar_2026-11-27.pdf`.

## 3. Cobertura

| App | Relatório | Situação |
|---|---|---|
| diagnox | Bomba de ARLA | medido (seção 2) |
| diagnox | NOx | medir na migração (etapa 11) |
| diagnox | Eficiência do catalisador | medir na migração (etapa 11) |
| diagnox | Testes especiais | medir na migração (etapa 11) |
| valvulas | EBS, teste automático de 10 bar | medido (seção 2) |
| valvulas | ECA | medir na migração (etapa 12) |
