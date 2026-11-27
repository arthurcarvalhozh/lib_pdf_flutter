## 0.1.0-dev.1

- Pacote criado a partir da prova de conceito (etapa 2 do plano).
- Escritor PDF (etapa 3): `/ID` no trailer, nomes escapados, metadados
  `subject`, `keywords`, `creator` e `creationDate`, formatos A3, Legal e em
  milímetros, `.portrait`. O mesmo documento com a mesma data gera os mesmos
  bytes.
- Canvas PDF (etapa 4): opacidade como grupo de transparência, modos de
  mistura, gradientes lineares e radiais em vetor, recorte por diferença,
  `drawImageNine` e `drawAtlas`; sombras, desfoques, filtros de cor,
  `ShaderMask` e `ImageFiltered` rasterizados só no trecho.
- Correção: imagens de widgets (`Image`, `RawImage`) quebravam a geração,
  porque o `RenderImage` descartava a imagem antes da escrita.
