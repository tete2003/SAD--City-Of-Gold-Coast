# SAD Snowflake Reporting Models

This folder contains the final dbt-style Snowflake reporting models prepared for the
Speed Awareness Device reporting setup for the Griffith University / City of Gold Coast project.

## Purpose

These models support validated Power BI reporting by providing:

- cleaned detailed vehicle records
- hourly site summary reporting
- current site dimension data
- deployment-aware side panel reporting
- deployment-aware councillor summary reporting
- deployment-aware hourly chart reporting

## Main Models

### 1. `mart_sierzega_fct_sad_vehicle_records_clean`

Base cleaned reporting table built from the final reporting vehicle records table.

Final agreed cleaning logic:

- valid records only
- `vehicle_event_ts` must exist
- `device_id` must exist
- `V1` must not be null
- `V2` must not be null
- `V1` must be between `10` and `150`
- `V2` must be between `10` and `150`
- site assignment fields must exist

### 2. `mart_sierzega_fct_sad_hourly_site_summary`

Pre-aggregated site/device hourly summary built from the cleaned vehicle records table.

### 3. `mart_sierzega_dim_sad_current_sites`

Current Drive Safe site dimension used for slicers, labels, and map details.

### 4. `mart_sierzega_councillor_side_panel`

Deployment-aware side panel model used for Power BI selectors and deployment detail display.

### 5. `mart_sierzega_councillor_summary`

Deployment-level councillor summary model containing KPI-style metrics.

### 6. `mart_sierzega_fct_sad_hourly_deployment_summary`

Deployment-aware hourly chart model used when charts must follow one exact installed/removed period.

## Checks File

`tables_reporting_checks.sql` is included as a validation/check script.
It is used to:

- preview records
- check row counts
- validate cleaned data quality
- validate summary consistency

This file is for checking outputs and is not a reporting model.

## Notes

- These files are written in dbt style using `config(...)` and `ref(...)`.
- The `schema.yml` file provides model documentation and column-level metadata.
- Weekly chart support is included through `week_start_date` in the hourly deployment summary model.
