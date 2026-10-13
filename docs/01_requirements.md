# 01 Requirements: Ride Hailing Service

## 1. Product
1.1 Riders request trips and see a fare estimate.
1.2 Drivers accept and drive them; riders pay through an outside provider.
1.3 Both sides rate each other; support can investigate any trip.

## 2. Users
- U1 Rider.
- U2 Driver.
- U3 Support admin: reads trips and payments, cancels, refunds.
- U4 Payment provider: external system; may report results twice or late.

## 3. Five key actions
Proposal kept unchanged: the five cover the money path. Cancellation (B9) is a state change, not a sixth action; the state machine handles it (B5).

- A1 Rider requests a trip (pickup, dropoff, estimate). Success: one "requested" trip with a stored estimate. Fails: missing locations, outside service area, rider already active (B1), retry (B6).
- A2 Driver accepts. Success: exactly one driver assigned. Fails: two accept at once, driver already active (B2), rider cancelled first.
- A3 Driver moves trip to arrived, started, completed; rider watches. Success: steps recorded in order. Fails: steps skipped or repeated, location updates lost.
- A4 Rider pays. One payment covers exactly one fare or one cancellation fee. Fails: declined card, timeout, duplicate callback. A retried payment request creates no second charge (B6).
- A5 Both rate each other. Success: one rating per person per trip. Fails: trip not completed, window passed, rated twice (B7).

## 4. Rules that must always hold
Trip statuses: requested, assigned, arrived, started, completed, cancelled. Completed and cancelled are terminal. Refunds are rows on the payment side. A dispute is only a support note in the audit log.

- B0 A trip is ACTIVE in the statuses requested, assigned, arrived and started.
- B1 A rider has at most one active trip. Enforced by a database unique index.
- B2 A driver has at most one active trip. Same enforcement. A trip with no driver yet counts for the rider only.
- B3 Money is whole kobo in integer columns, currency NGN only. Enforced by column types and a currency check. A decimal amount is stopped by API validation, not by the column type (the database rounds 10.5 kobo to 11; see docs\04 question 2).
- B4 After completion, fare, distance, start and end times, rider and driver are frozen. Only updated_at may change. Enforced by a database trigger. Corrections and partial refunds are new rows.
- B5 Every status change is recorded (who, when, from, to); only legal changes are allowed.
- B6 Idempotency keys are unique per rider and action, not global. A retried request must not create a second trip or a second charge; it returns the stored result unchanged. Provider payment references are unique.
- B7 A rating needs a completed trip and a participant, within 7 days of completion, once per person per trip.
- B8 Personal data (names, phone numbers, locations) follows Nigeria's NDPA 2023: collect only what is needed, allow deletion, restrict access. Retention periods are NOT verified and need legal advice.
- B9 Rider, driver or support may cancel from requested, assigned or arrived. The system cancels a requested trip no one accepted after request_timeout_seconds, with no fee (placeholder 600 seconds, needs owner approval, held in a settings row). After started, only support. A flat fee applies after assignment, none before. The fee is 50000 kobo (500 naira), a placeholder approved by the owner and held in a settings row, not hard coded.
- B10 The sum of refunds on a payment never exceeds the payment amount.

## 5. Non goals
Matching algorithm, a live map or route display (the rider sees the driver's latest position through the event stream, EP27, but no map or route is drawn), surge pricing, promo codes, driver payouts, tax, multi-city, mobile apps, a full dispute system, a money record for a manual refund of a failed payment (known gap: its trace is provider_event plus audit_log).

## 6. Open questions
- Q1 Currency: ANSWERED. NGN only, kobo (B3).
- Q2 Cancellation fee: ANSWERED. Flat after assignment (B9).
- Q3 Rating window: ANSWERED. 7 days (B7).
- Q4 Refunds: ANSWERED. Partial allowed, as new rows (B4).
- Q5 Location retention: blocked on legal advice. No retention period is chosen.
- Q6 An assigned driver never arrives and the rider is charged the fee if they cancel. OPEN: needs an owner decision before launch. Recommended: no fee when the driver is more than a stated number of minutes late, held in a setting. Not built here.
