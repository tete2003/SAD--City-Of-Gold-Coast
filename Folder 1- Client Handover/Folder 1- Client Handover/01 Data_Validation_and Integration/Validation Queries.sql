-- =====================================================================
-- CGC-34 Data Validation Queries
-- Project: Speed Awareness Devices - Power BI Dashboard Migration
-- Author: Liya Mary Saju (Business Analyst & BI Developer)
-- Date: 4 May 2026
-- 
-- Purpose: Validate Power BI dashboard KPI values against Snowflake
--          source-of-truth data marts.
-- 
-- Data sources:
--   - Block 16 source: PAWS_DBT_STD.SIERZEGA_STD_SAD_VEHICLE_RECORDS
--                      (powers Pages 1 & 2: Overview, Speed Behaviour)
--   - Block 21 source: PAWS_DBT_RPT.MART_SIERZEGA_FCT_SAD_VEHICLE_RECORDS_FINAL
--                      (powers Pages 3 & 4: Councillor Summary, Posted Speed)
-- 
-- Outcome: 23 of 24 KPIs validated across all 4 dashboard pages.
-- =====================================================================

USE WAREHOUSE GRIFFITH_TRANSPORT_WH;
USE DATABASE GRIFFITH_SAD;


-- ---------------------------------------------------------------------
-- QUERY 1: Block 16 hourly summary (full output for Pages 1 & 2)
-- Returns 24,553 rows - one per (date, hour) combination
-- ---------------------------------------------------------------------
WITH clean_speed_records AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY device_id, vehicle_event_ts, approach_speed, departure_speed, is_valid
            ORDER BY metadata_filename, row_number
        ) AS duplicate_rank
    FROM GRIFFITH_SAD.PAWS_DBT_STD.SIERZEGA_STD_SAD_VEHICLE_RECORDS
    WHERE is_valid = '+'
      AND vehicle_event_ts IS NOT NULL
      AND device_id IS NOT NULL
      AND approach_speed BETWEEN 1 AND 150
      AND departure_speed BETWEEN 1 AND 150
),
sad_prepared_vehicle_events AS (
    SELECT
        device_id,
        vehicle_event_ts,
        DATE(vehicle_event_ts) AS event_date,
        HOUR(vehicle_event_ts) AS event_hour,
        approach_speed,
        departure_speed,
        approach_speed - departure_speed AS speed_reduction,
        CASE
            WHEN approach_speed > departure_speed THEN 'speed_reduced'
            WHEN approach_speed = departure_speed THEN 'no_change'
            WHEN approach_speed < departure_speed THEN 'speed_increased'
            ELSE 'unknown'
        END AS speed_behaviour
    FROM clean_speed_records
    WHERE duplicate_rank = 1
)
SELECT
    event_date,
    event_hour,
    COUNT(*) AS vehicle_count,
    ROUND(AVG(approach_speed), 2) AS avg_approach_speed,
    ROUND(AVG(departure_speed), 2) AS avg_departure_speed,
    ROUND(AVG(speed_reduction), 2) AS avg_speed_reduction,
    COUNT_IF(speed_behaviour = 'speed_reduced') AS speed_reduced_count,
    COUNT_IF(speed_behaviour = 'no_change') AS no_change_count,
    COUNT_IF(speed_behaviour = 'speed_increased') AS speed_increased_count,
    ROUND(100 * COUNT_IF(speed_behaviour = 'speed_reduced') / NULLIF(COUNT(*), 0), 2) AS speed_reduction_rate_pct
FROM sad_prepared_vehicle_events
GROUP BY event_date, event_hour
ORDER BY event_date, event_hour;


-- ---------------------------------------------------------------------
-- QUERY 2: Pages 1 & 2 KPI validation summary
-- Aggregates Block 16 source to match dashboard KPI cards
-- ---------------------------------------------------------------------
WITH clean_speed_records AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY device_id, vehicle_event_ts, approach_speed, departure_speed, is_valid
            ORDER BY metadata_filename, row_number
        ) AS duplicate_rank
    FROM GRIFFITH_SAD.PAWS_DBT_STD.SIERZEGA_STD_SAD_VEHICLE_RECORDS
    WHERE is_valid = '+'
      AND vehicle_event_ts IS NOT NULL
      AND device_id IS NOT NULL
      AND approach_speed BETWEEN 1 AND 150
      AND departure_speed BETWEEN 1 AND 150
)
SELECT
    'Block 16 (Pages 1 & 2 source-of-truth)' AS source,
    COUNT(*) AS total_vehicles,
    ROUND(AVG(approach_speed), 2) AS avg_approach_speed,
    ROUND(AVG(departure_speed), 2) AS avg_departure_speed,
    ROUND(AVG(approach_speed - departure_speed), 2) AS avg_speed_reduction,
    COUNT_IF(approach_speed > departure_speed) AS speed_reduced_count,
    COUNT_IF(approach_speed = departure_speed) AS no_change_count,
    COUNT_IF(approach_speed < departure_speed) AS speed_increased_count,
    ROUND(100.0 * COUNT_IF(approach_speed > departure_speed) / COUNT(*), 2) AS slowing_down_pct,
    ROUND(100.0 * COUNT_IF(approach_speed = departure_speed) / COUNT(*), 2) AS no_change_pct,
    ROUND(100.0 * COUNT_IF(approach_speed < departure_speed) / COUNT(*), 2) AS speed_increased_pct
FROM clean_speed_records
WHERE duplicate_rank = 1;


-- ---------------------------------------------------------------------
-- QUERY 3: Page 3 (Councillor Summary) KPI validation
-- Aggregates Block 21 source to match dashboard KPI cards
-- ---------------------------------------------------------------------
SELECT
    'Block 21 (Page 3 source-of-truth)' AS source,
    COUNT(*) AS total_vehicles,
    COUNT_IF(approach_speed > posted_speed) AS v1_over_speed,
    COUNT_IF(departure_speed > posted_speed) AS v2_over_speed,
    ROUND(AVG(approach_speed), 2) AS v1_avg_speed,
    ROUND(AVG(departure_speed), 2) AS v2_avg_speed,
    ROUND(100.0 * COUNT_IF(approach_speed > posted_speed) / COUNT(*), 2) AS v1_over_pct,
    ROUND(100.0 * COUNT_IF(departure_speed > posted_speed) / COUNT(*), 2) AS v2_over_pct,
    ROUND(AVG(reduction_speed), 2) AS avg_reduction,
    ROUND(AVG(CASE WHEN approach_speed > posted_speed AND approach_speed > departure_speed
                   THEN reduction_speed END), 2) AS reduction_speeders_who_slowed,
    ROUND(100.0 * COUNT_IF(approach_speed > departure_speed) / COUNT(*), 2) AS slowing_pct
FROM GRIFFITH_SAD.PAWS_DBT_RPT.MART_SIERZEGA_FCT_SAD_VEHICLE_RECORDS_FINAL
WHERE is_valid_flag = TRUE
  AND vehicle_event_ts IS NOT NULL
  AND device_id IS NOT NULL
  AND approach_speed BETWEEN 1 AND 150
  AND departure_speed BETWEEN 1 AND 150
  AND property_surrogate_key IS NOT NULL
  AND gis_id IS NOT NULL
  AND posted_speed IS NOT NULL;


-- ---------------------------------------------------------------------
-- QUERY 4: Per-device aggregation (Block 21 detail by GIS ID)
-- Returns 109 rows - one per device
-- ---------------------------------------------------------------------
SELECT
    gis_id,
    posted_speed,
    COUNT(*) AS total_vehicles,
    COUNT_IF(approach_speed > posted_speed) AS v1_over_speed,
    COUNT_IF(departure_speed > posted_speed) AS v2_over_speed,
    ROUND(AVG(approach_speed), 2) AS v1_avg_speed,
    ROUND(AVG(departure_speed), 2) AS v2_avg_speed,
    ROUND(100.0 * COUNT_IF(approach_speed > posted_speed) / COUNT(*), 2) AS v1_over_pct,
    ROUND(100.0 * COUNT_IF(departure_speed > posted_speed) / COUNT(*), 2) AS v2_over_pct,
    ROUND(AVG(reduction_speed), 2) AS avg_reduction
FROM GRIFFITH_SAD.PAWS_DBT_RPT.MART_SIERZEGA_FCT_SAD_VEHICLE_RECORDS_FINAL
WHERE is_valid_flag = TRUE
  AND vehicle_event_ts IS NOT NULL
  AND device_id IS NOT NULL
  AND approach_speed BETWEEN 1 AND 150
  AND departure_speed BETWEEN 1 AND 150
  AND property_surrogate_key IS NOT NULL
  AND gis_id IS NOT NULL
  AND posted_speed IS NOT NULL
GROUP BY gis_id, posted_speed
ORDER BY gis_id;


-- ---------------------------------------------------------------------
-- QUERY 5: Page 4 (Posted Speed Analysis) KPI validation
-- ---------------------------------------------------------------------
SELECT
    'Page 4 (Posted Speed Analysis)' AS source,
    COUNT(*) AS total_vehicles,
    COUNT_IF(departure_speed > posted_speed) AS v2_over_speed,
    COUNT_IF(departure_speed <= posted_speed) AS v2_not_over_speed,
    ROUND(100.0 * COUNT_IF(departure_speed <= posted_speed) / COUNT(*), 2) AS v2_below_pct,
    ROUND(100.0 * COUNT_IF(departure_speed > posted_speed) / COUNT(*), 2) AS v2_over_pct
FROM GRIFFITH_SAD.PAWS_DBT_RPT.MART_SIERZEGA_FCT_SAD_VEHICLE_RECORDS_FINAL
WHERE is_valid_flag = TRUE
  AND vehicle_event_ts IS NOT NULL
  AND device_id IS NOT NULL
  AND approach_speed BETWEEN 1 AND 150
  AND departure_speed BETWEEN 1 AND 150
  AND property_surrogate_key IS NOT NULL
  AND gis_id IS NOT NULL
  AND posted_speed IS NOT NULL;


-- ---------------------------------------------------------------------
-- QUERY 6: Definition test for "Speed Reduction (Speeding Only)"
-- Tested 3 alternative definitions to identify dashboard's logic
-- Result: Dashboard uses Definition B (3.74 km/h)
-- ---------------------------------------------------------------------
SELECT
    ROUND(AVG(CASE WHEN approach_speed > posted_speed THEN reduction_speed END), 2) AS def_a_all_speeders,
    ROUND(AVG(CASE WHEN approach_speed > posted_speed AND approach_speed > departure_speed
                   THEN reduction_speed END), 2) AS def_b_speeders_who_slowed,
    ROUND(AVG(CASE WHEN approach_speed > posted_speed AND departure_speed <= posted_speed
                   THEN reduction_speed END), 2) AS def_c_speeders_now_compliant,
    COUNT_IF(approach_speed > posted_speed) AS total_speeders,
    COUNT_IF(approach_speed > posted_speed AND approach_speed > departure_speed) AS speeders_who_slowed,
    COUNT_IF(approach_speed > posted_speed AND departure_speed <= posted_speed) AS speeders_now_compliant
FROM GRIFFITH_SAD.PAWS_DBT_RPT.MART_SIERZEGA_FCT_SAD_VEHICLE_RECORDS_FINAL
WHERE is_valid_flag = TRUE
  AND vehicle_event_ts IS NOT NULL
  AND device_id IS NOT NULL
  AND approach_speed BETWEEN 1 AND 150
  AND departure_speed BETWEEN 1 AND 150
  AND property_surrogate_key IS NOT NULL
  AND gis_id IS NOT NULL
  AND posted_speed IS NOT NULL;


-- ---------------------------------------------------------------------
-- QUERY 7: Data layer comparison (STD vs RPT mart)
-- Confirms why Pages 1 & 2 (60M) differ from Pages 3 & 4 (32M)
-- ---------------------------------------------------------------------
SELECT
    'STD layer (Pages 1 & 2 source)' AS source_table,
    COUNT(*) AS total_vehicles
FROM GRIFFITH_SAD.PAWS_DBT_STD.SIERZEGA_STD_SAD_VEHICLE_RECORDS
WHERE is_valid = '+'
  AND vehicle_event_ts IS NOT NULL
  AND device_id IS NOT NULL
  AND approach_speed BETWEEN 1 AND 150
  AND departure_speed BETWEEN 1 AND 150

UNION ALL

SELECT
    'RPT mart (Pages 3 & 4 source)' AS source_table,
    COUNT(*) AS total_vehicles
FROM GRIFFITH_SAD.PAWS_DBT_RPT.MART_SIERZEGA_FCT_SAD_VEHICLE_RECORDS_FINAL
WHERE is_valid_flag = TRUE
  AND vehicle_event_ts IS NOT NULL
  AND device_id IS NOT NULL
  AND approach_speed BETWEEN 1 AND 150
  AND departure_speed BETWEEN 1 AND 150
  AND property_surrogate_key IS NOT NULL
  AND gis_id IS NOT NULL
  AND posted_speed IS NOT NULL;