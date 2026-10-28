import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dot_matrix_timer/main.dart';

void main() {
  testWidgets('app builds and shows timer', (WidgetTester tester) async {
    await tester.pumpWidget(const DotMatrixTimerApp());
    await tester.pump();

    expect(find.text('60:00'), findsOneWidget);
    expect(find.text('Press a dot to start  •  Hold screen to end'), findsOneWidget);
    expect(find.byType(GridView), findsOneWidget);
  });
}
