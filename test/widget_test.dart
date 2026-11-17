// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ica16_quiz/main.dart';

void main() {
  testWidgets('Quiz app renders setup guidance when Firebase is unavailable',
      (WidgetTester tester) async {
    await tester.pumpWidget(QuizApp(setupError: Exception('Firebase not configured')));

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('Firebase setup required'), findsOneWidget);
    expect(find.textContaining('Connect this app to your Firebase project'), findsOneWidget);
  });
}
