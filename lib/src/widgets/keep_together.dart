import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Mantém o filho inteiro na mesma página, se ele couber numa página.
///
/// Na tela, não muda nada: é só uma marcação lida pela paginação.
class KeepTogether extends SingleChildRenderObjectWidget {
  const KeepTogether({super.key, required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => RenderKeepTogether();
}

/// Render object do [KeepTogether].
class RenderKeepTogether extends RenderProxyBox {}
