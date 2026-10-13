# 06c Endpoint Matrix

Generated from the endpoint index of `06_api_contracts.md` by a script, so the two cannot disagree (regenerated in Stage 5 prep 2, after the written design assumptions and the new error code; the endpoints did not change). Part 1: endpoints against caller roles (Y = may call; the ownership check for each is in 06 section 1.3). Part 2: endpoints against requirement IDs. Part 3: the flags.

## 1. Endpoints against caller roles

| Id | Method and path | rider | driver | support | provider | scheduler |
|---|---|---|---|---|---|---|
| EP01 | POST /v1/fare-quotes | Y | - | - | - | - |
| EP02 | POST /v1/trips | Y | - | - | - | - |
| EP03 | GET /v1/trips/{trip_id} | Y | Y | Y | - | - |
| EP04 | GET /v1/trips/{trip_id}/status-history | Y | Y | Y | - | - |
| EP05 | GET /v1/trips/{trip_id}/driver-location | Y | - | Y | - | - |
| EP06 | GET /v1/riders/me/trips | Y | - | - | - | - |
| EP07 | GET /v1/drivers/me/trips | - | Y | - | - | - |
| EP08 | GET /v1/trip-requests | - | Y | - | - | - |
| EP09 | POST /v1/trips/{trip_id}/accept | - | Y | - | - | - |
| EP10 | POST /v1/trips/{trip_id}/arrive | - | Y | - | - | - |
| EP11 | POST /v1/trips/{trip_id}/start | - | Y | - | - | - |
| EP12 | POST /v1/trips/{trip_id}/complete | - | Y | - | - | - |
| EP13 | POST /v1/trips/{trip_id}/locations | - | Y | - | - | - |
| EP14 | POST /v1/trips/{trip_id}/cancel | Y | Y | Y | - | - |
| EP15 | POST /v1/trips/{trip_id}/payments | Y | - | - | - | - |
| EP16 | GET /v1/payments/{payment_id} | Y | - | Y | - | - |
| EP17 | POST /v1/trips/{trip_id}/ratings | Y | Y | - | - | - |
| EP18 | GET /v1/trips/{trip_id}/ratings | Y | Y | Y | - | - |
| EP19 | POST /v1/provider/webhooks | - | - | - | Y | - |
| EP20 | POST /v1/support/payments/{payment_id}/fail | - | - | Y | - | - |
| EP21 | POST /v1/support/payments/{payment_id}/refunds | - | - | Y | - | - |
| EP22 | GET /v1/support/settings | - | - | Y | - | - |
| EP23 | PUT /v1/support/settings/{key} | - | - | Y | - | - |
| EP24 | POST /v1/support/notes | - | - | Y | - | - |
| EP25 | POST /v1/support/riders/{rider_id}/erasure | - | - | Y | - | - |
| EP26 | POST /v1/support/drivers/{driver_id}/erasure | - | - | Y | - | - |
| EP27 | GET /v1/trips/{trip_id}/events | Y | - | Y | - | - |
| JB1 | request timeout job (internal) | - | - | - | - | Y |
| JB2 | payment reconciliation job (internal) | - | - | - | - | Y |
| JB3 | idempotency cleanup job (internal) | - | - | - | - | Y |

## 2. Requirement IDs against endpoints

| Requirement | Meaning (01_requirements.md) | Endpoints |
|---|---|---|
| A1 | rider requests a trip | EP01, EP02 |
| A2 | driver accepts | EP08, EP09 |
| A3 | trip moves and rider watches | EP03, EP04, EP05, EP06, EP07, EP10, EP11, EP12, EP13, EP27 |
| A4 | rider pays | EP15, EP16, EP19, EP20, JB2 |
| A5 | both rate | EP17, EP18 |
| B0 | ACTIVE definition | EP02 |
| B1 | one active trip per rider | EP02, EP14, JB1 |
| B2 | one active trip per driver | EP09, EP14 |
| B3 | money in kobo, NGN | EP01, EP12, EP15, EP21, EP23 |
| B4 | frozen after completion | EP03, EP12, EP21 |
| B5 | every change recorded, legal moves only | EP04, EP10, EP11, EP14, EP19, EP24 |
| B6 | idempotency, unique references | EP02, EP15, EP19, EP20, JB2, JB3 |
| B7 | rating rules | EP17, EP18, EP23 |
| B8 | personal data (NDPA) | EP05, EP06, EP07, EP13, EP25, EP26, EP27 |
| B9 | cancellation, timeout, fee | EP14, EP22, EP23, JB1 |
| B10 | refunds never exceed payment | EP21 |
| U1 | rider | EP03, EP06, EP15, EP27 |
| U2 | driver | EP03, EP07, EP08, EP09 |
| U3 | support admin | EP03, EP04, EP14, EP16, EP20, EP21, EP22, EP23, EP24, EP25, EP26, EP27 |
| U4 | payment provider | EP19, EP20, JB2 |
| Q1 | currency (answered) | EP01, EP23 |
| Q2 | cancellation fee (answered) | EP14, EP23 |
| Q3 | rating window (answered) | EP17, EP23 |
| Q4 | refunds (answered) | EP21 |
| Q5 | location retention (blocked on legal advice) | NONE |
| Q6 | driver never arrives (open) | NONE |

## 3. Flags

**Requirement IDs with no endpoint (2):**
- **Q5 Location retention.** No endpoint and no job: no retention period is chosen (blocked on legal advice), so there is nothing to build. `location_ping` rows are kept until a decision is made. A purge job (a DELETE of old pings is allowed by the database, `append_only_guard` refuses only update) is added after the decision. Not a gap in this contract, an open owner item.
- **Q6 Driver never arrives.** Open owner decision. EP14 applies the current rule (a rider cancelling from assigned or arrived pays the fee) and says so. No endpoint can fix it until the owner chooses a lateness limit, which would then be a new setting key in EP23.

**Endpoints with no requirement ID: none.**

**Weakly covered (not flagged as missing):** B0 is a definition (what ACTIVE means), enforced by the two partial unique indexes; EP02 and EP09 are where it shows. A5 and B7 are served by EP17 and EP18. No endpoint reads the `support_admin`, `rider`, `driver` or `vehicle` tables: account creation and profile endpoints are outside Part A (06 section 6).