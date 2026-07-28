#!/usr/bin/env python3
"""
ONS Enterprise Data Platform - OLTP Data Population Script
Version: 1.0
Author: Guilherme Roriz (revised)
Description: Generates synthetic data for all OLTP tables, respecting
             business rules and referential integrity.

Fixes vs v1.0:
  - Reuses a single connection/cursor instead of opening one per lookup
    (v1.0 leaked ~100+ unclosed connections and could exhaust max_connections).
  - Column names matched to the OLTP Source System Documentation
    (state.grid_operator_area, plant/substation.estado_id,
    generation_reading.output_mw / available_capacity).
  - Captures real primary keys via RETURNING instead of assuming
    auto-increment IDs start at 1 and land in insertion order.
  - Idempotent: truncates target tables first (--truncate, default on)
    instead of dying on unique-constraint violations on rerun.
  - Unique text fields built from a counter instead of Faker's .unique
    pool, which was at real risk of exhausting itself over 500 rows.
  - Configurable volume via CLI flags (--days, --minute-level) so the
    generated data can match the documented ~144k/~1.44M rows-per-day
    scale instead of silently being ~60x smaller.

Usage:
  python populate_oltp.py                       # 3 days, hourly readings
  python populate_oltp.py --days 7               # 7 days, hourly readings
  python populate_oltp.py --minute-level          # per-minute readings (large!)
  python populate_oltp.py --no-truncate           # append instead of reset
"""

import argparse
import random
import datetime

import psycopg2
import psycopg2.extras
from faker import Faker

# ------------------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------------------
DB_PARAMS = {
    "dbname": "ons_oltp",
    "user": "postgres",
    "password": "postgres",
    "host": "localhost",
    "port": 5432,
}
SCHEMA = "oltp"

SEED = 42  # for reproducibility
random.seed(SEED)
fake = Faker("pt_BR")
fake.seed_instance(SEED)

# Tables truncated at startup, in FK-safe (child-first) order.
TRUNCATE_ORDER = [
    "occurrence_asset",
    "work_order_asset",
    "measurement",
    "generation_reading",
    "asset_status",
    "occurrence",
    "work_order",
    "transmission_line",
    "substation",
    "plant",
    "occurrence_type",
    "maintenance_type",
    "state",
]

# ------------------------------------------------------------------------------
# DB helpers - one connection, reused everywhere
# ------------------------------------------------------------------------------
def bulk_insert(cur, table, columns, rows):
    """Insert many rows in one round trip. No IDs returned."""
    if not rows:
        return
    sql = f"INSERT INTO {SCHEMA}.{table} ({', '.join(columns)}) VALUES %s"
    psycopg2.extras.execute_values(cur, sql, rows)


def bulk_insert_returning(cur, table, columns, rows, pk_column):
    """
    Insert many rows and return their generated primary keys, in the
    same order the rows were passed in. Avoids ever guessing IDs.
    """
    if not rows:
        return []
    sql = (
        f"INSERT INTO {SCHEMA}.{table} ({', '.join(columns)}) "
        f"VALUES %s RETURNING {pk_column}"
    )
    results = psycopg2.extras.execute_values(cur, sql, rows, fetch=True)
    return [row[0] for row in results]


def fake_latitude_longitude():
    """Generate random coordinates within Brazil's bounding box."""
    lat = random.uniform(-33.7, 5.3)
    lon = random.uniform(-73.9, -34.8)
    return round(lat, 6), round(lon, 6)


def unique_name(prefix, i):
    """Deterministic unique-enough display name, no reliance on Faker's
    finite unique pool (which real-world runs of 500+ rows can exhaust)."""
    return f"{fake.word().capitalize()} {prefix} {i}"


# ------------------------------------------------------------------------------
# 1. Reference tables
# ------------------------------------------------------------------------------
def populate_state(cur):
    ufs = [
        ("AC", "Acre"), ("AL", "Alagoas"), ("AP", "Amapá"),
        ("AM", "Amazonas"), ("BA", "Bahia"), ("CE", "Ceará"),
        ("DF", "Distrito Federal"), ("ES", "Espírito Santo"),
        ("GO", "Goiás"), ("MA", "Maranhão"), ("MT", "Mato Grosso"),
        ("MS", "Mato Grosso do Sul"), ("MG", "Minas Gerais"),
        ("PA", "Pará"), ("PB", "Paraíba"), ("PR", "Paraná"),
        ("PE", "Pernambuco"), ("PI", "Piauí"), ("RJ", "Rio de Janeiro"),
        ("RN", "Rio Grande do Norte"), ("RS", "Rio Grande do Sul"),
        ("RO", "Rondônia"), ("RR", "Roraima"), ("SC", "Santa Catarina"),
        ("SP", "São Paulo"), ("SE", "Sergipe"), ("TO", "Tocantins"),
    ]
    # column name matches the OLTP doc: grid_operator_area (not ons_control_area)
    rows = [(code, name, f"Área {code}") for code, name in ufs]
    return bulk_insert_returning(
        cur, "state", ["state_code", "state_name", "grid_operator_area"],
        rows, "state_id",
    )


def populate_occurrence_type(cur):
    types = [
        ("OUT", "Outage", "Forced Outage", "High"),
        ("EQF", "Equipment Failure", "Transformer Failure", "Critical"),
        ("ALM", "Alarm", "Voltage Limit", "Medium"),
        ("EMG", "Emergency", "Load Shedding", "Critical"),
        ("OUT_PLAN", "Outage", "Planned Outage", "Low"),
        ("EQF_LINE", "Equipment Failure", "Line Trip", "High"),
        ("ALM_FREQ", "Alarm", "Frequency Deviation", "Medium"),
        ("EMG_STORM", "Emergency", "Storm Damage", "Critical"),
    ]
    return bulk_insert_returning(
        cur, "occurrence_type",
        ["type_code", "category", "subtype", "severity_level"],
        types, "occurrence_type_id",
    )


def populate_maintenance_type(cur):
    types = [
        ("PREV", "Preventive", "Routine Inspection", "Low"),
        ("CORR", "Corrective", "Emergency Repair", "Urgent"),
        ("PRED", "Preventive", "Predictive Maintenance", "Medium"),
        ("OVER", "Preventive", "Major Overhaul", "High"),
        ("CORR_LINE", "Corrective", "Line Repair", "High"),
    ]
    return bulk_insert_returning(
        cur, "maintenance_type",
        ["type_code", "category", "subtype", "priority_level"],
        types, "maintenance_type_id",
    )


# ------------------------------------------------------------------------------
# 2. Master data
# ------------------------------------------------------------------------------
def populate_plant(cur, state_ids, n=100):
    types = ["Hydro", "Thermal", "Wind", "Solar", "Nuclear"]
    rows = []
    for i in range(1, n + 1):
        code = f"PLT-{i:03d}"
        name = unique_name("Plant", i)
        ptype = random.choice(types)
        cap = (
            round(random.uniform(500, 1500), 2)
            if ptype == "Nuclear"
            else round(random.uniform(50, 2000), 2)
        )
        start = datetime.date(1980, 1, 1)
        end = datetime.date(2025, 12, 31)
        commission_date = start + (end - start) * random.random()
        operator = fake.company()
        estado_id = random.choice(state_ids)
        status = random.choice(["Active"] * 80 + ["Decommissioned"] * 10 + ["Under Construction"] * 10)
        rows.append((code, name, ptype, cap, commission_date, operator, status, estado_id))
    return bulk_insert_returning(
        cur, "plant",
        ["plant_code", "plant_name", "plant_type", "installed_capacity",
         "commissioning_date", "operator_name", "status", "estado_id"],
        rows, "plant_id",
    )


def populate_substation(cur, state_ids, n=200):
    stypes = ["Step-up", "Step-down", "Switching"]
    rows = []
    for i in range(1, n + 1):
        code = f"SUB-{i:03d}"
        name = unique_name("Substation", i)
        voltage = random.choice([13.8, 34.5, 69, 138, 230, 345, 500])
        stype = random.choice(stypes)
        estado_id = random.choice(state_ids)
        status = random.choice(["Active"] * 170 + ["Decommissioned"] * 15 + ["Planned"] * 15)
        rows.append((code, name, voltage, stype, status, estado_id))
    return bulk_insert_returning(
        cur, "substation",
        ["substation_code", "substation_name", "voltage_level_kv",
         "substation_type", "status", "estado_id"],
        rows, "substation_id",
    )


def populate_transmission_line(cur, sub_ids, n=500):
    rows = []
    for i in range(1, n + 1):
        code = f"LIN-{i:03d}"
        name = unique_name("Line", i)
        voltage = random.choice([69, 138, 230, 345, 500, 765])
        length = round(random.uniform(5, 1200), 2)
        ctype = random.choice(["AC", "DC"])
        origin = random.choice(sub_ids)
        dest = random.choice(sub_ids)
        while dest == origin:
            dest = random.choice(sub_ids)
        status = random.choice(["Active"] * 450 + ["Decommissioned"] * 25 + ["Planned"] * 25)
        mid_lat, mid_lon = fake_latitude_longitude()
        orig_lat = round(mid_lat + random.uniform(-1, 1), 6)
        orig_lon = round(mid_lon + random.uniform(-1, 1), 6)
        dest_lat = round(mid_lat + random.uniform(-1, 1), 6)
        dest_lon = round(mid_lon + random.uniform(-1, 1), 6)
        rows.append((
            code, name, voltage, length, ctype, origin, dest, status,
            orig_lat, orig_lon, dest_lat, dest_lon, mid_lat, mid_lon,
        ))
    return bulk_insert_returning(
        cur, "transmission_line",
        ["line_code", "line_name", "voltage_level_kv", "length_km", "circuit_type",
         "origin_substation_id", "destination_substation_id", "status",
         "origin_latitude", "origin_longitude", "destination_latitude",
         "destination_longitude", "midpoint_latitude", "midpoint_longitude"],
        rows, "line_id",
    )


# ------------------------------------------------------------------------------
# 3. Transactional data
# ------------------------------------------------------------------------------
def populate_generation_reading(cur, plant_ids_caps, days, minute_level):
    """plant_ids_caps: list of (plant_id, installed_capacity) tuples."""
    rows = []
    start_date = datetime.date(2026, 7, 1)
    step_minutes = 1 if minute_level else 60
    steps_per_day = 1440 // step_minutes
    for plant_id, cap in plant_ids_caps:
        cap = float(cap)
        for d in range(days):
            dt = start_date + datetime.timedelta(days=d)
            for step in range(steps_per_day):
                ts = datetime.datetime(dt.year, dt.month, dt.day) + datetime.timedelta(
                    minutes=step * step_minutes
                )
                output = round(random.uniform(0, cap * 0.9), 2)
                available = round(random.uniform(output, cap), 2)
                rows.append((plant_id, ts, output, available))
    # column names matched to the OLTP doc: output_mw / available_capacity
    bulk_insert(
        cur, "generation_reading",
        ["plant_id", "reading_timestamp", "output_mw", "available_capacity"],
        rows,
    )
    return len(rows)


def populate_measurement(cur, sub_ids, line_ids, days, minute_level):
    rows = []
    start_date = datetime.date(2026, 7, 1)
    step_minutes = 1 if minute_level else 60
    steps_per_day = 1440 // step_minutes

    for sub_id in sub_ids:
        for d in range(days):
            dt = start_date + datetime.timedelta(days=d)
            for step in range(steps_per_day):
                ts = datetime.datetime(dt.year, dt.month, dt.day) + datetime.timedelta(
                    minutes=step * step_minutes
                )
                freq = round(random.uniform(59.8, 60.2), 2)
                voltage = round(random.uniform(13.5, 505), 1)
                load = round(random.uniform(0, 300), 2)
                reliability = round(random.uniform(0.9, 1.0), 4)
                rows.append(("substation", sub_id, ts, None, None, freq, voltage, load, reliability))

    for line_id in line_ids:
        for d in range(days):
            dt = start_date + datetime.timedelta(days=d)
            for step in range(steps_per_day):
                ts = datetime.datetime(dt.year, dt.month, dt.day) + datetime.timedelta(
                    minutes=step * step_minutes
                )
                power_flow = round(random.uniform(0, 2000), 2)
                losses = round(power_flow * random.uniform(0.01, 0.05), 2)
                freq = round(random.uniform(59.8, 60.2), 2)
                voltage = round(random.uniform(69, 500), 1)
                # system_load_mw / reliability_index intentionally left NULL for
                # lines - the Data Vault's sat_line_measurement has no columns
                # for them (see OLTP doc, Section 2.2 known-gap note).
                rows.append(("transmission_line", line_id, ts, power_flow, losses, freq, voltage, None, None))

    bulk_insert(
        cur, "measurement",
        ["asset_type", "asset_id", "reading_timestamp", "power_flow_mw", "losses_mw",
         "frequency_hz", "voltage_kv", "system_load_mw", "reliability_index"],
        rows,
    )
    return len(rows)


def populate_occurrences(cur, plant_ids, sub_ids, line_ids, occurrence_type_ids, days):
    """~20 events/day per the OLTP doc, spread across the window."""
    n = max(1, round(20 * days))
    occ_rows = []
    start_ts = datetime.datetime(2026, 7, 1, 0, 0, 0)
    window_hours = days * 24

    for i in range(1, n + 1):
        ticket = f"TKT-{i:04d}"
        occurrence_type_id = random.choice(occurrence_type_ids)
        start_dt = start_ts + datetime.timedelta(hours=random.uniform(0, window_hours))
        resolved = random.choices([True, False], weights=[70, 30])[0]
        end_dt = start_dt + datetime.timedelta(minutes=random.randint(10, 600)) if resolved else None
        affected_load = round(random.uniform(0, 500), 2)
        customers = random.randint(0, 5000)
        occ_rows.append((ticket, occurrence_type_id, start_dt, end_dt, resolved, affected_load, customers))

    # Insert with RETURNING so we know the *real* occurrence_id for each ticket,
    # instead of assuming ticket i got id i.
    occurrence_ids = bulk_insert_returning(
        cur, "occurrence",
        ["ticket_number", "occurrence_type_id", "start_datetime", "end_datetime",
         "resolved_flag", "affected_load_mw", "customers_affected"],
        occ_rows, "occurrence_id",
    )

    asset_rows = []
    for occurrence_id in occurrence_ids:
        num_assets = random.randint(1, 3)
        chosen_assets = set()
        for _ in range(num_assets):
            asset_type = random.choice(["plant", "substation", "transmission_line"])
            asset_id = {
                "plant": random.choice(plant_ids),
                "substation": random.choice(sub_ids),
                "transmission_line": random.choice(line_ids),
            }[asset_type]
            chosen_assets.add((asset_type, asset_id))
        for atype, aid in chosen_assets:
            asset_rows.append((occurrence_id, atype, aid))

    bulk_insert(cur, "occurrence_asset", ["occurrence_id", "asset_type", "asset_id"], asset_rows)
    return len(occ_rows), len(asset_rows)


def populate_work_orders(cur, plant_ids, sub_ids, line_ids, maintenance_type_ids, days):
    """~50 work orders/day per the OLTP doc."""
    n = max(1, round(50 * days))
    wo_rows = []
    for i in range(1, n + 1):
        order = f"WO-{i:04d}"
        maintenance_type_id = random.choice(maintenance_type_ids)
        sched_date = datetime.date(2026, 7, 1) + datetime.timedelta(days=random.randint(0, max(days - 1, 0)))
        planned = round(random.uniform(1, 24), 2)
        actual = round(planned * random.uniform(0.8, 1.2), 2) if random.random() > 0.2 else None
        cost = round(random.uniform(1000, 50000), 2)
        overdue = random.choice([True, False]) if actual is not None else False
        avail = round(random.uniform(80, 100), 2)
        wo_rows.append((order, maintenance_type_id, sched_date, planned, actual, cost, overdue, avail))

    work_order_ids = bulk_insert_returning(
        cur, "work_order",
        ["order_number", "maintenance_type_id", "scheduled_date", "planned_duration_hours",
         "actual_duration_hours", "cost", "overdue_flag", "asset_availability_pct"],
        wo_rows, "work_order_id",
    )

    asset_rows = []
    for work_order_id in work_order_ids:
        num_assets = random.randint(1, 2)
        chosen_assets = set()
        for _ in range(num_assets):
            asset_type = random.choice(["plant", "substation", "transmission_line"])
            asset_id = {
                "plant": random.choice(plant_ids),
                "substation": random.choice(sub_ids),
                "transmission_line": random.choice(line_ids),
            }[asset_type]
            chosen_assets.add((asset_type, asset_id))
        for atype, aid in chosen_assets:
            asset_rows.append((work_order_id, atype, aid))

    bulk_insert(cur, "work_order_asset", ["work_order_id", "asset_type", "asset_id"], asset_rows)
    return len(wo_rows), len(asset_rows)


def populate_asset_status(cur, plant_ids, sub_ids, line_ids, days):
    rows = []
    for d in range(days):
        snap_date = datetime.date(2026, 7, 1) + datetime.timedelta(days=d)
        for plant_id in plant_ids:
            avail = round(random.uniform(80, 100), 2)
            in_op = random.choice([True] * 90 + [False] * 10)
            rows.append((snap_date, "plant", plant_id, avail, in_op))
        for sub_id in sub_ids:
            avail = round(random.uniform(85, 100), 2)
            in_op = random.choice([True] * 95 + [False] * 5)
            rows.append((snap_date, "substation", sub_id, avail, in_op))
        for line_id in line_ids:
            avail = round(random.uniform(90, 100), 2)
            in_op = random.choice([True] * 98 + [False] * 2)
            rows.append((snap_date, "transmission_line", line_id, avail, in_op))
    bulk_insert(
        cur, "asset_status",
        ["snapshot_date", "asset_type", "asset_id", "availability_pct", "in_operation_flag"],
        rows,
    )
    return len(rows)


# ------------------------------------------------------------------------------
# Main execution
# ------------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(description="Populate the ONS OLTP schema with synthetic data.")
    parser.add_argument("--days", type=int, default=3, help="Number of days of transactional data (default: 3)")
    parser.add_argument("--minute-level", action="store_true",
                         help="Generate per-minute readings (matches documented volume; large - "
                              "~1.44M measurement rows/day). Default is hourly, for feasibility.")
    parser.add_argument("--no-truncate", dest="truncate", action="store_false",
                         help="Do not truncate tables first (default truncates for a clean, idempotent run).")
    parser.set_defaults(truncate=True)
    args = parser.parse_args()

    conn = psycopg2.connect(**DB_PARAMS)
    try:
        with conn.cursor() as cur:
            if args.truncate:
                print("Truncating existing data...")
                cur.execute(
                    f"TRUNCATE TABLE {', '.join(f'{SCHEMA}.{t}' for t in TRUNCATE_ORDER)} "
                    f"RESTART IDENTITY CASCADE"
                )

            print("Populating reference tables...")
            state_ids = populate_state(cur)
            occurrence_type_ids = populate_occurrence_type(cur)
            maintenance_type_ids = populate_maintenance_type(cur)

            print("Populating master data...")
            plant_ids = populate_plant(cur, state_ids)
            sub_ids = populate_substation(cur, state_ids)
            line_ids = populate_transmission_line(cur, sub_ids)

            print("Populating transactional data...")
            cur.execute(
                f"SELECT plant_id, installed_capacity FROM {SCHEMA}.plant "
                f"WHERE plant_id = ANY(%s)", (plant_ids,)
            )
            plant_ids_caps = cur.fetchall()

            n_gen = populate_generation_reading(cur, plant_ids_caps, args.days, args.minute_level)
            n_meas = populate_measurement(cur, sub_ids, line_ids, args.days, args.minute_level)
            n_occ, n_occ_asset = populate_occurrences(
                cur, plant_ids, sub_ids, line_ids, occurrence_type_ids, args.days
            )
            n_wo, n_wo_asset = populate_work_orders(
                cur, plant_ids, sub_ids, line_ids, maintenance_type_ids, args.days
            )
            n_status = populate_asset_status(cur, plant_ids, sub_ids, line_ids, args.days)

        conn.commit()
        print("Data population complete!")
        print(f"  generation_reading : {n_gen:,} rows")
        print(f"  measurement        : {n_meas:,} rows")
        print(f"  occurrence         : {n_occ:,} rows ({n_occ_asset:,} occurrence_asset links)")
        print(f"  work_order         : {n_wo:,} rows ({n_wo_asset:,} work_order_asset links)")
        print(f"  asset_status       : {n_status:,} rows")
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


if __name__ == "__main__":
    main()
