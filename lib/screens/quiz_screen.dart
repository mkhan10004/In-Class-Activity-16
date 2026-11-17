import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/cloud_attempts.dart';
import '../services/trivia_api.dart';

enum QuizStage {
  loading,
  requestError,
  playing,
  readyToSubmit,
  submitting,
  verifying,
  saveUnknown,
  permissionDenied,
  verificationUnavailable,
  cloudVerified,
}

class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key, required this.user});
  final User user;

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  final TriviaApi _api = TriviaApi();
  final CloudAttempts _cloud = CloudAttempts();
  final TextEditingController _restoreId = TextEditingController();
  final TextEditingController _foreignUid = TextEditingController();
  final TextEditingController _foreignRound = TextEditingController();

  QuizStage _stage = QuizStage.loading;
  List<TriviaQuestion> _questions = [];
  List<int?> _selections = [];
  int _index = 0;
  int _score = 0;
  String _roundId = '';
  String _message = '';
  bool _busy = false;
  bool _knownCommitted = false;
  Map<String, Object>? _frozenFields;
  AttemptRecord? _verified;
  AttemptRecord? _restored;
  String? _restoreMessage;
  String? _ruleTestResult;

  ApiFault _apiFault = ApiFault.none;
  CloudFault _cloudFault = CloudFault.none;

  String get _uid => widget.user.uid;
  String get _path => 'users/$_uid/attempts/$_roundId';
  bool get _unresolved => _busy ||
      _stage == QuizStage.saveUnknown ||
      _stage == QuizStage.verificationUnavailable ||
      _stage == QuizStage.submitting ||
      _stage == QuizStage.verifying;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _newRound());
  }

  @override
  void dispose() {
    _api.dispose();
    _restoreId.dispose();
    _foreignUid.dispose();
    _foreignRound.dispose();
    super.dispose();
  }

  bool _isCurrent(String uid, String id) =>
      mounted && _uid == uid && _roundId == id &&
      FirebaseAuth.instance.currentUser?.uid == uid;

  Future<void> _newRound() async {
    if (_unresolved) return;
    setState(() {
      _roundId = _cloud.newRoundId(_uid);
      _questions = [];
      _selections = [];
      _index = 0;
      _score = 0;
      _frozenFields = null;
      _knownCommitted = false;
      _verified = null;
      _message = '';
      _stage = QuizStage.loading;
    });
    await _loadQuestions();
  }

  Future<void> _loadQuestions() async {
    if (_busy) return;
    final uid = _uid;
    final id = _roundId;
    setState(() { _busy = true; _stage = QuizStage.loading; _message = ''; });
    try {
      final fetched = await _api.fetch(fault: kDebugMode ? _apiFault : ApiFault.none);
      if (!_isCurrent(uid, id)) return;
      setState(() {
        _questions = fetched;
        _selections = List<int?>.filled(10, null);
        _stage = QuizStage.playing;
      });
    } catch (e) {
      if (!_isCurrent(uid, id)) return;
      setState(() {
        _message = 'Questions unavailable: $e. Use Retry, with at least 5 seconds between requests.';
        _stage = QuizStage.requestError;
      });
    } finally {
      if (_isCurrent(uid, id)) setState(() => _busy = false);
    }
  }

  void _choose(int choiceIndex) {
    if (_stage != QuizStage.playing || _selections[_index] != null) return;
    setState(() {
      _selections[_index] = choiceIndex;
      if (choiceIndex == _questions[_index].correctIndex) _score++;
    });
  }

  void _continue() {
    if (_stage != QuizStage.playing || _selections[_index] == null) return;
    setState(() {
      if (_index < 9) {
        _index++;
      } else {
        _frozenFields = _cloud.frozenFields(_score);
        _stage = QuizStage.readyToSubmit;
      }
    });
  }

  void _cloudError(Object e, {required bool duringVerification}) {
    if (e is AttemptCollision) {
      _stage = QuizStage.permissionDenied;
      _message = 'ID collision / payload mismatch. Original attempt was not changed. $e';
    } else if (e is FirebaseException && e.code == 'permission-denied') {
      _stage = QuizStage.permissionDenied;
      _message = 'permission-denied: verify you are the owner and the exact six-field rules are deployed.';
    } else if (e is FirebaseException && e.code == 'unauthenticated') {
      _stage = QuizStage.permissionDenied;
      _message = 'unauthenticated: sign in again. No success was claimed.';
    } else if (duringVerification) {
      _stage = QuizStage.verificationUnavailable;
      _message = 'Verification unavailable: $e. A save may already exist. Retry SERVER READ; do not create a new ID.';
    } else {
      _stage = QuizStage.saveUnknown;
      if (e is LostAcknowledgement) {
        _message = 'INJECTED lost acknowledgement after real transaction. Save status UNKNOWN. Use Recover via server read.';
      } else if (e is FirebaseException && e.code == 'resource-exhausted') {
        _message = 'resource-exhausted: simulated quota error. Save status UNKNOWN; no automatic retries.';
      } else if (e is FirebaseException && e.code == 'unavailable') {
        _message = 'unavailable/offline: save status UNKNOWN. Reconnect and recover using the same ID.';
      } else {
        _message = 'Save status UNKNOWN: $e. Verify from server before retrying.';
      }
    }
  }

  Future<void> _submit() async {
    if (_stage != QuizStage.readyToSubmit || _busy || _frozenFields == null) return;
    final uid = _uid;
    final id = _roundId;
    final fixed = _frozenFields!;
    setState(() { _busy = true; _stage = QuizStage.submitting; _message = ''; });
    try {
      await _cloud.createOnce(
        uid: uid, roundId: id, fixedFields: fixed,
        fault: kDebugMode ? _cloudFault : CloudFault.none,
      );
      if (!_isCurrent(uid, id)) return;
      _knownCommitted = true;
    } catch (e) {
      if (!_isCurrent(uid, id)) return;
      setState(() {
        _busy = false;
        _cloudError(e, duringVerification: false);
      });
      return;
    }

    try {
      if (!_isCurrent(uid, id)) return;
      setState(() => _stage = QuizStage.verifying);
      final result = await _cloud.readExact(
        uid: uid, roundId: id, expectedFields: fixed,
      );
      if (!_isCurrent(uid, id)) return;
      if (result == null) {
        setState(() => _cloudError(
          StateError('Committed document missing from server'),
          duringVerification: true,
        ));
      } else {
        setState(() {
          _verified = result;
          _stage = QuizStage.cloudVerified;
          _message = 'Cloud verified by Source.server. No pending writes and all six fields match.';
        });
      }
    } catch (e) {
      if (_isCurrent(uid, id)) {
        setState(() => _cloudError(e, duringVerification: true));
      }
    } finally {
      if (_isCurrent(uid, id)) setState(() => _busy = false);
    }
  }

  /// First read from server. Never resubmit while an operation is in flight.
  /// If the server confirms absence, permit an explicit same-ID submit.
  Future<void> _recover() async {
    if (_busy || _frozenFields == null ||
        (_stage != QuizStage.saveUnknown &&
         _stage != QuizStage.verificationUnavailable)) return;
    final uid = _uid;
    final id = _roundId;
    final prior = _stage;
    setState(() { _busy = true; _stage = QuizStage.verifying; _message = ''; });
    try {
      final record = await _cloud.readExact(
        uid: uid, roundId: id, expectedFields: _frozenFields,
      );
      if (!_isCurrent(uid, id)) return;
      if (record != null) {
        setState(() {
          _verified = record;
          _knownCommitted = true;
          _stage = QuizStage.cloudVerified;
          _message = 'Recovered: SAME round ID matched a real Source.server read. Exactly one attempt.';
        });
      } else if (_knownCommitted || prior == QuizStage.verificationUnavailable) {
        setState(() {
          _stage = QuizStage.verificationUnavailable;
          _message = 'Unexpected absence after a known completed transaction. Do not replay or overwrite; inspect console/rules.';
        });
      } else {
        setState(() {
          _stage = QuizStage.readyToSubmit;
          _message = 'Server confirms no attempt at this ID. You may submit again; the SAME round ID is retained.';
        });
      }
    } catch (e) {
      if (_isCurrent(uid, id)) {
        setState(() => _cloudError(e, duringVerification: prior == QuizStage.verificationUnavailable));
      }
    } finally {
      if (_isCurrent(uid, id)) setState(() => _busy = false);
    }
  }

  Future<void> _retrieveSaved() async {
    if (_busy) return;
    final requestedId = _restoreId.text.trim();
    if (requestedId.isEmpty || requestedId.contains('/')) {
      setState(() => _restoreMessage = 'Enter an exact round document ID (no slashes).');
      return;
    }
    final uid = _uid;
    setState(() { _restoreMessage = 'Reading this exact document from SERVER…'; _restored = null; });
    try {
      final record = await _cloud.readExact(uid: uid, roundId: requestedId);
      if (!mounted || FirebaseAuth.instance.currentUser?.uid != uid) return;
      setState(() {
        _restored = record;
        _restoreMessage = record == null
            ? 'No document exists at that ID on the server.'
            : 'Retrieved and validated original record via Source.server.';
      });
    } catch (e) {
      if (mounted && FirebaseAuth.instance.currentUser?.uid == uid) {
        setState(() => _restoreMessage = 'Server retrieval unavailable: $e');
      }
    }
  }

  Future<void> _runRulesProbe(String label, Future<void> Function() work) async {
    if (_busy) return;
    setState(() { _busy = true; _ruleTestResult = '$label: checking deployed rules…'; });
    try {
      await work();
      if (mounted) setState(() => _ruleTestResult =
          '$label: UNEXPECTED ALLOWED. This test FAILS; inspect deployed security rules.');
    } on FirebaseException catch (e) {
      if (mounted) setState(() => _ruleTestResult = e.code == 'permission-denied'
          ? '$label: PASS - permission-denied from deployed Firestore.'
          : '$label: inconclusive (${e.code}): ${e.message}');
    } catch (e) {
      if (mounted) setState(() => _ruleTestResult = '$label: inconclusive error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    if (_unresolved) return;
    try {
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sign-out error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('General Knowledge • Class A'),
        actions: [
          IconButton(
            onPressed: _unresolved ? null : _signOut,
            tooltip: _unresolved ? 'Resolve submission before signing out' : 'Sign out',
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              _headerCard(context),
              const SizedBox(height: 12),
              _stageCard(context),
              const SizedBox(height: 16),
              _restoreCard(context),
              if (kDebugMode) ...[
                const SizedBox(height: 16),
                _debugControls(context),
              ],
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _headerCard(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Authenticated account', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(widget.user.email ?? '(email unavailable)'),
        SelectableText('UID: $_uid', style: Theme.of(context).textTheme.bodySmall),
        const Divider(height: 22),
        const Text('10 easy questions • 4 answers each • 1 point per question'),
        if (_roundId.isNotEmpty) ...[
          const SizedBox(height: 6),
          SelectableText('Round ID: $_roundId', style: Theme.of(context).textTheme.bodySmall),
        ],
      ]),
    ),
  );

  Widget _stageCard(BuildContext context) {
    switch (_stage) {
      case QuizStage.loading:
        return _infoCard(
          icon: Icons.hourglass_top, title: 'Loading questions',
          body: 'Fetching and checking all 10 questions. The quiz cannot start until validation passes.',
          loading: true,
        );
      case QuizStage.requestError:
        return _infoCard(
          icon: Icons.warning_amber_rounded, title: 'Question request error', body: _message,
          action: FilledButton.icon(
            onPressed: _busy ? null : _loadQuestions,
            icon: const Icon(Icons.refresh), label: const Text('Retry request'),
          ),
        );
      case QuizStage.playing:
        return _playCard(context);
      case QuizStage.readyToSubmit:
      case QuizStage.submitting:
      case QuizStage.verifying:
      case QuizStage.saveUnknown:
      case QuizStage.permissionDenied:
      case QuizStage.verificationUnavailable:
      case QuizStage.cloudVerified:
        return _resultCard(context);
    }
  }

  Widget _playCard(BuildContext context) {
    final question = _questions[_index];
    final chosen = _selections[_index];
    final answered = chosen != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Question ${_index + 1} of 10', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: (_index + 1) / 10),
          const SizedBox(height: 20),
          Text(question.question, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 18),
          ...List.generate(4, (i) {
            final correct = question.correctIndex == i;
            final picked = chosen == i;
            final showCorrect = answered && correct;
            final showWrong = answered && picked && !correct;
            final color = showCorrect
                ? Colors.green.shade700
                : showWrong ? Colors.red.shade700 : null;
            final icon = showCorrect ? Icons.check_circle : showWrong ? Icons.cancel : Icons.circle_outlined;
            return Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: OutlinedButton.icon(
                onPressed: answered ? null : () => _choose(i),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                  alignment: Alignment.centerLeft,
                  foregroundColor: color,
                  side: BorderSide(color: color ?? Theme.of(context).dividerColor),
                ),
                icon: Icon(icon, color: color),
                label: Text(question.choices[i], style: TextStyle(color: color)),
              ),
            );
          }),
          if (answered) ...[
            const SizedBox(height: 10),
            Row(children: [
              Icon(chosen == question.correctIndex ? Icons.check_circle : Icons.info_outline,
                  color: chosen == question.correctIndex ? Colors.green.shade700 : Colors.red.shade700),
              const SizedBox(width: 8),
              Expanded(child: Text(
                chosen == question.correctIndex
                    ? 'Correct! You earned 1 point.'
                    : 'Incorrect. Correct answer: ${question.correctAnswer}',
              )),
            ]),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _continue,
              child: Text(_index == 9 ? 'Review all 10 answers' : 'Next question'),
            ),
          ],
          const SizedBox(height: 8),
          Text('Score so far: $_score / 10', style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
    );
  }

  Widget _resultCard(BuildContext context) {
    final verified = _stage == QuizStage.cloudVerified;
    final stageLabel = switch (_stage) {
      QuizStage.readyToSubmit => 'Ready to submit',
      QuizStage.submitting => 'Submitting to Firestore',
      QuizStage.verifying => 'Verifying from SERVER',
      QuizStage.saveUnknown => 'Save status UNKNOWN',
      QuizStage.permissionDenied => 'Submission blocked',
      QuizStage.verificationUnavailable => 'Verification unavailable',
      QuizStage.cloudVerified => 'Cloud verified',
      _ => 'Review',
    };
    final messageColor = verified ? Colors.green.shade800 :
        (_stage == QuizStage.saveUnknown || _stage == QuizStage.verificationUnavailable
            ? Colors.orange.shade900 : Theme.of(context).colorScheme.onSurface);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Final score: $_score / 10', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 7),
          Row(children: [
            Icon(verified ? Icons.verified : Icons.cloud_outlined, color: messageColor),
            const SizedBox(width: 8),
            Expanded(child: Text(stageLabel, style: TextStyle(color: messageColor, fontWeight: FontWeight.bold))),
          ]),
          if (_message.isNotEmpty) ...[
            const SizedBox(height: 7),
            Text(_message),
          ],
          if (_busy) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 12),
          SelectableText('Firestore path: $_path'),
          if (_verified != null) ...[
            const SizedBox(height: 6),
            SelectableText('schemaVersion: 1 | variant: A | categoryId: 9\n'
                'questionCount: 10 | correctCount: ${_verified!.correctCount}\n'
                'submittedAt (server): ${_verified!.submittedAt.toDate().toIso8601String()}'),
          ],
          const Divider(height: 28),
          Text('Review — all 10 answers', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          ...List.generate(_questions.length, (i) {
            final q = _questions[i];
            final selected = _selections[i];
            final good = selected == q.correctIndex;
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(good ? Icons.check_circle : Icons.cancel,
                  color: good ? Colors.green.shade700 : Colors.red.shade700, size: 21),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${i + 1}. ${q.question}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text('You chose: ${selected == null ? '(none)' : q.choices[selected]}'),
                  Text('Correct: ${q.correctAnswer}'),
                ])),
              ]),
            );
          }),
          Wrap(spacing: 10, runSpacing: 8, children: [
            if (_stage == QuizStage.readyToSubmit)
              FilledButton.icon(
                onPressed: _busy ? null : _submit,
                icon: const Icon(Icons.cloud_upload), label: const Text('Submit once'),
              ),
            if (_stage == QuizStage.readyToSubmit)
              OutlinedButton.icon(
                onPressed: _busy ? null : () async {
                  final discard = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('Replay without saving?'),
                      content: const Text(
                        'This completed round has not been submitted to Firestore. '
                        'Replay will discard its answers and create a new round ID.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          child: const Text('Keep this round'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(dialogContext, true),
                          child: const Text('Discard and replay'),
                        ),
                      ],
                    ),
                  );
                  if (discard == true && mounted && !_unresolved) _newRound();
                },
                icon: const Icon(Icons.replay),
                label: const Text('Replay (discard unsaved)'),
              ),
            if (_stage == QuizStage.saveUnknown || _stage == QuizStage.verificationUnavailable)
              FilledButton.icon(
                onPressed: _busy ? null : _recover,
                icon: const Icon(Icons.cloud_sync), label: const Text('Recover — server read'),
              ),
            if (verified)
              FilledButton.icon(
                onPressed: _busy ? null : _newRound,
                icon: const Icon(Icons.replay), label: const Text('Replay (new round ID)'),
              ),
            if (_stage == QuizStage.permissionDenied)
              const Text('Correct the Firebase rules/account first; the existing record will never be overwritten.'),
          ]),
        ]),
      ),
    );
  }

  Widget _restoreCard(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('T07 • Retrieve after app restart', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        const Text('Copy the exact Round ID after saving, restart the app, sign in as the SAME user, paste it here. No device storage is used.'),
        const SizedBox(height: 10),
        TextField(controller: _restoreId, autocorrect: false,
          decoration: const InputDecoration(labelText: 'Previously saved round ID', border: OutlineInputBorder())),
        const SizedBox(height: 10),
        OutlinedButton.icon(onPressed: _busy ? null : _retrieveSaved,
          icon: const Icon(Icons.search), label: const Text('Get exact attempt from server')),
        if (_restoreMessage != null) ...[const SizedBox(height: 8), Text(_restoreMessage!)],
        if (_restored != null) ...[
          const SizedBox(height: 8),
          SelectableText('Path: ${_restored!.path}\n'
              'Score: ${_restored!.correctCount}/10\n'
              'Server timestamp: ${_restored!.submittedAt.toDate().toIso8601String()}'),
        ],
      ]),
    ),
  );

  Widget _debugControls(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: ExpansionTile(
        title: const Text('Development tests • T03, T09–T12'),
        subtitle: const Text('DEBUG ONLY. Real server writes/reads; injections are labeled.'),
        children: [
          const SizedBox(height: 10),
          const Text('T03: select malformed API response, then start fresh or tap Retry request. Wait 5+ seconds between requests.'),
          OutlinedButton(
            onPressed: _unresolved ? null : _newRound,
            child: const Text('T03 start a fresh round (DEBUG)'),
          ),
          DropdownButton<ApiFault>(
            isExpanded: true, value: _apiFault,
            items: ApiFault.values.map((fault) => DropdownMenuItem(
              value: fault, child: Text('API: ${fault.name} ${fault == ApiFault.none ? '(real URL)' : '(INJECTED)'}'),
            )).toList(),
            onChanged: _busy ? null : (v) => setState(() => _apiFault = v ?? ApiFault.none),
          ),
          const Divider(),
          const Text('T09/T12: choose failure before Submit. Lost acknowledgement performs a REAL commit then hides its acknowledgement.'),
          DropdownButton<CloudFault>(
            isExpanded: true, value: _cloudFault,
            items: CloudFault.values.map((fault) => DropdownMenuItem(
              value: fault, child: Text('Cloud: ${fault.name} ${fault == CloudFault.none ? '(real)' : '(INJECTED)'}'),
            )).toList(),
            onChanged: _busy ? null : (v) => setState(() => _cloudFault = v ?? CloudFault.none),
          ),
          const Divider(),
          const Text('T10: sign in as test user B. Paste user A UID and saved round ID. A read and a write must BOTH be denied.'),
          TextField(controller: _foreignUid,
            decoration: const InputDecoration(labelText: 'Other user UID (A)', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(controller: _foreignRound,
            decoration: const InputDecoration(labelText: 'Other user round ID', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton(onPressed: _busy ? null : () {
              final uid = _foreignUid.text.trim(); final id = _foreignRound.text.trim();
              if (uid.isEmpty || id.isEmpty || uid == _uid || uid.contains('/') || id.contains('/')) {
                setState(() => _ruleTestResult = 'Enter a different UID and a valid round ID.'); return;
              }
              _runRulesProbe('T10 foreign read', () => _cloud.attemptForeignRead(uid, id));
            }, child: const Text('T10 read A as B')),
            OutlinedButton(onPressed: _busy ? null : () {
              final uid = _foreignUid.text.trim(); final id = _foreignRound.text.trim();
              if (uid.isEmpty || id.isEmpty || uid == _uid || uid.contains('/') || id.contains('/')) {
                setState(() => _ruleTestResult = 'Enter a different UID and a valid round ID.'); return;
              }
              _runRulesProbe('T10 foreign write', () => _cloud.attemptForeignWrite(uid, id));
            }, child: const Text('T10 write A as B')),
          ]),
          const Divider(),
          const Text('T11: these are intentionally invalid REAL requests to the deployed Firestore rules. Existing saved attempts must remain unchanged.'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton(onPressed: _busy ? null : () =>
              _runRulesProbe('T11 score 11', () => _cloud.attemptBadScore(_uid)),
              child: const Text('Score = 11')),
            OutlinedButton(onPressed: _busy ? null : () =>
              _runRulesProbe('T11 extra field', () => _cloud.attemptExtraField(_uid)),
              child: const Text('Extra field')),
            OutlinedButton(onPressed: _busy || _verified == null ? null : () =>
              _runRulesProbe('T11 update', () => _cloud.attemptUpdate(_uid, _verified!.roundId)),
              child: const Text('Update saved attempt')),
          ]),
          if (_ruleTestResult != null) ...[const SizedBox(height: 10), SelectableText(_ruleTestResult!)],
        ],
      ),
    ),
  );

  Widget _infoCard({
    required IconData icon,
    required String title,
    required String body,
    Widget? action,
    bool loading = false,
  }) => Card(
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 35),
        const SizedBox(height: 12),
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        Text(body),
        if (loading) ...[const SizedBox(height: 16), const LinearProgressIndicator()],
        if (action != null) ...[const SizedBox(height: 16), action],
      ]),
    ),
  );
}
