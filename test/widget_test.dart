import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Flutter test environment renders a widget', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Text('NaeemSoft Restaurant')));
    expect(find.text('NaeemSoft Restaurant'), findsOneWidget);
  });
}
