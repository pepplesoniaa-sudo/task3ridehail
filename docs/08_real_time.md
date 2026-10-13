# 08 Real time: the rider watching the driver approach

Documents only, no code, no trigger and no migration added. CONFIRMED means I ran it and kept the output (`evidence/part_b_*.txt`; SQL in `db/queries/part_b_*.sql`, read only or rolled back, as `ridehail_app`). INFERRED means I reasoned it from standards or from the schema. Field names are columns of `02_entities.md` (`trip_status_history`: `seq`, `from_status`, `to_status`, `created_at`; `location_ping`: `latitude`, `longitude`, `accuracy_m`, `recorded_at`); fields that are not columns are derived and defined in section 4 (`reason`, `last_seq`, `code`).

## 1. The place

**A3, the rider watching the trip.** After a rider requests a trip, the rider app needs to know without asking again: the trip was accepted (`assigned`), the driver `arrived`, the trip `started`, it `completed` or was `cancelled`, and while the driver approaches, the driver's latest position. Two kinds of updates:
- **Status changes.** Rare (at most about 6 per trip), important, must never be lost or reordered. They are rows of `trip_status_history`, ordered by the `seq` column.
- **Location pings.** Frequent (the driver app sends one about every second through `POST /v1/trips/{trip_id}/locations`, EP13), only the latest matters, losing one is harmless.

Today the only way is polling EP03 (status) and EP05 (latest ping).

## 2. WebSockets against Server-Sent Events (SSE) for this case

[CLASS NOTE NEEDED: bidirectional vs unidirectional]

| Question | Server-Sent Events | WebSocket |
|---|---|---|
| **Direction of traffic** | One way: server to client. The rider only receives. The driver's phone sends pings by an ordinary POST (EP13), which the API already has and which carries authentication, ownership check, rate limit and idempotency rules per request. | Two ways on one connection. The rider app has nothing to send, so half of the channel is unused; and pings sent over a socket would need their own authentication and validation path. |
| **Reconnection and resume** | Built in for browsers: the client reconnects by itself and sends the `Last-Event-ID` header with the last `id:` it saw. The server resumes from there. Native app clients must implement the same rule (a few lines), INFERRED. | None built in. The application must invent its own resume message and its own reconnect timer. |
| **Proxies and load balancers** | It is a normal HTTP response that never ends, so it passes most proxies. It needs response buffering switched off (`Cache-Control: no-store`, `X-Accel-Buffering: no`) and a heartbeat shorter than the idle timeout of every hop (a comment line every 20 seconds). INFERRED. | Needs `Upgrade` support at every hop; some corporate proxies and older middleboxes break it. INFERRED. |
| **HTTP versions and the browser connection limit** | Over HTTP/1.1 a browser allows about 6 connections per host, and every open stream uses one, so many tabs of the same app can starve ordinary requests. A rider watches one trip, so it is one stream; over HTTP/2 streams share one connection. INFERRED. | Not held in the HTTP connection pool in the same way; its limits are different. INFERRED. |
| **Mobile battery and background** | A held connection keeps the radio awake. Both phone operating systems suspend network connections of an app in the background, so a stream only works while the app is in the foreground; "the driver arrived" in the background needs a push notification (outside this design). Sending a location event at most every 2 seconds, and only when it changed, limits radio use. INFERRED. | The same background rule applies. A socket needs its own keep-alive ping to survive network changes. INFERRED. |
| **Authentication of the stream** | The stream is a GET, so it carries `Authorization: Bearer ...` like every endpoint (section 5, "Long lived token problem"). The browser `EventSource` object cannot set headers; a fetch-based client or a library can. A token must never be put in the URL (it ends up in logs). INFERRED. | Browsers cannot set headers on the first WebSocket request either; the usual workarounds are a token in the URL or a first message. Both need more care than a header. INFERRED. |
| **Scale** | One open connection per watching rider; it holds a file descriptor and a small buffer on one API instance. I did not measure memory per connection. The number to plan with is open streams per instance, to be measured under load. | The same. A socket server also keeps per-connection state for the application protocol. |
| **What is sent** | Status events from `trip_status_history` in `seq` order (the `id:` of each event is its `seq`), the latest ping as a `location` event, a heartbeat, and an `end` event. | The same messages, but the application defines the framing and acknowledgements. |

## 3. Recommendation and the cost of the fallback

**Use SSE.** The rider only receives, so a unidirectional channel is enough: SSE is plain HTTP, it resumes with a standard header, its authentication is the same as every other endpoint, and pings stay on the POST that already exists. [CLASS NOTE NEEDED: bidirectional vs unidirectional]

**Switch to WebSockets when** the client needs to send as well as receive on the same channel at a rate where a POST per message is a poor fit: in-app chat between rider and driver, the driver app needing push commands from the server with acknowledgements, a live negotiation of the fare, or binary payloads. None of these is in the requirements.

**Polling is the fallback**, and it is what the apps can do today. Its cost, computed for N riders watching, each polling every 5 seconds (rate = N / 5 requests per second per endpoint). **Re-measured after migration 016** (the index on `payment(trip_id)`), CONFIRMED in `evidence/migration_016_polling_remeasure.txt`; the "before" column keeps the measurement of Part B and of the Stage 4 close baseline (`evidence/migration_016_measure_before.txt`).

**Assumptions, visible:**
- **Poll interval 5 seconds**, one EP03 read and one EP05 read per poll.
- **Read times are warm-cache execution times of the SQL statement** (`EXPLAIN ANALYZE`), not whole-request times: network, JSON building, connection pool, authentication and the application's own CPU are not included. EP03 read **0.23 ms** (median of 5 runs, range 0.14 to 0.32 ms) after the index, against **about 15 ms** before (the payments scan inside it: 14.8 to 17.7 ms; the whole EP03 read: 13.8 to 14.3 ms; `evidence/migration_016_measure_before.txt`). EP05 read **0.04 ms** (median of 4 warm runs; Part B measured 0.09 ms on another run). The first read of a trip that is not in cache cost 7 to 9 ms (EP03) and 3.8 ms (EP05); a rider who keeps polling keeps those pages warm, so the warm figure is used.
- **Timings on this machine vary by about 3 times between runs**, so every figure below is an order of magnitude, and the range column shows what the spread alone does.
- **"Cores" = seconds of database execution per second of wall clock**, assuming the work spreads perfectly over cores. Real systems lose some to locks and contention.

| Watching riders N | EP03 requests per second | EP03 body bytes per second (971 B each) | Database time per second, EP03 **before** the index (about 15 ms per read) | Database time per second, EP03 **after** (0.23 ms; range at 0.14 to 0.32 ms) | EP05 requests per second | Database time per second, EP05 (0.04 ms) |
|---|---|---|---|---|---|---|
| 100 | 20 | 19.4 KB | 0.30 s (0.3 core) | 0.0046 s (0.003 to 0.006) | 20 | 0.0008 s |
| 1,000 | 200 | 194 KB | 3.0 s (about 3 cores) | 0.046 s (0.028 to 0.064) | 200 | 0.008 s |
| 10,000 | 2,000 | 1.9 MB | 30 s (about 30 cores) | 0.46 s (0.28 to 0.64) | 2,000 | 0.08 s |
| 100,000 | 20,000 | 19.4 MB | 300 s (about 300 cores) | 4.6 s (2.8 to 6.4) | 20,000 | 0.8 s |

Reading it: the index cut the database time of an EP03 poll by about **65 times** (about 15 ms to 0.23 ms; 15 divided by 0.23 is 65.2, rounded to the nearest whole number). At 1,000 watching riders polling costs the database 0.05 s per second, which is nothing; at 10,000 it is about half a core; at 100,000 it is 4.6 cores for EP03 and 0.8 for EP05, about 5 in total (3.6 to 7.2 at the two ends of the spread), plus 40,000 requests per second and 19.4 MB per second of EP03 bodies that the application and the network must carry (the database is no longer the first thing to break; this table does not measure those). EP05 (one index read) was always cheap. ETag (`If-None-Match`) returns 304 with no body for an unchanged trip, which is nearly every poll, so it saves the 971 B body but not the read; a trip of 20 minutes at 5 seconds is 240 polls and only about 6 changes (an assumption, not a measurement). A poll never shows a change faster than its interval: 5 seconds on average 2.5 seconds late. The reason to use the stream (EP27) is therefore no longer "polling would melt the database" but latency (1 second against 5), request count and battery, which this stage did not measure.
**Bytes over a whole trip (assumed 20 minutes, 1,200 seconds; sizes from real samples):** polling EP03 every 5 seconds is 240 x 971 B = 233 KB of bodies. The stream sends 6 status events of 136 B, up to 600 location events of 125 B (one per 2 seconds) and a final `end` of 41 B: about 76 KB, and a heartbeat of 13 B every 20 seconds (CONFIRMED sizes of the sample events, measured with `wc -c` on the exact text of section 5; the trip length is an assumption).

## 4. Where the feed comes from, and what the database can and cannot do

The API reads PostgreSQL; PostgreSQL does not push to the API unless the API asks. Proposal (one mechanism, in two steps):

**Step 1 (no change to the database): a batched poller inside each API instance.** Each instance keeps the list of trips it has open streams for. Every 1 second it runs two queries for all of them at once:
- **New status events:** `SELECT trip_id, seq, from_status, to_status, created_at FROM trip_status_history WHERE trip_id = ANY($open_trips) ORDER BY trip_id, seq`, from which the instance sends the rows with `seq` above what each stream has sent. CONFIRMED plan for 50 trips (R4): one Index Scan on `trip_status_history_trip_seq_idx`, 0.33 ms for 248 rows. For one trip and one resume (R1): 0.046 ms, 5 rows.
- **Latest ping per trip:** a lateral join that takes the newest row of each trip. CONFIRMED plan for 50 trips (R3): 50 index probes of `location_ping_trip_recorded_idx`, 0.28 ms; for one trip (R2) 0.09 ms.
The cost grows with the number of open streams per instance, not with the number of polls: 10,000 streams over 10 instances is 1,000 streams per instance, one batch per second (INFERRED, scaling the 50-stream timing; not measured). Status events reach the rider within about 1 second.

**Step 2 (needs a migration in a later stage; NOT added now, decision 3): a doorbell.** A `NOTIFY` sent when `trip_status_history` gets a row would wake the poller at once instead of waiting for its timer. The trigger `trip_write_history` is the place, but it is SECURITY DEFINER code owned by `ridehail_writer`, so changing it is a migration and an owner decision. The data path stays the same (read by `seq`), so the notification only needs to say "something changed for this trip".

**What LISTEN and NOTIFY do and do not do (CONFIRMED, `evidence/part_b_listen_notify.txt` and `part_b_listen_notify_cross_session.txt`, run as `ridehail_app` with `pg_notify` by hand; no trigger, no table):**

| Test | Result | Meaning for the design |
|---|---|---|
| N1 listener, then a committed notification | delivered with the payload `{"trip_id":"40000000-...198904","seq":930301,"to_status":"completed"}` | works for `ridehail_app` with no extra grant |
| N6 listener in one session, sender in another (backend pids 266 and 273) | delivered across sessions | the doorbell reaches an API instance that holds the listening connection |
| N2 notification sent in a transaction that is rolled back | **not delivered** | a rolled-back status move never rings the bell; the notification is tied to the commit |
| N3c notification sent inside an open transaction | delivered only after the `COMMIT` | the reader never sees an event before the data it points to is visible |
| N3a two identical notifications in one transaction | delivered once | identical payloads are folded; the payload must carry `seq` so that two moves are not folded |
| N3b two different payloads in one transaction | both delivered, in the order sent | order is kept within a transaction |
| N4 notification sent while nobody listens, then a session starts listening | **not delivered** | **notifications are lost while a listener is disconnected**; they are not stored |
| N5 payload of 7,999 characters, then 8,000 | the first is accepted; the second fails with SQLSTATE 22023 "payload string too long" | the payload limit is under 8,000 bytes: send ids only (`trip_id`, `seq`), never the event body |

**Why `seq` makes resume safe.** Notifications can be lost (N4), but they are never the data. Whenever the API wakes (by a notification or by its 1-second timer) it reads from the table `WHERE trip_id = ... AND seq > last_sent`. A lost notification costs at most one timer interval of delay, never an event. The same read serves a client that reconnects with `Last-Event-ID`. For this to be correct, `seq` order for one trip must equal the order in which the changes became visible. It does: every move of a trip updates the trip row, the history row is written by an AFTER trigger on that update, so a second move of the same trip waits for the first to commit (CONFIRMED: with session A holding an uncommitted move of trip 11, session B's move of the same trip hit the 800 ms `lock_timeout`, SQLSTATE 55P03, `evidence/part_b_trip_row_lock_b.txt`; the AFTER trigger is in `pg_get_triggerdef`). The ordering conclusion is INFERRED from that wait. **Two limits:**
- **Do not poll globally by `seq > highest seen`.** Identity values are handed out when the row is inserted, not when it commits, so across different trips a row with a lower `seq` can become visible after a row with a higher one, and a global poller would skip it. Per-trip reads are safe because of the lock above. INFERRED (not demonstrated: the demonstration needs two committed transactions, and this stage keeps everything rolled back).
- **62 bulk trips have a misplaced `seq`** (known limit, accepted: `evidence/migration_010_seq_investigation.txt`). A replay of one of those trips could list its events out of timeline order. Trips created through the API after migration 010 are not affected.

**Other limits of NOTIFY:** a listener needs its own database connection that stays open (a connection pool in transaction mode cannot hold one; INFERRED); the notification queue has a finite size in PostgreSQL (documented, not tested); with several API instances each instance listens and each receives every notification, which is cheap because the payload is a pair of ids.

## 5. The event format, resume and ending

The endpoint is **EP27 `GET /v1/trips/{trip_id}/events`**, specified in `06_api_contracts.md`. Response: `200`, `Content-Type: text/event-stream`, `Cache-Control: no-store`, `X-Accel-Buffering: no`.

**Event names and data (data is one line of JSON; a rider never receives actor ids):**

| Event | `id:` | `data:` fields | When |
|---|---|---|---|
| `status` | the `seq` of the history row | `seq`, `from_status` (null for the first), `to_status`, `created_at` | each status change, in `seq` order |
| `location` | none (latest wins, never replayed) | `latitude`, `longitude`, `accuracy_m`, `recorded_at` | at most one every 2 seconds, only if a newer ping exists, only while the trip is assigned, arrived or started |
| `end` | none | `reason` (`completed`, `cancelled`, `token_expired`, `max_duration`) | last event before the server closes the stream |
| `error` | none | `code` (a code of `06b`, for example `service_unavailable`), `request_id` | the database fails after the 200 was sent; then the server closes |
| (comment line `: keepalive`) | none | none | every 20 seconds of silence |

An event without an `id:` does not change the client's last event id, so `Last-Event-ID` always names the last **status** event. The first line of a stream is `retry: 3000` (the client waits 3 seconds before reconnecting).

**A first connection** (real `seq` values and statuses of trip `40000000-0000-0000-0000-000000198904`; the timestamps are identical because the bulk loader wrote the whole trip in one transaction; the `location` line is illustrative):

```
GET /v1/trips/40000000-0000-0000-0000-000000198904/events
Authorization: Bearer ****
Accept: text/event-stream

HTTP/1.1 200 OK
Content-Type: text/event-stream
Cache-Control: no-store

retry: 3000

id: 930297
event: status
data: {"seq":930297,"from_status":null,"to_status":"requested","created_at":"2026-10-06T18:43:32.458283Z"}

id: 930298
event: status
data: {"seq":930298,"from_status":"requested","to_status":"assigned","created_at":"2026-10-06T18:43:32.458283Z"}

event: location
data: {"latitude":6.455210,"longitude":3.388742,"accuracy_m":8,"recorded_at":"2026-10-06T18:44:09.310552Z"}

: keepalive
```

(sizes of these exact forms: a `status` event 136 bytes, a `location` event 125, an `end` event 41, a keepalive 13; CONFIRMED with `wc -c`.)

**Resume with `seq`.** The client had seen `930299` (arrived) and lost the connection. It reconnects with that id and receives only what it missed, then the end:

```
GET /v1/trips/40000000-0000-0000-0000-000000198904/events
Last-Event-ID: 930299

HTTP/1.1 200 OK
...
id: 930300
event: status
data: {"seq":930300,"from_status":"arrived","to_status":"started","created_at":"2026-10-06T18:43:32.458283Z"}

id: 930301
event: status
data: {"seq":930301,"from_status":"started","to_status":"completed","created_at":"2026-10-06T18:43:32.458283Z"}

event: end
data: {"reason":"completed"}
```

The query behind it is `WHERE trip_id = $1 AND seq > 930299 ORDER BY seq` (CONFIRMED plan R1, index scan, 0.046 ms). With no `Last-Event-ID` the server sends every event of the trip from the start (at most about 6 rows), so a client that lost its state can rebuild the timeline. A `Last-Event-ID` that is not a whole number of 0 or more is a 400 `invalid_cursor` before any stream starts; a number larger than every `seq` of the trip simply yields no old events.

**Ownership check on the stream (a random id is not authorisation).** Before anything is sent, the API runs `SELECT id, status FROM trip WHERE id = $1 AND rider_id = $2` with the caller's `sub` (support may read any trip). No row means the same 404 `not_found` as an unknown id, so a stranger learns nothing. After that the poller reads only trip ids that passed this check on a stream of the same caller, so a client cannot widen the set; `trip.rider_id` never changes (`02_entities.md`: "never changes"), so one check at connect time stays true for the life of the stream. Every database call of the stream is in a transaction that first sets `app.actor_role` and `app.actor_id` from the token, as in `06` section 1.4. The check is made again on every reconnect.

**When the trip finishes.** The server sends the last `status` event (`completed` or `cancelled`), then `event: end` with the `reason`, then closes the response. A browser `EventSource` reconnects by itself when a connection closes, so the client must stop on the `end` event (call `close()`); the contract says so. **If the client reconnects after the trip ended** (it never saw the end): the server replays the events after `Last-Event-ID`, sends `end` at once and closes. The client sees `end` again and stops, so there is no reconnect loop. If the trip was `completed` or `cancelled` and the client has seen every event, the stream is `end` only.

**Long lived token problem.** A stream outlives the check that opened it. Rules: the token is verified at connect and the stream is closed (`end`, `reason: token_expired`) at the token's expiry, so the client refreshes its token and reconnects with `Last-Event-ID`; and a stream lives at most 15 minutes (`end`, `reason: max_duration`) so a revoked token, a deleted rider (`deleted_at`) or a deactivated support admin is cut off within 15 minutes. Revocation is not checked more often than that (limit, INFERRED); shorten the maximum if that is too long. Tokens are never put in the URL.

## 6. Decisions for approval
1. **Use SSE for the rider watch (EP27), keep pings on POST (EP13).** WebSockets only when chat or server commands appear.
2. **Feed the stream with a batched per-instance poller at 1 second** (no database change); add the `NOTIFY` doorbell later by migration (the `trip_write_history` trigger), for lower latency only.
3. **A later migration to add `NOTIFY` to the history trigger is optional**, and the `payment(trip_id)` index recommended in `07_over_fetching.md` decision 3 is now built (migration 016), so polling EP03 no longer costs a full scan of the payment table.
4. **Stream limits:** heartbeat 20 s, location at most every 2 s, token-expiry close, 15-minute maximum, at most 2 open streams per rider per trip (the third is 429 `rate_limited`). All are placeholders.
5. **Support may open the same stream** (read only, any trip), consistent with EP05; the driver app does not (its own trip is read with EP03 and its own pings go by POST).

## 7. Not verified
- No SSE server exists. The event format, resume behaviour and closing rules are a contract design; nothing was streamed over HTTP.
- Memory and file descriptors per open connection, proxy and load balancer behaviour, HTTP/2 stream limits and the mobile background rules are INFERRED from standards and general experience.
- The out-of-order commit risk of a global `seq` poll is reasoned, not demonstrated; the per-trip lock wait is demonstrated.
- The 1-second poller's scaling to thousands of streams per instance is extrapolated from 50-stream timings.
- The notification queue size limit and the transaction-pool behaviour of LISTEN were not tested.
- Trip length (20 minutes), the share of unchanged polls and the ping rate (1 per second) are assumptions.
