class StrokePoint {
  final double x; // Normalized 0.0 to 1.0 on canvas
  final double y; // Normalized 0.0 to 1.0 on canvas
  final double pressure; // Stylus pressure

  StrokePoint({required this.x, required this.y, required this.pressure});

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'pressure': pressure};

  factory StrokePoint.fromJson(Map<String, dynamic> json) {
    return StrokePoint(
      x: json['x'] as double,
      y: json['y'] as double,
      pressure: json['pressure'] as double,
    );
  }
}