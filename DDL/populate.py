#!/usr/bin/env python3
"""
ONS Enterprise Data Platform – OLTP Data Population Script
Version: 1.2 (corrected – schema search_path fix)
Author: Guilherme Roriz
Description: Generates static synthetic data for all OLTP tables,
             respecting business rules and referential integrity.
"""

import random
import decimal
import datetime
import psycopg2
import psycopg2.extras
from faker import Faker

# ------------------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------------------
DB_PARAMS = {}

SEED = 42
random.seed(SEED)
fake = Faker("pt_BR")
fake.seed_instance(SEED)

# ------------------------------------------------------------------------------
# Database helper functions
# ------------------------------------------------------------------------------
def get_connection():
    """Return a connection with search_path set to oltp."""
    conn = psycopg2.connect(**DB_PARAMS)
    conn.cursor().execute("SET search_path TO oltp;")
    conn.commit()
    return conn

def bulk_insert_returning(cur, table, columns, rows, returning_col):
    """
    Insert multiple rows and return a list of the specified column values.
    """
    if not rows:
        return []
    col_names = ", ".join(columns)
    sql = (
        f"INSERT INTO {table} ({col_names}) VALUES %s "
        f"RETURNING {returning_col}"
    )
    results = psycopg2.extras.execute_values(cur, sql, rows, fetch=True)
    return [row[0] for row in results]

def insert_rows(cur, table, columns, rows):
    """Simple INSERT – caller must commit afterwards."""
    if not rows:
        return
    col_names = ", ".join(columns)
    sql = f"INSERT INTO {table} ({col_names}) VALUES %s"
    psycopg2.extras.execute_values(cur, sql, rows)

# ------------------------------------------------------------------------------
# Data generation helpers
# ------------------------------------------------------------------------------
def fake_latitude_longitude():
    """Generate random coordinates within Brazil."""
    lat = random.uniform(-33.7, 5.3)
    lon = random.uniform(-73.9, -34.8)
    return round(lat, 6), round(lon, 6)

# ------------------------------------------------------------------------------
# Population functions
# ------------------------------------------------------------------------------
def populate_state(cur):
    """Insert Brazilian states and return list of state_id."""
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
        ("SP", "São Paulo"), ("SE", "Sergipe"), ("TO", "Tocantins")
    ]
    rows = [(code, name, fake.unique.street_name()) for code, name in ufs]
    return bulk_insert_returning(
        cur, "state",
        ["state_code", "state_name", "ons_control_area"],
        rows, "state_id"
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
    rows = [(code, cat, sub, sev) for code, cat, sub, sev in types]
    insert_rows(cur, "occurrence_type", ["type_code", "category", "subtype", "severity_level"], rows)

def populate_maintenance_type(cur):
    types = [
        ("PREV", "Preventive", "Routine Inspection", "Low"),
        ("CORR", "Corrective", "Emergency Repair", "Urgent"),
        ("PRED", "Preventive", "Predictive Maintenance", "Medium"),
        ("OVER", "Preventive", "Major Overhaul", "High"),
        ("CORR_LINE", "Corrective", "Line Repair", "High"),
    ]
    rows = [(code, cat, sub, pri) for code, cat, sub, pri in types]
    insert_rows(cur, "maintenance_type", ["type_code", "category", "subtype", "priority_level"], rows)

def populate_plant(cur, state_ids):
    """Insert 100 power plants and return their IDs."""
    types = ["Hydro", "Thermal", "Wind", "Solar", "Nuclear"]
    rows = []
    for i in range(1, 101):
        code = f"PLT-{i:03d}"
        name = fake.unique.company() + " Plant"
        ptype = random.choice(types)
        cap = round(random.uniform(50, 2000), 2) if ptype != "Nuclear" else round(random.uniform(500, 1500), 2)
        start = datetime.date(1980, 1, 1)
        end = datetime.date(2025, 12, 31)
        delta = end - start
        commission_date = start + datetime.timedelta(days=random.randint(0, delta.days))
        operator = fake.company()
        state_id = random.choice(state_ids)
        status = random.choice(["Active"] * 80 + ["Decommissioned"] * 10 + ["Under Construction"] * 10)
        rows.append((code, name, ptype, cap, commission_date, operator, state_id, status))
    return bulk_insert_returning(
        cur, "plant",
        ["plant_code", "plant_name", "plant_type", "installed_capacity",
         "commissioning_date", "operator_name", "state_id", "status"],
        rows, "plant_id"
    )

def populate_substation(cur, state_ids):
    """Insert 200 substations and return their IDs."""
    stypes = ["Step-up", "Step-down", "Switching"]
    rows = []
    for i in range(1, 201):
        code = f"SUB-{i:03d}"
        name = fake.unique.city() + " Substation"
        voltage = random.choice([13.8, 34.5, 69, 138, 230, 345, 500])
        stype = random.choice(stypes)
        state_id = random.choice(state_ids)
        status = random.choice(["Active"] * 170 + ["Decommissioned"] * 15 + ["Planned"] * 15)
        rows.append((code, name, voltage, stype, state_id, status))
    return bulk_insert_returning(
        cur, "substation",
        ["substation_code", "substation_name", "voltage_level_kv",
         "substation_type", "state_id", "status"],
        rows, "substation_id"
    )

def populate_transmission_line(cur, sub_ids):
    """Insert 500 transmission lines and return their IDs."""
    rows = []
    for i in range(1, 501):
        code = f"LIN-{i:03d}"
        name = fake.unique.street_name() + f" Line {i}"
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
        rows.append((code, name, voltage, length, ctype, origin, dest, status,
                     orig_lat, orig_lon, dest_lat, dest_lon, mid_lat, mid_lon))
    return bulk_insert_returning(
        cur, "transmission_line",
        ["line_code", "line_name", "voltage_level_kv", "length_km",
         "circuit_type", "origin_substation_id", "destination_substation_id", "status",
         "origin_latitude", "origin_longitude", "destination_latitude", "destination_longitude",
         "midpoint_latitude", "midpoint_longitude"],
        rows, "line_id"
    )

def populate_generation_reading(cur, plant_ids):
    """3 days of hourly readings for generation."""
    rows = []
    start_date = datetime.date(2026, 7, 1)
    for plant_id in plant_ids:
        cur.execute("SELECT installed_capacity FROM plant WHERE plant_id = %s", (plant_id,))
        cap = cur.fetchone()[0]
        for d in range(3):
            dt = start_date + datetime.timedelta(days=d)
            for hour in range(24):
                ts = datetime.datetime(dt.year, dt.month, dt.day, hour, 0, 0)
                output = round(random.uniform(0, float(cap) * 0.9), 2)
                available = round(random.uniform(output, float(cap)), 2)
                rows.append((plant_id, ts, output, available))
    insert_rows(cur, "generation_reading", ["plant_id", "reading_timestamp",
                "generation_output_mw", "available_capacity_mw"], rows)

def populate_measurement(cur, sub_ids, line_ids):
    """3 days of hourly measurements (polymorphic)."""
    rows = []
    start_date = datetime.date(2026, 7, 1)
    for sub_id in sub_ids:
        for d in range(3):
            dt = start_date + datetime.timedelta(days=d)
            for hour in range(24):
                ts = datetime.datetime(dt.year, dt.month, dt.day, hour, 0, 0)
                freq = round(random.uniform(59.8, 60.2), 2)
                voltage = round(random.uniform(13.5, 505), 1)
                load = round(random.uniform(0, 300), 2)
                reliability = round(random.uniform(0.9, 1.0), 4)
                rows.append(("substation", sub_id, ts, None, None, freq, voltage, load, reliability))
    for line_id in line_ids:
        for d in range(3):
            dt = start_date + datetime.timedelta(days=d)
            for hour in range(24):
                ts = datetime.datetime(dt.year, dt.month, dt.day, hour, 0, 0)
                power_flow = round(random.uniform(0, 2000), 2)
                losses = round(power_flow * random.uniform(0.01, 0.05), 2)
                freq = round(random.uniform(59.8, 60.2), 2)
                voltage = round(random.uniform(69, 500), 1)
                rows.append(("transmission_line", line_id, ts, power_flow, losses, freq, voltage, None, None))
    insert_rows(cur, "measurement", ["asset_type", "asset_id", "reading_timestamp",
                "power_flow_mw", "losses_mw", "frequency_hz", "voltage_kv",
                "system_load_mw", "reliability_index"], rows)

def populate_occurrences(cur, plant_ids, sub_ids, line_ids):
    """100 occurrence events over 3 days, some with multiple assets."""
    rows = []
    asset_rows = []
    start_ts = datetime.datetime(2026, 7, 1, 0, 0, 0)
    for i in range(1, 101):
        ticket = f"TKT-{i:04d}"
        type_id = random.randint(1, 8)
        start_dt = start_ts + datetime.timedelta(hours=random.randint(0, 72))
        resolved = random.choices([True, False], weights=[70, 30])[0]
        end_dt = None if not resolved else start_dt + datetime.timedelta(minutes=random.randint(10, 600))
        affected_load = round(random.uniform(0, 500), 2)
        customers = random.randint(0, 5000)
        rows.append((ticket, type_id, start_dt, end_dt, resolved, affected_load, customers))
        num_assets = random.randint(1, 3)
        chosen = set()
        for _ in range(num_assets):
            atype = random.choice(["plant", "substation", "transmission_line"])
            if atype == "plant":
                aid = random.choice(plant_ids)
            elif atype == "substation":
                aid = random.choice(sub_ids)
            else:
                aid = random.choice(line_ids)
            chosen.add((atype, aid))
        for atype, aid in chosen:
            asset_rows.append((i, atype, aid))  # occurrence_id will match insertion order
    insert_rows(cur, "occurrence", ["ticket_number", "occurrence_type_id", "start_datetime",
                "end_datetime", "resolved_flag", "affected_load_mw", "customers_affected"], rows)
    insert_rows(cur, "occurrence_asset", ["occurrence_id", "asset_type", "asset_id"], asset_rows)

def populate_work_orders(cur, plant_ids, sub_ids, line_ids):
    """50 work orders over 3 days."""
    rows = []
    asset_rows = []
    for i in range(1, 51):
        order = f"WO-{i:04d}"
        type_id = random.randint(1, 5)
        sched_date = datetime.date(2026, 7, 1) + datetime.timedelta(days=random.randint(0, 2))
        planned = round(random.uniform(1, 24), 2)
        actual = round(planned * random.uniform(0.8, 1.2), 2) if random.random() > 0.2 else None
        cost = round(random.uniform(1000, 50000), 2)
        overdue = random.choice([True, False]) if actual is not None else False
        avail = round(random.uniform(80, 100), 2)
        rows.append((order, type_id, sched_date, planned, actual, cost, overdue, avail))
        num_assets = random.randint(1, 2)
        chosen = set()
        for _ in range(num_assets):
            atype = random.choice(["plant", "substation", "transmission_line"])
            if atype == "plant":
                aid = random.choice(plant_ids)
            elif atype == "substation":
                aid = random.choice(sub_ids)
            else:
                aid = random.choice(line_ids)
            chosen.add((atype, aid))
        for atype, aid in chosen:
            asset_rows.append((i, atype, aid))  # work_order_id sequential
    insert_rows(cur, "work_order", ["order_number", "maintenance_type_id", "scheduled_date",
                "planned_duration_hours", "actual_duration_hours", "cost", "overdue_flag",
                "asset_availability_pct"], rows)
    insert_rows(cur, "work_order_asset", ["work_order_id", "asset_type", "asset_id"], asset_rows)

def populate_asset_status(cur, plant_ids, sub_ids, line_ids):
    """Daily snapshot for each asset for 3 days."""
    rows = []
    for d in range(3):
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
    insert_rows(cur, "asset_status", ["snapshot_date", "asset_type", "asset_id",
                                 "availability_pct", "in_operation_flag"], rows)

# ------------------------------------------------------------------------------
# Main execution
# ------------------------------------------------------------------------------
def main():
    with get_connection() as conn:
        with conn.cursor() as cur:
            print("Populating reference tables...")
            state_ids = populate_state(cur)
            populate_occurrence_type(cur)
            populate_maintenance_type(cur)

            print("Populating master data...")
            plant_ids = populate_plant(cur, state_ids)
            sub_ids = populate_substation(cur, state_ids)
            line_ids = populate_transmission_line(cur, sub_ids)

            print("Populating transactional data...")
            populate_generation_reading(cur, plant_ids)
            populate_measurement(cur, sub_ids, line_ids)
            populate_occurrences(cur, plant_ids, sub_ids, line_ids)
            populate_work_orders(cur, plant_ids, sub_ids, line_ids)
            populate_asset_status(cur, plant_ids, sub_ids, line_ids)

            conn.commit()
    print("Data population complete!")

if __name__ == "__main__":
    main()
