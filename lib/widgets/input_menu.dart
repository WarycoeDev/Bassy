// lib/widgets/input_menu.dart
import 'package:flutter/material.dart';

/// Resultado de un [InputMenu].
class InputMenuResult {
  final bool confirmed;
  final String text;
  const InputMenuResult({required this.confirmed, required this.text});
}

/// Menú de entrada de texto reutilizable y con estilo global.
///
/// Análogo a `ActionMenu` pero para capturar texto:
///  - nombres de playlist
///  - renombrar álbum/artista (futuro)
///  - buscar, etc.
///
/// Dos modos:
///  - [show]: dialog centrado (móvil / por defecto).
///  - [showAt]: variante anclada (mismo dialog; reservado para popup real).
class InputMenu {
  InputMenu._();

  static Future<InputMenuResult?> show(
    BuildContext context, {
    String? title,
    String? subtitle,
    String? initialValue,
    String hintText = 'Escribe un nombre…',
    String confirmLabel = 'Guardar',
    String cancelLabel = 'Cancelar',
    int maxLength = 80,
    bool allowEmpty = false,
    TextInputType keyboardType = TextInputType.text,
    List<String>? suggestions,
  }) {
    return showDialog<InputMenuResult>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _InputDialog(
        title: title,
        subtitle: subtitle,
        initialValue: initialValue,
        hintText: hintText,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        maxLength: maxLength,
        allowEmpty: allowEmpty,
        keyboardType: keyboardType,
        suggestions: suggestions,
      ),
    );
  }

  /// Variante anclada. Hoy delega en [show]; si más adelante quieres
  /// un popup real anclado a [globalPosition], solo cambia este cuerpo.
  static Future<InputMenuResult?> showAt(
    BuildContext context, {
    required Offset globalPosition,
    String? title,
    String? subtitle,
    String? initialValue,
    String hintText = 'Escribe un nombre…',
    String confirmLabel = 'Guardar',
    String cancelLabel = 'Cancelar',
    int maxLength = 80,
    bool allowEmpty = false,
    TextInputType keyboardType = TextInputType.text,
    List<String>? suggestions,
  }) {
    return show(
      context,
      title: title,
      subtitle: subtitle,
      initialValue: initialValue,
      hintText: hintText,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      maxLength: maxLength,
      allowEmpty: allowEmpty,
      keyboardType: keyboardType,
      suggestions: suggestions,
    );
  }
}

class _InputDialog extends StatefulWidget {
  final String? title;
  final String? subtitle;
  final String? initialValue;
  final String hintText;
  final String confirmLabel;
  final String cancelLabel;
  final int maxLength;
  final bool allowEmpty;
  final TextInputType keyboardType;
  final List<String>? suggestions;

  const _InputDialog({
    this.title,
    this.subtitle,
    this.initialValue,
    required this.hintText,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.maxLength,
    required this.allowEmpty,
    required this.keyboardType,
    this.suggestions,
  });

  @override
  State<_InputDialog> createState() => _InputDialogState();
}

class _InputDialogState extends State<_InputDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue ?? '');
    _controller.addListener(_onChanged);
  }

  void _onChanged() {
    // Un solo listener: limpia error y refresca estado del botón.
    setState(() => _error = null);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  bool get _canConfirm =>
      widget.allowEmpty || _controller.text.trim().isNotEmpty;

  void _confirm() {
    final text = _controller.text.trim();
    if (!widget.allowEmpty && text.isEmpty) {
      setState(() => _error = 'El nombre no puede estar vacío');
      return;
    }
    Navigator.pop(
      context,
      InputMenuResult(confirmed: true, text: text),
    );
  }

  void _cancel() {
    Navigator.pop(
      context,
      const InputMenuResult(confirmed: false, text: ''),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Dialog(
      backgroundColor: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: 32,
        vertical: 24,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.title != null)
                Text(
                  widget.title!,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 18,
                  ),
                ),
              if (widget.subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  widget.subtitle!,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                autofocus: true,
                maxLength: widget.maxLength,
                keyboardType: widget.keyboardType,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _confirm(),
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  errorText: _error,
                  filled: true,
                  fillColor: scheme.surfaceContainer,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  counterText: '',
                ),
              ),
              if (widget.suggestions != null &&
                  widget.suggestions!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final s in widget.suggestions!)
                      ActionChip(
                        label: Text(
                          s,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onPressed: () {
                          _controller.text = s;
                          _controller.selection =
                              TextSelection.collapsed(offset: s.length);
                        },
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Flexible(
                    child: TextButton(
                      onPressed: _cancel,
                      child: Text(
                        widget.cancelLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: FilledButton(
                      onPressed: _canConfirm ? _confirm : null,
                      child: Text(
                        widget.confirmLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}