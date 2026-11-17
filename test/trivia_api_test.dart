import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ica16_quiz/services/trivia_api.dart';

Map<String, dynamic> fixture(int i) => {
  'category': 'General Knowledge', 'type': 'multiple', 'difficulty': 'easy',
  'question': 'Q $i &amp; more?',
  'correct_answer': 'A &amp; B',
  'incorrect_answers': ['C', 'D', 'E'],
};

String bodyOf(List<dynamic> results, {int code = 0}) =>
    jsonEncode({'response_code': code, 'results': results});

void main() {
  final api = TriviaApi();
  test('exact 10 validated questions; HTML decoded; choices stable', () {
    final data = api.decodeAndValidate(bodyOf(List.generate(10, fixture)));
    expect(data.length, 10);
    expect(data.first.question, contains('& more?'));
    expect(data.first.correctAnswer, 'A & B');
    expect(data.first.choices.toSet().length, 4);
    final choices = List<String>.of(data.first.choices);
    expect(data.first.choices, orderedEquals(choices));
  });
  test('reject response_code nonzero', () {
    expect(() => api.decodeAndValidate(bodyOf([], code: 5)), throwsA(isA<QuizDataException>()));
  });
  test('reject bad JSON', () {
    expect(() => api.decodeAndValidate('{broken'), throwsA(isA<QuizDataException>()));
  });
  test('reject nine questions', () {
    expect(() => api.decodeAndValidate(bodyOf(List.generate(9, fixture))), throwsA(isA<QuizDataException>()));
  });
  test('reject duplicate choices after HTML decoding', () {
    final items = List.generate(10, fixture);
    items[0]['incorrect_answers'] = ['A & B', 'D', 'E'];
    expect(() => api.decodeAndValidate(bodyOf(items)), throwsA(isA<QuizDataException>()));
  });
  test('reject wrong category and wrong type', () {
    final items = List.generate(10, fixture);
    items[1]['category'] = 'Sports';
    expect(() => api.decodeAndValidate(bodyOf(items)), throwsA(isA<QuizDataException>()));
  });
}
