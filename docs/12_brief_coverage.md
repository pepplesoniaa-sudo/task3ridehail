# 12 Brief coverage: create, read, update, delete for every entity

This note says, for each of the 16 entities, which endpoint covers each of the four actions (create, read, update, delete), or why none exists. Endpoint ids are from `06_api_contracts.md` section 2 (EP01 to EP27, and the three internal jobs JB1 to JB3). A GAP means the brief asks for a behaviour that no endpoint reaches; the smallest contract addition is named, but no endpoint was actually added in this fix.

A general note before the table. The brief is a design for three apps (rider, driver, support) plus the payment provider. It never asks for a public sign up or a vehicle management screen, so several entities have no create endpoint on purpose, not by oversight. Those are marked "out of scope" with the reason, and are not counted as gaps.

## The matrix

| Entity | Create | Read | Update | Delete |
|---|---|---|---|---|
| rider | none, out of scope: riders are assumed to exist before the app is used; the brief has no sign up | EP06 (own trip list), EP03 (own trip), EP27 (own trip events), EP16 (support) | none, out of scope: no profile edit in the brief | EP25 (erasure, which anonymises in place) |
| driver | none, out of scope: drivers are assumed to exist; no driver onboarding in the brief | EP07 (own trip list), EP03 (own trip) | none, out of scope: no profile edit | EP26 (erasure, which anonymises in place) |
| vehicle | none, out of scope: vehicles belong to drivers but the brief has no vehicle screen | none directly; the plate is read back only as a snapshot in EP03 | none, out of scope | none, out of scope |
| trip | EP02 | EP03, EP06, EP07, EP27 | EP09, EP10, EP11, EP12, EP14 (status moves only) | none; a trip is never deleted |
| trip_status_history | written by triggers during EP02, EP09, EP10, EP11, EP12, EP14 and JB1 | EP04 | none; the table is append only | none; append only |
| location_ping | EP13 | EP05 (the latest point only) | none; a stored point is never edited | GAP: retention deletes old points, but no job in the brief does it. Smallest addition: one retention job, JB4, or a step folded into JB1 |
| fare_quote | EP01 | EP01 (in the answer), EP03 (inside the trip) | none; a quote is never edited | none; a quote simply expires by its time |
| payment | EP15 | EP16, EP03 (support view) | EP19 (the provider moves the status), EP20 (support fails a pending one) | none |
| refund | EP21 | EP16 (support view) | EP19 (the provider confirms it) | none |
| rating | EP17 | EP18 | none; a rating is never edited | none |
| idempotency_key | written as a side effect of EP02 and EP15 | none directly; the retry path reads it inside EP02 and EP15 | written as a side effect of EP02 and EP15 when the answer is stored | JB3 (cleanup of expired keys) |
| setting | EP23 (upsert) | EP22 | EP23 | none |
| support_admin | none, out of scope: staff are created outside the API | none directly | none, out of scope | none, out of scope |
| audit_log | written by triggers during EP19, EP20, EP21, EP23, and by the function in EP24 | none in the contract; the support console would read it outside the API | none; append only | none; append only |
| status_transition_rule | loaded by the migrations as reference data | none in the contract; the rows are listed in `03_state_machine.md` | none | none |
| provider_event | EP19 | EP16 (support view of the related payment) | EP19 (marking it handled) | none |

## The gaps found

Only one true gap was found, plus one optional addition.

1. GAP, retention of `location_ping`. The entity note in `02_entities.md` says points are kept "append only except for scheduled deletion" (source line 119), and the brief's data minimisation rule (B8) expects old points to go. No endpoint or job in `06_api_contracts.md` deletes them. Smallest addition: one internal job, for example JB4 "location retention", that deletes points older than a setting value, in the same way JB3 deletes expired keys. This is the smallest change because it adds a job only, not a new public route.
2. Optional, reading `audit_log` through the support console. Support notes are written (EP24) and the audit rows exist, but there is no route to read them back. This is not a gap against the brief, which only asks that sensitive actions be recorded. If the class wants the console to show them, the smallest addition is one read route, for example EP28 "GET a trip's audit rows", support only.

## What was not done

No endpoint was added. This note only reports what the current contract covers and names the smallest addition for the one gap. Adding JB4 and EP28 are recommendations for the owner, not changes made in this fix.
