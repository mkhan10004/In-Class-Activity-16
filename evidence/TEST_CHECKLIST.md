# ICA16 Class A — Undergraduate test checklist

**Do not mark PASS until you actually perform the test on your real deployed Firebase project.**

Record for each test: timestamp/timezone, app commit hash, device/Android version, user A or B (redacted), round ID suffix, precondition, action, expected result, actual observed result, PASS/FAIL, screenshot filename / console evidence, and correction (if failed first).

| ID | Action | Required observation | Your result |
|---|---|---|---|
| T01 | Sign in with valid then invalid credentials | Valid user UID; useful auth error, no passwords logged | NOT RUN |
| T02 | Load exact Class A API URL | Ten valid easy category 9 multiple-choice questions | NOT RUN |
| T03 | Debug inject bad JSON, nonzero response code, nine results | Each blocks play and shows manual rate-limited retry | NOT RUN |
| T04 | Answer right, wrong, double-tap | Decoded text, fixed choice order, score increments once | NOT RUN |
| T05 | Finish round and replay | Review all ten, correct total, new ID and cleared answers | NOT RUN |
| T06 | Submit online, double tap | One six-field server document, resolved timestamp and matching Source.server read | NOT RUN |
| T07 | Restart app and retrieve same ID as user A | Exact old attempt retrieved from server | NOT RUN |
| T08 | Submit offline, reconnect | Never falsely claims success; same-ID recovery | NOT RUN |
| T09 | Inject lost acknowledgement after real transaction | `saveUnknown`, server-only recovery, exactly one document | NOT RUN |
| T10 | Sign in B, try A's read and write | Both denied by deployed owner rules | NOT RUN |
| T11 | Score 11, extra field, update | All denied; existing record unchanged | NOT RUN |
| T12 | Inject unavailable and resource-exhausted | Distinct errors, manual bounded recovery, no false success | NOT RUN |

## Screenshots to capture

- Sign-in success and visible invalid sign-in error (never show passwords)
- Class A quiz with question progress, feedback and completed ten-answer review
- Firestore Console: `users/{uid}/attempts/{roundId}` with exactly six typed fields (redact UID as needed)
- App showing `Cloud verified` with matching document path, score and timestamp
- Post-restart server retrieval of exact old ID
- `saveUnknown` before and `Cloud verified` after lost-ack recovery
- Each denied rules probe, and errors from bad JSON / API code / nine questions / unavailable / quota injection
- A failed-first correction and four checkpoint screenshots/logs

## Six written prompts (120–180 words EACH)

1. **Two success layers:** HTTP 200 vs. `response_code==0`; schema validation, cite T02/T03.
2. **Unknown is not failed:** your actual T09 trace, `saveUnknown` and verified moment, ID suffix.
3. **Retry identity:** same ID vs new ID and collision from mismatched score.
4. **Cloud trust:** B denied vs. A's potentially fabricated in-range score, trusted backend proposal.
5. **AI critique:** fictional schema prompt, tool/date, response excerpt, two tested claims, one flaw, corrected design. Disclose assistance.
6. **Personal design defense:** loading/error/feedback cue, recovery trade-off, screenshot and failed-first fix.

Graduates-only G01/G02/G03 are deliberately not included in this UG package.
