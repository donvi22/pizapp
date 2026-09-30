import 'package:flutter/material.dart';

import 'project.dart';

class BoardText {
  const BoardText({
    required this.id,
    required this.x,
    required this.y,
    required this.text,
    this.width = 360,
    this.fontSize = 18,
    this.align = TextAlign.left,
  });

  final String id;
  final double x;
  final double y;
  final double width;
  final String text;
  final double fontSize;
  final TextAlign align;

  BoardText copyWith({
    double? x,
    double? y,
    double? width,
    String? text,
    double? fontSize,
    TextAlign? align,
  }) => BoardText(
    id: id,
    x: x ?? this.x,
    y: y ?? this.y,
    width: width ?? this.width,
    text: text ?? this.text,
    fontSize: fontSize ?? this.fontSize,
    align: align ?? this.align,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'x': x,
    'y': y,
    'width': width,
    'text': text,
    'fontSize': fontSize,
    'align': align.name,
  };

  factory BoardText.fromJson(Map<String, dynamic> json) => BoardText(
    id: json['id'] as String,
    x: (json['x'] as num).toDouble(),
    y: (json['y'] as num).toDouble(),
    width: (json['width'] as num).toDouble(),
    text: json['text'] as String,
    fontSize: (json['fontSize'] as num).toDouble(),
    align: TextAlign.values.byName(json['align'] as String),
  );

  static List<BoardText> fromTask(ProjectTask task) {
    final rawTexts = task.canvasData['texts'];
    if (rawTexts is List) {
      return rawTexts
          .map((raw) => BoardText.fromJson(Map<String, dynamic>.from(raw as Map)))
          .toList();
    }
    if (task.description.isEmpty) return [];
    return [
      BoardText(
        id: 'original-${task.id}',
        x: 24,
        y: 24,
        width: 852,
        text: task.description,
      ),
    ];
  }
}