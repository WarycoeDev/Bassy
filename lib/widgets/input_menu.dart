// lib/widgets/input_menu.dart
import 'dart:io';

import 'package:flutter/material.dart';

/// Resultado de un [InputMenu].
class InputMenuResult {
  final bool confirmed;
  final String text;
  const InputMenuResult({required this.confirmed, required this.text});
}

/// Menú de entrada de texto reutilizable y con el mismo estilo que
/// `ActionMenu` (cabecera con icono/carátula, botón cerrar, botones
/// redondeados).
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
    IconData fallbackIcon = Icons.edit_outlined,
    IconData confirmIcon = Icons.check_rounded,
    String? coverPath,
    Widget? leading,
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
        fallbackIcon: fallbackIcon,
        confirmIcon: confirmIcon,
        coverPath: coverPath,
        leading: leading,
      ),
    );
  }

  /// Variante anclada. Hoy delega en [show].
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
    IconData fallbackIcon = Icons.edit_outlined,
    IconData confirmIcon = Icons.check_rounded,
    String? coverPath,
    Widget? leading,
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
      fallbackIcon: fallbackIcon,
      confirmIcon: confirmIcon,
      coverPath: coverPath,
      leading: leading,
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
  final IconData fallbackIcon;
  final IconData confirmIcon;
  final String? coverPath;
  final Widget? leading;

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
    required this.fallbackIcon,
    required this.confirmIcon,
    this.suggestions,
    this.coverPath,
    this.leading,
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
    Navigator.pop(context, InputMenuResult(confirmed: true, text: text));
  }

  void _cancel() {
    Navigator.pop(
      context,
      const InputMenuResult(confirmed: false, text: ''),
    );
  }

  bool get _hasCover {
    final p = widget.coverPath;
    if (p == null || p.isEmpty) return false;
    try {
      return File(p).existsSync();
    } catch (_) {
      return false;
    }
  }

  Widget _fallbackCover(ColorScheme scheme) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        widget.fallbackIcon,
        color: scheme.onSurfaceVariant,
        size: 24,
      ),
    );
  }

  Widget _buildHeader(ColorScheme scheme) {
    final Widget leading = widget.leading ??
        (_hasCover
            ? ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.file(
                  File(widget.coverPath!),
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                  cacheWidth: 144,
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) => _fallbackCover(scheme),
                ),
              )
            : _fallbackCover(scheme));

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  leading,
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.title != null)
                          Text(
                            widget.title!,
                            style: TextStyle(
                              color: scheme.onSurface,
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        if (widget.subtitle != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            widget.subtitle!,
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            iconSize: 20,
            visualDensity: VisualDensity.compact,
            tooltip: 'Cerrar',
            onPressed: _cancel,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canConfirm = _canConfirm;

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
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(scheme),
              const SizedBox(height: 4),

              // Campo de texto con el mismo "contenedor" que la lista
              // de acciones del ActionMenu.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    maxLength: widget.maxLength,
                    keyboardType: widget.keyboardType,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _confirm(),
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 15,
                    ),
                    decoration: InputDecoration(
                      hintText: widget.hintText,
                      hintStyle: TextStyle(
                        color: scheme.onSurfaceVariant,
                      ),
                      errorText: _error,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      counterText: '',
                      filled: false,
                    ),
                  ),
                ),
              ),

              if (widget.suggestions != null &&
                  widget.suggestions!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Wrap(
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
                ),
              ],

              const SizedBox(height: 8),

              // Botones con el mismo lenguaje que ActionMenu.confirm.
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Material(
                        color: scheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(16),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: _cancel,
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                            child: Center(
                              child: Text(
                                widget.cancelLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Material(
                        color: canConfirm
                            ? scheme.primary
                            : scheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(16),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: canConfirm ? _confirm : null,
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  widget.confirmIcon,
                                  size: 18,
                                  color: canConfirm
                                      ? scheme.onPrimary
                                      : scheme.onSurface
                                          .withValues(alpha: 0.38),
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    widget.confirmLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: canConfirm
                                          ? scheme.onPrimary
                                          : scheme.onSurface
                                              .withValues(alpha: 0.38),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}