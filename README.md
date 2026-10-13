\# API Design and Data Modelling: a ride hailing service



Author: Sonia Pepple. Date: 13 October 2026.



A design and proof of a ride hailing service (riders, drivers, trips, payments).

The design is written first. A PostgreSQL schema proves it holds.

No API was built: the 27 endpoints exist as contracts only.



\## What is here



\- build/    The Word document and PDF, plus the source used to build them

\- docs/     The design documents (requirements, entities, state machine,

&#x20;           seven hard questions, API contracts, analyses, open items)

\- db/       Migrations 001 to 016, seed data and the query and proof scripts

\- evidence/ Saved output of every test, plan and proof

\- images/   The diagrams and the three screenshots of rejected inserts



\## What was built



\- 16 tables, 116 constraints, 42 indexes, 27 triggers, 18 functions, 4 roles

\- Two state machines (trip and payment) enforced by the database

\- Query plans and three rejected invalid inserts, run as the application role



\## Start here



Read build/API\_Design\_and\_Data\_Modelling\_Ride\_Hailing.pdf first.



\## Limits



\- Nothing was run over HTTP.

\- Several values are placeholders needing the owner (see docs/09\_open\_items.md).

\- Five decisions are still open: D5, D8, D9, D13, D16.



\## Secrets



No password or key is stored in this project. The database password

lives only in the environment.

