# ONS Enterprise Data Platform

## Overview

The **ONS Enterprise Data Platform** is an end-to-end Data Engineering portfolio project inspired by the Brazilian National Electric System Operator (ONS).

The project simulates operational data from an electrical power grid and demonstrates how enterprise data flows through a modern analytics platform—from transactional systems to a dimensional data warehouse.

Its primary goal is to showcase industry-standard data engineering practices, including data modeling, ETL development, data warehousing, and analytical data preparation using a realistic business domain.

## Architecture

The platform follows a modern enterprise data architecture:

> Synthetic Data Sources → Operational Database (OLTP) & Data Lake → Data Vault → Analytics & Business Intelligence

For a detailed architecture diagram, see the documentation in `/docs`.

## Technologies

- PostgreSQL
- SQL
- Python
- Data Vault 2.0
- Kimball Dimensional Modeling
- Git & GitHub

## Features

- Synthetic power system data generation
- Enterprise data modeling
- ETL / ELT pipelines
- Data Warehouse implementation
- Dimensional modeling
- Business-oriented analytical datasets
- End-to-end project documentation
- Configuration-driven OLTP → Data Vault ingestion
- Idempotent Data Vault → Galaxy dimensional ETL with SCD2 resolution

## Documentation

Detailed technical documentation, architecture diagrams, data models, and implementation decisions are available in the **`/docs`** directory.

ETL operating guides:

- [`ETL/1ETL.md`](ETL/1ETL.md) — OLTP → Data Vault
- [`ETL/2ETL.md`](ETL/2ETL.md) — Data Vault → Galaxy

Install the Python dependencies with `pip install -r requirements.txt` and copy `.env.example` to `.env`.

Run the ETL stages independently:

```bash
python -m ETL.data_vault.main
python -m ETL.galaxy.main
```

## Project Status

🚧 In development

This project is being developed incrementally as part of a continuous learning journey in Data Engineering and Analytics Engineering.

---

## License

Licensed under the MIT License.
