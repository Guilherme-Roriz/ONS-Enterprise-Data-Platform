# ONS Enterprise Data Platform

## Overview

The **ONS Enterprise Data Platform** is an end-to-end Data Engineering portfolio project inspired by the Brazilian National Electric System Operator (ONS).

The project simulates operational data from an electrical power grid and demonstrates how enterprise data flows through a modern analytics platform—from transactional systems to a dimensional data warehouse.

Its primary goal is to showcase industry-standard data engineering practices, including data modeling, ETL development, data warehousing, and analytical data preparation using a realistic business domain.

## Architecture

The platform follows a modern enterprise data architecture:

<<<<<<< HEAD
> Synthetic Data Sources → Operational Database (OLTP) & Data Lake → Data Vault → Analytics & Business Intelligence
=======
> Synthetic Data Sources → Operational Database (OLTP) → ETL / ELT Pipelines → Enterprise Data Warehouse → Analytics & Business Intelligence
>>>>>>> c7b13817471399e21f30c12929209d45af0ab129

For a detailed architecture diagram, see the documentation in `/docs`.

## Technologies

- PostgreSQL
- SQL
- Python
- Data Vault 2.0
- Kimball Dimensional Modeling
- Git & GitHub

---

## Features

- Synthetic power system data generation
- Enterprise data modeling
- ETL / ELT pipelines
- Data Warehouse implementation
- Dimensional modeling
- Business-oriented analytical datasets
- End-to-end project documentation

---

## Documentation

Detailed technical documentation, architecture diagrams, data models, and implementation decisions are available in the **`/docs`** directory.

---

## Project Status

🚧 In development

This project is being developed incrementally as part of a continuous learning journey in Data Engineering and Analytics Engineering.

---

## License

Licensed under the MIT License.
