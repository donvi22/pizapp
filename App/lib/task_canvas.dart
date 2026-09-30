import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'models/board_text.dart';

class BoardStroke {
  const BoardStroke({
    required this.points,
    this.color = const Color(0xFF263238),
    this.width = 3,
  });

  final List<Offset> points;
  final Color color;
  final double width;

  BoardStroke withPoint(Offset point) => BoardStroke(
        points: [...points, point],
        color: color,
        width: width,
      );

  Map<String, dynamic> toJson() => {
        'points': points.map((p) => [p.dx, p.dy]).toList(),
        'color': color.toARGB32(),
        'width': width,
      };

  static List<BoardStroke> fromCanvasData(Map<String, dynamic> data) {
    final rawStrokes = data['strokes'];
    if (rawStrokes is! List) return [];
    return rawStrokes.map((raw) {
      final stroke = raw as Map;
      final rawPoints = stroke['points'] as List;
      return BoardStroke(
        points: rawPoints.map((rawPoint) {
          final pair = rawPoint as List;
          return Offset(
            (pair[0] as num).toDouble(),
            (pair[1] as num).toDouble(),
          );
        }).toList(),
        color: Color((stroke['color'] as num).toInt()),
        width: (stroke['width'] as num).toDouble(),
      );
    }).toList();
  }
}

enum CanvasMode { write, draw, erase }

class TaskCanvas extends StatefulWidget {
  const TaskCanvas({
    super.key,
    required this.texts,
    required this.strokes,
    required this.onTextsChanged,
    required this.onTextEdited,
    required this.onStrokesChanged,
    required this.onActionStart,
    required this.onActionEnd,
    required this.canUndo,
    required this.canRedo,
    required this.onUndo,
    required this.onRedo,
    this.readOnly = false,
  });

  final List<BoardText> texts;
  final List<BoardStroke> strokes;
  final ValueChanged<List<BoardText>> onTextsChanged;
  final VoidCallback onTextEdited;
  final ValueChanged<List<BoardStroke>> onStrokesChanged;
  final VoidCallback onActionStart;
  final VoidCallback onActionEnd;
  final bool canUndo;
  final bool canRedo;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final bool readOnly;

  @override
  State<TaskCanvas> createState() => _TaskCanvasState();
}

class _TaskCanvasState extends State<TaskCanvas> {
  static const _colors = <Color>[
    Color(0xFF263238),
    Color(0xFFE53935),
    Color(0xFF1E88E5),
    Color(0xFF43A047),
    Color(0xFFF9A825),
  ];

  final _horizontalScroll = ScrollController();
  final _verticalScroll = ScrollController();
  CanvasMode _mode = CanvasMode.write;
  Color _selectedColor = _colors.first;
  double _lineWidth = 3;
  String? _selectedTextId;
  BoardStroke? _draft;
  Offset? _eraserPosition;

  @override
  void dispose() {
    _horizontalScroll.dispose();
    _verticalScroll.dispose();
    super.dispose();
  }

  BoardText? get _selectedText {
    for (final block in widget.texts) {
      if (block.id == _selectedTextId) return block;
    }
    return null;
  }

  void _replaceText(BoardText updated, {bool typed = false}) {
    widget.onTextsChanged([
      for (final block in widget.texts)
        if (block.id == updated.id) updated else block,
    ]);
    if (typed) widget.onTextEdited();
  }

  void _addText() {
    widget.onActionStart();
    final block = BoardText(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      x: math.min(520.0, (_horizontalScroll.hasClients ? _horizontalScroll.offset : 0.0) + 48.0),
      y: (_verticalScroll.hasClients ? _verticalScroll.offset : 0) + 48,
      text: '',
    );
    widget.onTextsChanged([...widget.texts, block]);
    setState(() => _selectedTextId = block.id);
    widget.onActionEnd();
  }

  void _deleteSelectedText() {
    final block = _selectedText;
    if (block == null) return;
    widget.onActionStart();
    widget.onTextsChanged(widget.texts.where((item) => item.id != block.id).toList());
    setState(() => _selectedTextId = null);
    widget.onActionEnd();
  }

  void _setAlignment(TextAlign align) {
    final block = _selectedText;
    if (block == null || block.align == align) return;
    widget.onActionStart();
    _replaceText(block.copyWith(align: align));
    widget.onActionEnd();
  }

  void _startStroke(DragStartDetails details) {
    widget.onActionStart();
    setState(() {
      _draft = BoardStroke(
        points: [details.localPosition],
        color: _selectedColor,
        width: _lineWidth,
      );
    });
  }

  void _extendStroke(DragUpdateDetails details) {
    final draft = _draft;
    if (draft == null) return;
    final start = draft.points.last;
    final end = details.localPosition;
    final steps = math.max(1, ((end - start).distance / 4).ceil());
    setState(() => _draft = BoardStroke(
      points: [
        ...draft.points,
        for (var step = 1; step <= steps; step++)
          Offset.lerp(start, end, step / steps)!,
      ],
      color: draft.color,
      width: draft.width,
    ));
  }

  void _finishStroke() {
    final draft = _draft;
    if (draft == null) return;
    widget.onStrokesChanged([...widget.strokes, draft]);
    setState(() => _draft = null);
    widget.onActionEnd();
  }

  void _startErasing(DragStartDetails details) {
    widget.onActionStart();
    _eraseAt(details.localPosition);
  }

  void _eraseAt(Offset position) {
    const radius = 18.0;
    final result = <BoardStroke>[];
    var changed = false;
    for (final stroke in widget.strokes) {
      var remaining = <Offset>[];
      void finishSegment() {
        if (remaining.isNotEmpty) {
          result.add(BoardStroke(points: remaining, color: stroke.color, width: stroke.width));
          remaining = <Offset>[];
        }
      }
      for (final point in stroke.points) {
        if ((point - position).distance <= radius) {
          changed = true;
          finishSegment();
        } else {
          remaining.add(point);
        }
      }
      finishSegment();
    }
    setState(() => _eraserPosition = position);
    if (changed) widget.onStrokesChanged(result);
  }

  void _finishErasing() {
    setState(() => _eraserPosition = null);
    widget.onActionEnd();
  }

  double _canvasHeight() {
    var contentHeight = 900.0;
    for (final block in widget.texts) {
      final style = TextStyle(fontSize: block.fontSize, height: 1.5);
      final painter = TextPainter(
        text: TextSpan(text: block.text.isEmpty ? ' ' : block.text, style: style),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: block.width - 24);
      contentHeight = math.max(contentHeight, block.y + math.max(100, painter.height + 56) + 40);
      painter.dispose();
    }
    for (final stroke in [...widget.strokes, ?_draft]) {
      for (final point in stroke.points) {
        contentHeight = math.max(contentHeight, point.dy + 80);
      }
    }
    return contentHeight;
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedText;
    return Column(
      children: [
        if (widget.readOnly)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Pizarra en modo lectura'),
          )
        else SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              ChoiceChip(
                label: const Text('Texto'),
                avatar: const Icon(Icons.text_fields, size: 18),
                selected: _mode == CanvasMode.write,
                onSelected: (_) => setState(() => _mode = CanvasMode.write),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Dibujar'),
                avatar: const Icon(Icons.draw, size: 18),
                selected: _mode == CanvasMode.draw,
                onSelected: (_) => setState(() => _mode = CanvasMode.draw),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Goma'),
                avatar: const Icon(Icons.auto_fix_normal, size: 18),
                selected: _mode == CanvasMode.erase,
                onSelected: (_) => setState(() => _mode = CanvasMode.erase),
              ),
              const SizedBox(width: 8),
              IconButton(tooltip: 'Deshacer', onPressed: widget.canUndo ? widget.onUndo : null, icon: const Icon(Icons.undo)),
              IconButton(tooltip: 'Rehacer', onPressed: widget.canRedo ? widget.onRedo : null, icon: const Icon(Icons.redo)),
            ],
          ),
        ),
        if (!widget.readOnly && _mode == CanvasMode.write)
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                TextButton.icon(onPressed: _addText, icon: const Icon(Icons.add), label: const Text('A\u00F1adir texto')),
                if (selected != null) ...[
                  IconButton(tooltip: 'Eliminar bloque', onPressed: _deleteSelectedText, icon: const Icon(Icons.delete_outline)),
                  const Center(child: Text('Tama\u00F1o')),
                  SizedBox(
                    width: 150,
                    child: Slider(
                      value: selected.fontSize.clamp(12.0, 40.0).toDouble(),
                      min: 12,
                      max: 40,
                      divisions: 14,
                      label: selected.fontSize.round().toString(),
                      onChangeStart: (_) => widget.onActionStart(),
                      onChanged: (value) {
                        final current = _selectedText;
                        if (current != null) _replaceText(current.copyWith(fontSize: value));
                      },
                      onChangeEnd: (_) => widget.onActionEnd(),
                    ),
                  ),
                  IconButton(tooltip: 'Alinear a la izquierda', onPressed: () => _setAlignment(TextAlign.left), icon: const Icon(Icons.format_align_left)),
                  IconButton(tooltip: 'Centrar', onPressed: () => _setAlignment(TextAlign.center), icon: const Icon(Icons.format_align_center)),
                  IconButton(tooltip: 'Alinear a la derecha', onPressed: () => _setAlignment(TextAlign.right), icon: const Icon(Icons.format_align_right)),
                ],
              ],
            ),
          ),
        if (!widget.readOnly && _mode == CanvasMode.draw)
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final color in _colors)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: const Text('\u25CF'),
                      labelStyle: TextStyle(color: color, fontSize: 22),
                      selected: _selectedColor == color,
                      onSelected: (_) => setState(() => _selectedColor = color),
                    ),
                  ),
                const SizedBox(width: 8),
                const Center(child: Text('Grosor')),
                SizedBox(width: 140, child: Slider(value: _lineWidth, min: 2, max: 12, divisions: 5, onChanged: (value) => setState(() => _lineWidth = value))),
              ],
            ),
          ),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(color: Colors.grey.shade200, border: Border.all(color: Colors.grey.shade300)),
            child: SingleChildScrollView(
              controller: _horizontalScroll,
              scrollDirection: Axis.horizontal,
              child: SingleChildScrollView(
                controller: _verticalScroll,
                child: SizedBox(
                  width: 900,
                  height: _canvasHeight(),
                  child: Stack(
                    children: [
                      const Positioned.fill(child: ColoredBox(color: Colors.white)),
                      for (final block in widget.texts)
                        Positioned(
                          key: ValueKey(block.id),
                          left: block.x,
                          top: block.y,
                          width: block.width,
                          child: _BoardTextEditor(
                            block: block,
                            readOnly: widget.readOnly,
                            selected: block.id == _selectedTextId,
                            onSelected: () => setState(() => _selectedTextId = block.id),
                            onEdited: (text) {
                              _replaceText(block.copyWith(text: text), typed: true);
                            },
                            onDragStart: widget.onActionStart,
                            onMoved: (x, y) {
                              final current = widget.texts.firstWhere((item) => item.id == block.id);
                              _replaceText(current.copyWith(x: x.clamp(0.0, 900.0 - current.width).toDouble(), y: math.max(0.0, y)));
                            },
                            onDragEnd: widget.onActionEnd,
                          ),
                        ),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: _StrokesPainter(
                              [...widget.strokes, ?_draft],
                              eraserPosition: _eraserPosition,
                            ),
                          ),
                        ),
                      ),
                      if (!widget.readOnly && _mode != CanvasMode.write)
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onPanStart: _mode == CanvasMode.draw ? _startStroke : _startErasing,
                            onPanUpdate: _mode == CanvasMode.draw ? _extendStroke : (details) => _eraseAt(details.localPosition),
                            onPanEnd: (_) {
                              if (_mode == CanvasMode.draw) { _finishStroke(); } else { _finishErasing(); }
                            },
                            onPanCancel: () {
                              if (_mode == CanvasMode.draw) { _finishStroke(); } else { _finishErasing(); }
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BoardTextEditor extends StatefulWidget {
  const _BoardTextEditor({
    required this.block,
    required this.readOnly,
    required this.selected,
    required this.onSelected,
    required this.onEdited,
    required this.onDragStart,
    required this.onMoved,
    required this.onDragEnd,
  });

  final BoardText block;
  final bool readOnly;
  final bool selected;
  final VoidCallback onSelected;
  final ValueChanged<String> onEdited;
  final VoidCallback onDragStart;
  final void Function(double x, double y) onMoved;
  final VoidCallback onDragEnd;

  @override
  State<_BoardTextEditor> createState() => _BoardTextEditorState();
}

class _BoardTextEditorState extends State<_BoardTextEditor> {
  late final TextEditingController _controller;
  late double _dragX;
  late double _dragY;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.block.text);
  }

  @override
  void didUpdateWidget(covariant _BoardTextEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller.text != widget.block.text) {
      _controller.value = TextEditingValue(
        text: widget.block.text,
        selection: TextSelection.collapsed(offset: widget.block.text.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        border: Border.all(color: widget.selected ? Colors.blue : Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!widget.readOnly) GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onSelected,
            onPanStart: (_) {
              _dragX = widget.block.x;
              _dragY = widget.block.y;
              widget.onSelected();
              widget.onDragStart();
            },
            onPanUpdate: (details) {
              _dragX += details.delta.dx;
              _dragY += details.delta.dy;
              widget.onMoved(_dragX, _dragY);
            },
            onPanEnd: (_) => widget.onDragEnd(),
            onPanCancel: widget.onDragEnd,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [Icon(Icons.drag_indicator, size: 18), Text('Mover')],
            ),
          ),
          TextField(
            controller: _controller,
            readOnly: widget.readOnly,
            onTap: widget.readOnly ? null : widget.onSelected,
            onChanged: widget.readOnly ? null : widget.onEdited,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            textAlign: widget.block.align,
            style: TextStyle(fontSize: widget.block.fontSize, height: 1.5),
            decoration: const InputDecoration(hintText: 'Escribe aqu\u00ED', border: InputBorder.none),
          ),
        ],
      ),
    );
  }
}

class _StrokesPainter extends CustomPainter {
  const _StrokesPainter(this.strokes, {this.eraserPosition});
  final List<BoardStroke> strokes;
  final Offset? eraserPosition;

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;
      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = stroke.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      if (stroke.points.length == 1) {
        canvas.drawCircle(stroke.points.first, stroke.width / 2, paint..style = PaintingStyle.fill);
        continue;
      }
      final path = Path()..moveTo(stroke.points.first.dx, stroke.points.first.dy);
      for (final point in stroke.points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, paint);
    }
    if (eraserPosition != null) {
      canvas.drawCircle(
        eraserPosition!,
        18,
        Paint()..color = const Color(0xFF546E7A)..strokeWidth = 2..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _StrokesPainter oldDelegate) => true;
}

