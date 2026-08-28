"""Standalone operational scripts (run by hand / on a schedule, not by the app).

* ``load_risk_tables``     - load the static risk-reference CSVs into Postgres
                             (a deploy step; run after ``alembic upgrade head``).
* ``classify_unresolved``  - offline batch job: drain the ``unresolved_ingredients``
                             queue, classify it with the data-prep LLM-fallback
                             approach, merge accepted results back into the CSVs.
"""
