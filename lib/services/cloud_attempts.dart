import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

/// Development-only fault selections. In release, debug controls are hidden.
enum CloudFault { none, lostAcknowledgement, unavailable, resourceExhausted }

class LostAcknowledgement implements Exception {
  const LostAcknowledgement();
  @override
  String toString() => 'INJECTED: the real transaction committed, but its acknowledgement was hidden.';
}

class AttemptCollision implements Exception {
  const AttemptCollision();
  @override
  String toString() => 'Collision: this round ID already contains different or invalid data.';
}

class AttemptRecord {
  const AttemptRecord({
    required this.uid,
    required this.roundId,
    required this.correctCount,
    required this.submittedAt,
  });

  final String uid;
  final String roundId;
  final int correctCount;
  final Timestamp submittedAt;
  String get path => 'users/$uid/attempts/$roundId';
}

class CloudAttempts {
  CloudAttempts({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;

  String newRoundId(String uid) =>
      _db.collection('users').doc(uid).collection('attempts').doc().id;

  DocumentReference<Map<String, dynamic>> reference(String uid, String roundId) =>
      _db.doc('users/$uid/attempts/$roundId');

  Map<String, Object> frozenFields(int score) => Map.unmodifiable({
        'schemaVersion': 1,
        'variant': 'A',
        'categoryId': 9,
        'questionCount': 10,
        'correctCount': score,
      });

  bool _fixedFieldsMatch(Map<String, dynamic>? actual, Map<String, Object> expected) =>
      actual != null && expected.entries.every((e) => actual[e.key] == e.value);

  /// A transaction reads before writing and NEVER overwrites a document.
  /// The callback has no UI state changes, random IDs, or network calls.
  Future<void> createOnce({
    required String uid,
    required String roundId,
    required Map<String, Object> fixedFields,
    CloudFault fault = CloudFault.none,
  }) async {
    if (fault == CloudFault.unavailable) {
      throw FirebaseException(
        plugin: 'cloud_firestore', code: 'unavailable',
        message: 'INJECTED: backend unavailable',
      );
    }
    if (fault == CloudFault.resourceExhausted) {
      throw FirebaseException(
        plugin: 'cloud_firestore', code: 'resource-exhausted',
        message: 'INJECTED: quota exhausted',
      );
    }

    final docRef = reference(uid, roundId);
    await _db.runTransaction<void>((transaction) async {
      final existing = await transaction.get(docRef);
      if (existing.exists) {
        if (!_fixedFieldsMatch(existing.data(), fixedFields)) {
          throw const AttemptCollision();
        }
        return; // Matching prior commit: reuse; do not update.
      }
      transaction.set(docRef, {
        ...fixedFields,
        'submittedAt': FieldValue.serverTimestamp(),
      });
    });

    // T09: Only the acknowledgement is suppressed. The real write above ran.
    if (fault == CloudFault.lostAcknowledgement) {
      throw const LostAcknowledgement();
    }
  }

  Future<AttemptRecord?> readExact({
    required String uid,
    required String roundId,
    Map<String, Object>? expectedFields,
  }) async {
    final snapshot = await reference(uid, roundId)
        .get(const GetOptions(source: Source.server)); // Never SDK cache.
    if (!snapshot.exists) return null;
    if (snapshot.metadata.isFromCache || snapshot.metadata.hasPendingWrites) {
      throw StateError('Not cloud proof: cached or pending write.');
    }
    final data = snapshot.data();
    if (data == null || data.length != 6 ||
        data['schemaVersion'] is! int || data['schemaVersion'] != 1 ||
        data['variant'] is! String || data['variant'] != 'A' ||
        data['categoryId'] is! int || data['categoryId'] != 9 ||
        data['questionCount'] is! int || data['questionCount'] != 10 ||
        data['correctCount'] is! int ||
        (data['correctCount'] as int) < 0 || (data['correctCount'] as int) > 10 ||
        data['submittedAt'] is! Timestamp) {
      throw const AttemptCollision();
    }
    if (expectedFields != null && !_fixedFieldsMatch(data, expectedFields)) {
      throw const AttemptCollision();
    }
    return AttemptRecord(
      uid: uid,
      roundId: roundId,
      correctCount: data['correctCount'] as int,
      submittedAt: data['submittedAt'] as Timestamp,
    );
  }

  /// These tests send REAL writes/reads against deployed rules. Never use
  /// relaxed rules or a test-only backdoor in production.
  Future<void> attemptForeignRead(String uid, String roundId) async {
    await reference(uid, roundId).get(const GetOptions(source: Source.server));
  }

  Future<void> attemptForeignWrite(String uid, String roundId) async {
    await reference(uid, roundId).set({
      ...frozenFields(5), 'submittedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> attemptBadScore(String uid) async {
    await reference(uid, newRoundId(uid)).set({
      ...frozenFields(11), 'submittedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> attemptExtraField(String uid) async {
    await reference(uid, newRoundId(uid)).set({
      ...frozenFields(5),
      'submittedAt': FieldValue.serverTimestamp(),
      'injectedExtra': true,
    });
  }

  Future<void> attemptUpdate(String uid, String roundId) async {
    await reference(uid, roundId).update({'correctCount': 0});
  }
}
