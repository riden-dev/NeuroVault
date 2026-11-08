import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:neurovault/ui/screens/home_screen.dart';

void main() {
  testWidgets('HomeScreen renders three main rounded buttons', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: HomeScreen(),
        ),
      ),
    );

    expect(find.text('Visions'), findsOneWidget);
    expect(find.text('Routines'), findsOneWidget);
    expect(find.text('To-Do List'), findsOneWidget);
  });
}
