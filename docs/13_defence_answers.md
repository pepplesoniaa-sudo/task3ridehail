Defence preparation, not part of the deliverable.

# 13 Defence answers

Four questions asked at the defence, each answered in plain English in under 120 words, each citing the exact file and line. Every line below was opened and checked before it was cited.

## Question 1. Show a fact that lives in two places and defend it

A person's name lives once, in `driver.full_name`. `trip.driver_name_snapshot` copies it at assignment: a deliberate copy of a past fact, written once by trigger `trip_enforce_transition` (`04_hard_questions.md` line 26). The same trigger freezes it after completion or cancellation under B4, so an old receipt still names the driver who drove, even if that driver later changes name. Drift is the goal, not a fault: the snapshot is meant to stop matching the live row. Check `trip_snapshots_match_assignment` keeps it consistent, requiring the snapshot exactly when a driver and a vehicle exist (line 26). The second deliberate copy is the rating totals on rider and driver, kept by trigger `rating_update_cache` and the checks `rider_rating_cache_valid` and `driver_rating_cache_valid` (lines 41 to 43). Source: `04_hard_questions.md` question 1, lines 7 to 57.

## Question 2. A rider requests a second trip while one is in progress. Which line stops it?

The line is the partial unique index `trip_one_active_per_rider` in `db\migrations\004_quotes_trips.sql` lines 108 to 109:

`CREATE UNIQUE INDEX trip_one_active_per_rider ON trip (rider_id) WHERE status IN ('requested','assigned','arrived','started');`

A second active trip for the same rider is refused by the database itself, not by the API. It maps to 409 `rider_has_active_trip` (`06b_error_catalogue.md` line 22; `06_api_contracts.md` line 349). Evidence as `ridehail_app`: `evidence\proofs_rejected_and_extra.txt` part 1, lines 2 to 14, where the insert failed with "duplicate key value violates unique constraint `trip_one_active_per_rider`". An index beats application code because two requests at the same instant can both pass a check and then both write; the unique index is enforced inside the write, so exactly one wins.

## Question 3. Why does the trip store the fare rather than look it up from the driver's current rate?

The fare is fixed upfront, decision D1, approved in `docs\09_open_items.md` section 6 (line 116). EP01 (`06_api_contracts.md` lines 289 to 318) fixes the price from the settings at that moment and stores it on the quote; EP12 (line 460) copies the quote amount into `trip.fare_amount_minor` and states the client never sends the fare. B4 then freezes it, and refunds, receipts and disputes need the original figure. There is no per driver rate anywhere in this design: `base_fare_minor`, `per_km_minor` and `per_minute_minor` are global settings, not a rate on the driver, so a driver's current rate cannot be looked up because it does not exist.

## Question 4. At what user count do you switch this endpoint to GraphQL, and what triggers it?

The honest answer is that I would switch on a measured production problem, not on a user count; the figure below is a bandwidth illustration, labelled INFERRED, with an assumed bandwidth budget that nobody has set, and it is an owner item to confirm. `docs\07_over_fetching.md` lines 194 to 199 gives four switch conditions and no count, and line 196 says plainly there is no production figure. Here is an illustrative count derived only from measured bytes. `docs\07` line 183 and `docs\08_real_time.md` line 42 measure one EP03 rider poll at 971 bytes. At a 5 second poll (`docs\08` line 37) that is 971 divided by 5, about 194 bytes per second per watching rider. 1,000,000 divided by 194 is about 5,150 riders for 1 MB per second; 10,000,000 divided by 194 is about 51,500 for 10 MB per second. `docs\08` line 47 already shows 100,000 riders at 19.4 MB per second, which matches. INFERRED, an owner item to confirm; the trigger is bandwidth, so measure the real payload first.
