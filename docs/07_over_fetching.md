# 07 Over-fetching: where REST carries more than the client needs, and whether GraphQL is worth it

Documents only, no code. CONFIRMED means I ran it and kept the output (`evidence/part_b_*.txt`; SQL in `db/queries/measure_over_fetch.sql` and `db/queries/part_b_payments_by_trip.sql`, read only, run as `ridehail_app`). INFERRED means I reasoned it. A **design sketch** is a design that was never run. Nothing was installed. Field names are the column names of `02_entities.md`; fields that are not columns are the derived fields defined in `06_api_contracts.md` section 3 (`pickup_latitude`, `pickup_longitude`, `dropoff_latitude`, `dropoff_longitude`, `estimated_amount_minor`, `estimated_currency`, `payments`). The seed data is synthetic ("Pickup 1, Lagos", "Driver 1"), so no personal data appears below.

## 1. The endpoint, and why

**EP03 `GET /v1/trips/{trip_id}` (trip detail).** It is the one endpoint that gathers a trip row, the quote (coordinates, estimate), the driver and vehicle snapshot, and the payments, for three clients that need very different parts of it: the rider app, the driver app and the support console. It is also the endpoint the rider's app would poll to watch a trip (A3), so its size matters for every poll. The trip list (EP06) is used as a second measurement in section 3 because the rider's list row is the most common client need and it exposes a gap in the contract (see section 3, finding 1).

What EP03 does **not** carry already limits the damage: the status history (EP04), the ratings (EP18) and the payment detail with refunds and provider events (EP16, support view) are separate endpoints. EP03 is the "medium" document, not an "everything" document.

## 2. The real REST response

Rider view of EP03 for the completed trip `eeeeeeee-0000-0000-0000-000000000001` of the small seed (CONFIRMED, `evidence/part_b_over_fetch_measurements.txt`, M2; same values, keys reordered to the contract order for reading; the database returns keys in its own order, which does not matter to a client):

```json
{
  "id": "eeeeeeee-0000-0000-0000-000000000001",
  "status": "completed",
  "rider_id": "aaaaaaaa-0000-0000-0000-000000000001",
  "fare_quote_id": "ffffffff-0000-0000-0000-000000000001",
  "pickup_address": "Pickup 1, Lagos",
  "dropoff_address": "Dropoff 1, Lagos",
  "pickup_latitude": 6.453000,
  "pickup_longitude": 3.391000,
  "dropoff_latitude": 6.501000,
  "dropoff_longitude": 3.351000,
  "estimated_amount_minor": 125000,
  "estimated_currency": "NGN",
  "driver_name_snapshot": "Driver 1",
  "vehicle_plate_snapshot": "LAG-101-AA",
  "started_at": "2026-10-06T18:07:13.612607Z",
  "completed_at": "2026-10-06T18:07:13.612607Z",
  "cancelled_at": null,
  "cancelled_by_role": null,
  "cancellation_fee_minor": null,
  "cancellation_fee_currency": null,
  "fare_amount_minor": 250000,
  "fare_currency": "NGN",
  "distance_m": 7100,
  "payments": [
    {"id": "832d20bb-9b1c-4c41-90a1-435dfc71f92b", "purpose": "fare", "status": "succeeded", "amount_minor": 250000, "currency": "NGN"}
  ],
  "created_at": "2026-10-06T18:07:13.612607Z",
  "updated_at": "2026-10-06T18:07:13.612607Z"
}
```

(The fare here differs from the quote because seed A wrote its rows directly; the contract says the fare equals the quote at completion. This does not affect the measurement.)

**Size (CONFIRMED, M1; bytes are UTF-8 of the compact JSON, no spaces after `:` and `,`; fields are top-level keys plus 5 keys per payment):**

| Document | Fields | Bytes |
|---|---|---|
| EP03 rider view | 31 | 971 |
| EP03 driver view | 21 | 698 |
| EP03 support view | 33 | 1,074 |
| EP06 TripSummary item, rider list, before the contract fix | 11 | 358 |

Header bytes (status line, headers, TLS) are not counted. Gzip would shrink repeated field names and ids; I did not measure it.

## 3. What each client actually uses

| Client | What it shows | Fields it uses | Share of the response used | Share ignored |
|---|---|---|---|---|
| **Rider trip list row** | status, pickup, dropoff, driver name, fare | `id`, `status`, `pickup_address`, `dropoff_address`, `driver_name_snapshot`, `fare_amount_minor`, `fare_currency` (7) | from EP06 after the contract fix: 7 of 12 fields = 58.3%; 4,675 of 8,095 bytes on a page of 20 = 57.8%. (If it called EP03 per row instead: 7 of 31 fields = 22.6%, 221 of 971 bytes = 22.8%) | **EP06: 41.7% of fields, 42.2% of bytes. EP03 per row: 77.4% of fields, 77.2% of bytes** |
| **Driver active trip card** | where to pick up and drop off, the price | `id`, `status`, `pickup_address`, `pickup_latitude`, `pickup_longitude`, `dropoff_address`, `dropoff_latitude`, `dropoff_longitude`, `estimated_amount_minor`, `estimated_currency` (10) | 10 of 21 fields = 47.6%; 309 of 698 bytes = 44.3% | **52.4% of fields, 55.7% of bytes** |
| **Support console, trip page** | everything about one trip | all 33 fields of EP03 plus history, payment detail and ratings | 33 of 33 fields = 100% of EP03 | 0%, but it needs **four requests**: EP03 1,074 B + EP04 1,123 B + EP16 785 B + EP18 400 B = 3,382 B (CONFIRMED, M3) |

**Finding 1 (a contract gap, now closed in the contract; not built).** The rider list row shows the driver's name, but the list item `TripSummary` of EP06 had no `driver_name_snapshot`. Without it the rider app had two bad choices: call EP03 for every row (20 extra requests and 971 B each, about 19.4 KB for a page of 20; INFERRED by scaling the one measured response) or leave the name out. **Closed in Stage 4 close:** `06_api_contracts.md` now gives the rider's `TripSummary` the field `driver_name_snapshot` (source `trip.driver_name_snapshot`; seen by the rider in their own list and by support in EP03; not in the driver's list). It is a contract change only; no API is built. Measured on the real list page (rider `10000000-0000-0000-0000-000000000777`, 20 rows, CONFIRMED, `evidence/part_b_tripsummary_with_driver_name.txt`): before the fix the EP06 page was 7,280 B (11 fields per item, 358 B for the seed item); after the fix it is **8,095 B** (12 fields, 392 B for the seed item), that is **815 B more per 20 rows**. The list row then uses 7 of the 12 fields, 4,675 of 8,095 bytes = 57.8% used, **42.2% ignored**. (Part B first reported 835 B; that number counted two braces per row and left out one comma, and the exact figure is 815 B.)

**Finding 2 (a cost that is not about bytes), fixed by migration 016.** EP03's `payments` array was the costliest part of the read, and for the database, not the network. CONFIRMED before the fix (`evidence/migration_016_measure_before.txt`): reading all payments of a trip was a **parallel sequential scan of the 169,410 payment rows, 14.8 to 17.7 ms** (runs 14.843, 17.340 and 17.654 ms), because the only trip-based index, `payment_one_live_per_purpose`, is partial (live payments only) and the query asks for every status. The same read restricted to live payments (`status IN ('pending','succeeded')`) was an index scan of 0.07 ms. A full EP03 read measured 13.8 to 14.3 ms (runs 13.757 and 14.297 ms), almost all of it this one lookup. **Migration 016 adds `payment_trip_id_idx` ON payment (trip_id)** (5.13 MB): the all-payments read is now an `Index Scan using payment_trip_id_idx` of 0.06 to 0.10 ms and the full EP03 read 0.14 to 0.32 ms (CONFIRMED, `evidence/migration_016_measure_after.txt`, `migration_016_polling_remeasure.txt`; timings vary by about 3 times between runs). The extra index cost on a payment insert could not be told apart from noise (six runs, then a paired test of 300 inserts per round with and without the index: `evidence/migration_016_insert_cost_paired.txt`). Before the fix this mattered for over-fetching in two ways: a client that polled EP03 paid the cost on every poll, and a GraphQL resolver that loaded `payments` per trip would have repeated it per row (the N+1 problem of section 5).

## 4. The same need in GraphQL (design sketch, not run, nothing installed)

**Schema sketch for the types involved.** Names are camel case as GraphQL convention; each maps to a column or a derived field.

```graphql
# DESIGN SKETCH. NOT RUN. NO GRAPHQL LIBRARY IS INSTALLED.
scalar DateTime
enum TripStatus { REQUESTED ASSIGNED ARRIVED STARTED COMPLETED CANCELLED }
enum PaymentStatus { PENDING SUCCEEDED FAILED }

type Money { amountMinor: Int!  currency: String! }            # *_minor and the currency column beside it
type Place { address: String!  latitude: Float!  longitude: Float! }   # pickup_address and derived pickup_latitude, pickup_longitude (same for dropoff)
type DriverSnapshot { name: String!  vehiclePlate: String! }  # driver_name_snapshot, vehicle_plate_snapshot

type Payment { id: ID!  purpose: String!  status: PaymentStatus!  amount: Money! }
type StatusEvent { seq: Int!  fromStatus: TripStatus  toStatus: TripStatus!  actorRole: String!  createdAt: DateTime! }
type Rating { raterRole: String!  stars: Int!  comment: String  createdAt: DateTime! }   # comment visible to its author and support only

type Trip {
  id: ID!
  status: TripStatus!
  pickup: Place!
  dropoff: Place              # null for a driver before accepting (field-level rule, see section 5)
  estimated: Money!           # estimated_amount_minor, estimated_currency
  fare: Money                 # fare_amount_minor, fare_currency
  cancellationFee: Money      # rider and support only
  driver: DriverSnapshot      # rider and support only
  distanceM: Int
  startedAt: DateTime  completedAt: DateTime  cancelledAt: DateTime
  payments: [Payment!]!       # rider and support only
  history: [StatusEvent!]!    # one resolver, reads trip_status_history ordered by seq
  ratings: [Rating!]!
  createdAt: DateTime!
}
type TripPage { items: [Trip!]!  nextCursor: String }          # same signed keyset cursor as 06 section 1.9

type Query {
  trip(id: ID!): Trip
  myTrips(first: Int = 20, after: String, status: [TripStatus!], createdFrom: DateTime, createdTo: DateTime): TripPage!
}
```

**The rider list row** (status, pickup, dropoff, driver name, fare):

```graphql
query RiderTripList($after: String) {
  myTrips(first: 20, after: $after, status: [COMPLETED, CANCELLED]) {
    items { id status pickup { address } dropoff { address } driver { name } fare { amountMinor currency } }
    nextCursor
  }
}
```

What it would return for the first item (values of the real seed trip 0001; the second to twentieth items have the same shape; the cursor is a placeholder):

```json
{"data": {"myTrips": {"items": [
  {"id": "eeeeeeee-0000-0000-0000-000000000001", "status": "COMPLETED",
   "pickup": {"address": "Pickup 1, Lagos"}, "dropoff": {"address": "Dropoff 1, Lagos"},
   "driver": {"name": "Driver 1"}, "fare": {"amountMinor": 250000, "currency": "NGN"}}
 ], "nextCursor": "****"}}}
```

**Size for the page of 20.** The same seven fields as REST (the "needed" document) come to 4,675 B for the 20 rows of rider 777 (CONFIRMED; GraphQL's own envelope and nested keys such as `pickup` and `fare` would add some bytes that I did not compute). Against REST with the driver name in the summary (the contract after the fix), 8,095 B, that is about 3.4 KB less per page (about 42% of the body). GraphQL's saving on this need is therefore real but small in absolute terms.

**The driver's active trip card:**

```graphql
query DriverActiveTrip($id: ID!) {
  trip(id: $id) { id status pickup { address latitude longitude } dropoff { address latitude longitude } estimated { amountMinor currency } }
}
```

It returns the 10 fields the card shows (309 B in REST naming, against the 698 B driver view: 55.7% less).

**The support console, trip page**, where GraphQL helps most because it replaces four requests with one:

```graphql
query SupportTrip($id: ID!) {
  trip(id: $id) {
    id status pickup { address latitude longitude } dropoff { address latitude longitude } estimated { amountMinor currency }
    fare { amountMinor currency } cancellationFee { amountMinor currency } driver { name vehiclePlate } distanceM startedAt completedAt cancelledAt createdAt
    payments { id purpose status amount { amountMinor currency } }
    history { seq fromStatus toStatus actorRole createdAt }
    ratings { raterRole stars comment createdAt }
  }
}
```

The body is about the same size as the four REST responses together (support uses everything), but it is one round trip. A REST `expand` parameter (section 5) gets the same single trip.

## 5. When REST is still fine, and what GraphQL costs

[CLASS NOTE NEEDED: REST for an MVP]

**REST is the right start for this project.** Reasons, each INFERRED unless a number is given:
- **Three clients, all built by the same team**, with the same release cycle. The over-fetch measured is 42.2% of an 8,095 B list page of 20 rows (about 3.4 KB; CONFIRMED, `evidence/part_b_tripsummary_with_driver_name.txt`, line 17: 20 items, 8095 page bytes, 4675 used bytes, 42.2 percent ignored). Nobody notices that on a phone connection compared with TLS setup and the radio waking up.
- **Every endpoint here has an exact contract** with its ownership check, its errors by HTTP status (06b), its idempotency and its index (CONFIRMED plans in 06). That is easy to test, to rate-limit and to cache. GraphQL would move all of that into resolvers.
- **The expensive thing found is not the payload.** Finding 2 (a 14 to 17 ms sequential scan per trip read, before migration 016) would have been worse under GraphQL, because a resolver per row repeats it.

**What GraphQL costs** (each one is real work for this team):
- **Query depth and cost limits.** A client can ask for `myTrips { payments { ... } history { ... } }` for 100 trips. Without limits on depth, breadth and cost per query, one request can become hundreds of database reads. REST's list limit (default 20, maximum 100, one indexed query) is a cost limit by construction.
- **Caching is harder.** REST responses carry an ETag today (EP03: `updated_at`, so `If-None-Match` can return 304 with no body) and URLs that a proxy can key on. GraphQL usually sends one POST endpoint; it needs persisted queries or a client cache to get similar results.
- **N+1 queries.** A list of trips whose `driver`, `payments` and `history` are loaded by one resolver call per row. It needs batching (a dataloader) per field. Before migration 016 the data showed why: `payments` per trip was a sequential scan (finding 2), repeated per row.
- **Authorisation per field.** The rider must never see `driver_id`, the driver never `rider_id`, a comment only its author and support (06 section 3 and EP18). In REST that is three response shapes chosen once per endpoint. In GraphQL every field resolver must check the caller, and a forgotten check leaks data silently.
- **A second error model.** GraphQL returns HTTP 200 with an `errors` array. The catalogue of 06b (status, code, retryable, database cause) would need a second mapping, and clients, logs and rate limiters that read the HTTP status would see only 200s.
- **Extra tooling.** A schema, code generation, a gateway or server library, query logging and a way to test authorisation per field. Webhooks (EP19), idempotency keys (EP02, EP15), and the event stream (08) stay REST or HTTP anyway, so the system would have two styles.

**How this API already limits over-fetching (CONFIRMED sizes):**
- **Compact list items.** An EP06 item is 392 B (after the driver name was added, `evidence/part_b_tripsummary_with_driver_name.txt`, line 11) against 971 B for the EP03 rider view (60% smaller: 971 minus 392 is 579, and 579 divided by 971 is 0.5963, rounded to 60%).
- **A view per role.** EP03 returns 698 B to a driver, 971 B to a rider and 1,074 B to support, because the contract hides fields by caller (data minimisation, B8).
- **Separate endpoints for heavy parts.** History (1,123 B for 5 events), ratings (400 B) and payment detail with events and refunds (785 B) are not in EP03.
- **ETag on EP03.** An unchanged trip can be answered with a 304 and no 971 B body. The server still runs the read (0.14 to 0.32 ms after migration 016, 13.8 to 14.3 ms before), so ETag saves bytes, not database time.

**Cheap REST changes to make before considering GraphQL** (none is built; decisions 2 to 4 below):
1. **Done in the contract:** `driver_name_snapshot` is in the rider's `TripSummary`, so the list row needs no second call (closes finding 1, +815 B per 20-row page).
2. A `fields` parameter on EP03 and the lists, with an allow-list per role (for example `?fields=id,status,driver_name_snapshot`); the response keeps the same names, and an unknown field is a 400 `invalid_filter`. This gives the rider list row and the driver card the same 221 B and 309 B as the GraphQL queries.
3. An `expand` parameter for the support console (`?expand=history,payments,ratings`), allowed for support only, which turns four requests into one.
4. A separate lightweight endpoint, only if a screen is hit very often (for example a "current trip" card): one endpoint, one query, one index, instead of a general mechanism.
5. **Done:** the `payments` lookup is served by `payment_trip_id_idx` (migration 016, decision 3); it saved more time than any payload trimming (about 14 to 16 ms per EP03 read).

**When I would switch to GraphQL** (any one is a reason to measure, two together are a reason to move):
- **Many client types with very different needs**, for example third-party or partner apps, a web dashboard and several mobile apps that all want different subsets, so the team can no longer shape responses by role.
- **A mobile bandwidth or latency problem measured in production**, such as a p95 payload or time-to-first-screen figure from real telemetry, that the `fields` and `expand` changes did not fix. I have no such figure; this stage measured a seed, not production.
- **The number of one-off endpoints or `fields` variants growing**, for example a fifth or sixth view of the same resource, or `expand` rules that differ per endpoint.
- **Screens that assemble data from many resources** (like the support page, four requests) becoming the main way clients use the API, so that round trips, not bytes, dominate.
- **An illustrative user count, INFERRED (an owner item to confirm, not a measurement).** The honest answer is that I would switch on a measured production problem, not on a user count; the figure below is a bandwidth illustration, labelled INFERRED, with an assumed bandwidth budget that nobody has set, and it is an owner item to confirm. Taking the EP03 figure measured in `08_real_time.md` section 3, one rider poll costs 971 bytes, so each watching rider costs about 194 bytes per second at a 5 second poll (971 divided by 5). At that rate the payload crosses 1 MB per second at about 5,000 watching riders, 10 MB per second at about 50,000, and the 100,000 row of that table asks the network to carry 19.4 MB per second. Those are the points at which payload, not the database, becomes the first thing to break, and they are the user counts at which the `fields` cut (221 B for a rider list row) or a GraphQL subset is worth measuring. This is derived from the measured bytes, not observed in production, so it is on the owner list to confirm before it drives a real decision.

[CLASS NOTE NEEDED: REST for an MVP]

## 6. Decisions for approval
1. **Stay on REST for the MVP.** GraphQL is not needed for three internal clients; revisit on the switch points above.
2. **Add `driver_name_snapshot` to the rider's `TripSummary` (EP06).** DONE in the contract in Stage 4 close (`06_api_contracts.md`); not built.
3. **Fix the payments-by-trip read.** DONE: migration 016 added the ordinary index (the first option below); the alternative was not used. Options considered: add an ordinary index on `payment(trip_id)` in a later migration (recommended: failed attempts stay visible to the rider and to support, and the 14.5 to 17.7 ms scan becomes an index read; the cost is a small index on a table that is written once per payment), or limit EP03's `payments` to live payments (no migration, but a failed attempt disappears from EP03). No migration was added in Part B; migration 016 was added in Stage 4 close.
4. **Optionally add `fields` and `expand` to EP03 and the lists** when a client needs them, with the allow-lists above. Not built.

## 7. Not verified
- Nothing was run in GraphQL; the schema, queries and the response of section 4 are a design sketch. GraphQL envelope bytes were not computed.
- Gzip effects, HTTP header bytes and mobile network behaviour were not measured. The measurements are bytes of JSON bodies built in SQL from seed rows, in compact form; a real server's serialiser may differ by a few percent.
- The 19.4 KB figure for 20 calls to EP03 is one measured response multiplied by 20.
- "Nobody notices 3 KB" is a judgement, not a measurement.
- No production data exists; the thresholds in the switch points are suggestions.
