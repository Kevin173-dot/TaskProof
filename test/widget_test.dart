import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskguard/main.dart';

void main() {
  testWidgets('login screen shows the primary authentication options', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: LoginPage()));

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Log in'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Continue with Apple'), findsOneWidget);
  });
}
