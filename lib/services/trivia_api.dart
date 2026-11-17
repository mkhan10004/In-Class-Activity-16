import 'dart:convert';
import 'dart:math';

import 'package:html_unescape/html_unescape.dart';
import 'package:http/http.dart' as http;

/// Required Class A endpoint; no user-controlled substitutions.
const classAQuestionsUrl =
    'https://opentdb.com/api.php?amount=10&category=9&difficulty=easy&type=multiple';

enum ApiFault { none, badJson, apiCode, nineResults }

class QuizDataException implements Exception {
  const QuizDataException(this.message);
  final String message;
  @override
  String toString() => message;
}

class TooSoonException implements Exception {
  const TooSoonException(this.remainingSeconds);
  final int remainingSeconds;
  @override
  String toString() =>
      'OpenTDB limits requests. Try again in $remainingSeconds seconds.';
}

class TriviaQuestion {
  const TriviaQuestion({
    required this.question,
    required this.correctAnswer,
    required this.choices,
  });

  final String question;
  final String correctAnswer;
  final List<String> choices;
  int get correctIndex => choices.indexOf(correctAnswer);
}

class TriviaApi {
  TriviaApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  DateTime? _lastRequest;
  final HtmlUnescape _unescape = HtmlUnescape();

  Future<List<TriviaQuestion>> fetch({ApiFault fault = ApiFault.none}) async {
    final now = DateTime.now();
    final last = _lastRequest;
    if (last != null) {
      final ms = now.difference(last).inMilliseconds;
      if (ms < 5000) {
        throw TooSoonException(((5000 - ms) / 1000).ceil());
      }
    }
    _lastRequest = now; // Includes labeled injected calls; no auto-retry.

    String body;
    if (fault != ApiFault.none) {
      body = _injectedResponse(fault);
    } else {
      http.Response response;
      try {
        response = await _client
            .get(Uri.parse(classAQuestionsUrl))
            .timeout(const Duration(seconds: 10));
      } catch (e) {
        throw QuizDataException('Network request failed or timed out: $e');
      }
      if (response.statusCode != 200) {
        throw QuizDataException('HTTP ${response.statusCode}; not a valid quiz.');
      }
      body = response.body;
    }
    return decodeAndValidate(body);
  }

  /// Public for isolated model/validation tests.
  List<TriviaQuestion> decodeAndValidate(String body) {
    dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw const QuizDataException('Invalid JSON. The round was not started.');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const QuizDataException('API response must be an object.');
    }
    if (decoded['response_code'] is! int || decoded['response_code'] != 0) {
      throw QuizDataException(
        'OpenTDB response_code was ${decoded['response_code']} (expected 0).',
      );
    }
    final raw = decoded['results'];
    if (raw is! List || raw.length != 10) {
      throw const QuizDataException('Expected exactly 10 questions.');
    }
    final questions = <TriviaQuestion>[];
    for (var i = 0; i < 10; i++) {
      final obj = raw[i];
      if (obj is! Map<String, dynamic> ||
          obj['category'] != 'General Knowledge' ||
          obj['difficulty'] != 'easy' ||
          obj['type'] != 'multiple') {
        throw QuizDataException('Question ${i + 1} has an invalid category/type/difficulty.');
      }
      final question = _decodedText(obj['question']);
      final correct = _decodedText(obj['correct_answer']);
      final wrong = obj['incorrect_answers'];
      if (question.isEmpty || correct.isEmpty || wrong is! List || wrong.length != 3) {
        throw QuizDataException('Question ${i + 1} is missing required text or choices.');
      }
      final choices = [correct, ...wrong.map(_decodedText)];
      if (choices.any((choice) => choice.isEmpty) ||
          choices.map((choice) => choice.toLowerCase()).toSet().length != 4) {
        throw QuizDataException('Question ${i + 1} has blank or duplicate choices.');
      }
      choices.shuffle(Random()); // Once at load time, never from build().
      questions.add(TriviaQuestion(
        question: question,
        correctAnswer: correct,
        choices: List.unmodifiable(choices),
      ));
    }
    return List.unmodifiable(questions);
  }

  String _decodedText(dynamic input) => input is String
      ? _unescape.convert(input).trim()
      : '';

  String _injectedResponse(ApiFault fault) {
    if (fault == ApiFault.badJson) return '{not valid JSON';
    if (fault == ApiFault.apiCode) {
      return '{"response_code":5,"results":[]}';
    }
    // Clearly labeled development-only schema-validation fixture.
    return jsonEncode({
      'response_code': 0,
      'results': List.generate(9, (i) => {
        'category': 'General Knowledge',
        'difficulty': 'easy',
        'type': 'multiple',
        'question': 'Development fixture $i?',
        'correct_answer': 'Yes',
        'incorrect_answers': ['No', 'Maybe', 'Never'],
      }),
    });
  }

  void dispose() => _client.close();
}
