# Linha de base: tempo e tamanho dos PDFs de hoje (etapa 0)

> **O que é:** quanto os apps levam hoje para gerar cada relatório em PDF, e como é o arquivo, medidos no tablet
> **Para que serve:** ser a referência que as migrações (etapas 11 e 12) precisam bater
> **Quando consultar:** ao medir a lib nova num relatório migrado, e ao comparar o visual com o PDF de hoje
> **Status:** em andamento. Medidos: bomba de ARLA (diagnox). Faltam: valvulas, NOx, eficiência e testes especiais.

## 1. Como foi medido

- **Aparelho:** tablet Samsung SM-X133, o mesmo modelo usado na prova de conceito, controlado pelo adb.
- **Fluxo:** o teste roda até o fim, e o operador toca em "Gerar relatório" e depois no botão vermelho de PDF da tela "Detalhes do relatório".
- **Início:** o toque no botão de PDF, confirmado pelo log do Android (`ViewPostIme`).
- **Arquivo pronto:** o horário de gravação do PDF no cache do app, lido com `run-as`. Precisão de décimos de segundo.
- **Página visível:** o primeiro print da tela em que a página aparece no visualizador. Os prints saem a cada 0,4 a 0,7 s, então essa medida tem essa margem.

**Atenção:** o diagnox medido é um APK de debug (3.7.3-dev, compilado em JIT). Em release, o tempo de hoje deve ser menor, então a comparação com a lib nova precisa usar o mesmo tipo de build dos dois lados. Os números da prova de conceito foram medidos em build `--profile` e em outra unidade do SM-X133, por isso não dá para compará-los direto com os desta página.

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

## 3. Pendente

| App | Relatório | Situação |
|---|---|---|
| diagnox | Bomba de ARLA | medido (seção 2) |
| diagnox | NOx | não medido |
| diagnox | Eficiência do catalisador | não medido |
| diagnox | Testes especiais | não medido |
| valvulas | Relatório genérico (EBS/ECA) | não medido |
