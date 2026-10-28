import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dot_matrix_timer/main.dart';

void main() {
  testWidgets('app builds and shows timer', (WidgetTester tester) async {
    await tester.pumpWidget(const DotMatrixTimerApp());
    await tester.pump();

    expect(find.text('00:00'), findsOneWidget);
    expect(find.text('Tap a dot to set minutes'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
  });
}
