/* 
   DATA VALIDATION AND PREPARATION - SPEED AWARENESS DEVICE DATA
   Database: GRIFFITH_SAD
   Warehouse: GRIFFITH_TRANSPORT_WH
*/

use warehouse GRIFFITH_TRANSPORT_WH;
use database GRIFFITH_SAD;


/* 1. Confirm current Snowflake environment */

select
    current_warehouse() as warehouse_name,
    current_database() as database_name,
    current_schema() as schema_name,
    current_role() as role_name;


/* 2. List project tables across pipeline layers */

select
    table_schema,
    table_name,
    table_type
from information_schema.tables
where table_catalog = 'GRIFFITH_SAD'
  and table_schema in (
      'PAWS_DBT_RAW',
      'PAWS_DBT_STD',
      'PAWS_DBT_EDW',
      'PAWS_DBT_RPT'
  )
order by table_schema, table_name;


/* 3. Raw vehicle completeness check */

select
    count(*) as total_rows,
    count_if(vehicle_date_raw is null or trim(vehicle_date_raw) = '') as missing_dates,
    count_if(vehicle_time_raw is null or trim(vehicle_time_raw) = '') as missing_times,
    count_if(approach_speed is null) as missing_approach_speed,
    count_if(departure_speed is null) as missing_departure_speed,
    count_if(is_valid is null or trim(is_valid) = '') as missing_valid_flag
from GRIFFITH_SAD.PAWS_DBT_RAW.SIERZEGA_RAW_SAD_VEHICLE_RECORDS;


/* 4. Inspect sample records with missing departure speed */

select
    vehicle_date_raw,
    vehicle_time_raw,
    approach_speed,
    departure_speed,
    is_valid,
    metadata_filename,
    row_number
from GRIFFITH_SAD.PAWS_DBT_RAW.SIERZEGA_RAW_SAD_VEHICLE_RECORDS
where departure_speed is null
limit 20;


/* 5. Raw validity flag analysis */

select
    is_valid,
    count(*) as total_rows,
    count_if(departure_speed is null) as missing_departure_speed,
    count_if(approach_speed = 0) as approach_speed_zero,
    count_if(approach_speed = 255) as approach_speed_255
from GRIFFITH_SAD.PAWS_DBT_RAW.SIERZEGA_RAW_SAD_VEHICLE_RECORDS
group by is_valid
order by total_rows desc;


/* 6. Standardised vehicle validation */

select
    count(*) as total_rows,
    count_if(vehicle_event_ts is null) as missing_vehicle_event_ts,
    count_if(device_id is null or trim(device_id) = '') as missing_device_id,
    count_if(approach_speed is null) as missing_approach_speed,
    count_if(departure_speed is null) as missing_departure_speed,
    count_if(is_valid is null or trim(is_valid) = '') as missing_valid_flag
from GRIFFITH_SAD.PAWS_DBT_STD.SIERZEGA_STD_SAD_VEHICLE_RECORDS;


/* 7. Standardised validity flag analysis */

select
    is_valid,
    count(*) as total_rows,
    count_if(vehicle_event_ts is null) as missing_vehicle_event_ts,
    count_if(departure_speed is null) as missing_departure_speed,
    count_if(approach_speed = 0) as approach_speed_zero,
    count_if(approach_speed = 255) as approach_speed_255
from GRIFFITH_SAD.PAWS_DBT_STD.SIERZEGA_STD_SAD_VEHICLE_RECORDS
group by is_valid
order by total_rows desc;


/* 8. Duplicate summary check in standardised layer */

with duplicate_check as (
    select
        device_id,
        vehicle_event_ts,
        approach_speed,
        departure_speed,
        is_valid,
        count(*) as duplicate_count
    from GRIFFITH_SAD.PAWS_DBT_STD.SIERZEGA_STD_SAD_VEHICLE_RECORDS
    group by
        device_id,
        vehicle_event_ts,
        approach_speed,
        departure_speed,
        is_valid
    having count(*) > 1
)
select
    count(*) as duplicate_groups,
    coalesce(sum(duplicate_count), 0) as records_in_duplicate_groups,
    coalesce(sum(duplicate_count - 1), 0) as extra_duplicate_records
from duplicate_check;


/* 9. Duplicate summary check for clean speed records */

with clean_speed_records as (
    select
        device_id,
        vehicle_event_ts,
        approach_speed,
        departure_speed,
        is_valid
    from GRIFFITH_SAD.PAWS_DBT_STD.SIERZEGA_STD_SAD_VEHICLE_RECORDS
    where is_valid = '+'
      and vehicle_event_ts is not null
      and device_id is not null
      and approach_speed between 1 and 150
      and departure_speed between 1 and 150
),
duplicate_check as (
    select
        device_id,
        vehicle_event_ts,
        approach_speed,
        departure_speed,
        is_valid,
        count(*) as duplicate_count
    from clean_speed_records
    group by
        device_id,
        vehicle_event_ts,
        approach_speed,
        departure_speed,
        is_valid
    having count(*) > 1
)
select
    count(*) as duplicate_groups,
    coalesce(sum(duplicate_count), 0) as records_in_duplicate_groups,
    coalesce(sum(duplicate_count - 1), 0) as extra_duplicate_records
from duplicate_check;


/* 10. Row count reconciliation before deduplication */

select
    count(*) as standardised_total_records,
    count_if(
        is_valid = '+'
        and vehicle_event_ts is not null
        and device_id is not null
        and approach_speed between 1 and 150
        and departure_speed between 1 and 150
    ) as clean_speed_records_before_deduplication,
    count(*) - count_if(
        is_valid = '+'
        and vehicle_event_ts is not null
        and device_id is not null
        and approach_speed between 1 and 150
        and departure_speed between 1 and 150
    ) as excluded_records
from GRIFFITH_SAD.PAWS_DBT_STD.SIERZEGA_STD_SAD_VEHICLE_RECORDS;


/* 11. Row count reconciliation after deduplication */

with clean_speed_records as (
    select
        *,
        row_number() over (
            partition by
                device_id,
                vehicle_event_ts,
                approach_speed,
                departure_speed,
                is_valid
            order by metadata_filename, row_number
        ) as duplicate_rank
    from GRIFFITH_SAD.PAWS_DBT_STD.SIERZEGA_STD_SAD_VEHICLE_RECORDS
    where is_valid = '+'
      and vehicle_event_ts is not null
      and device_id is not null
      and approach_speed between 1 and 150
      and departure_speed between 1 and 150
)
select
    count(*) as clean_speed_records_before_deduplication,
    count_if(duplicate_rank = 1) as clean_speed_records_after_deduplication,
    count_if(duplicate_rank > 1) as duplicate_records_removed
from clean_speed_records;


/* 12. Speed range validation */

select
    count(*) as valid_records,
    count_if(approach_speed < 1 or approach_speed > 150) as invalid_approach_speed_range,
    count_if(departure_speed < 1 or departure_speed > 150) as invalid_departure_speed_range,
    min(approach_speed) as min_approach_speed,
    max(approach_speed) as max_approach_speed,
    min(departure_speed) as min_departure_speed,
    max(departure_speed) as max_departure_speed
from GRIFFITH_SAD.PAWS_DBT_STD.SIERZEGA_STD_SAD_VEHICLE_RECORDS
where is_valid = '+'
  and vehicle_event_ts is not null
  and device_id is not null
  and approach_speed is not null
  and departure_speed is not null;


/* 13. Clean speed record summary after deduplication */

with clean_speed_records as (
    select
        *,
        row_number() over (
            partition by
                device_id,
                vehicle_event_ts,
                approach_speed,
                departure_speed,
                is_valid
            order by metadata_filename, row_number
        ) as duplicate_rank
    from GRIFFITH_SAD.PAWS_DBT_STD.SIERZEGA_STD_SAD_VEHICLE_RECORDS
    where is_valid = '+'
      and vehicle_event_ts is not null
      and device_id is not null
      and approach_speed between 1 and 150
      and departure_speed between 1 and 150
)
select
    count(*) as clean_speed_records,
    round(avg(approach_speed), 2) as avg_approach_speed,
    round(avg(departure_speed), 2) as avg_departure_speed,
    round(avg(approach_speed - departure_speed), 2) as avg_speed_reduction,
    count_if(approach_speed > departure_speed) as speed_reduced_count,
    count_if(approach_speed = departure_speed) as no_change_count,
    count_if(approach_speed < departure_speed) as speed_increased_count
from clean_speed_records
where duplicate_rank = 1;


/* 14. Speed behaviour classification after deduplication */

with clean_speed_records as (
    select
        *,
        row_number() over (
            partition by
                device_id,
                vehicle_event_ts,
                approach_speed,
                departure_speed,
                is_valid
            order by metadata_filename, row_number
        ) as duplicate_rank
    from GRIFFITH_SAD.PAWS_DBT_STD.SIERZEGA_STD_SAD_VEHICLE_RECORDS
    where is_valid = '+'
      and vehicle_event_ts is not null
      and device_id is not null
      and approach_speed between 1 and 150
      and departure_speed between 1 and 150
),
sad_prepared_vehicle_events as (
    select
        case
            when approach_speed > departure_speed then 'speed_reduced'
            when approach_speed = departure_speed then 'no_change'
            when approach_speed < departure_speed then 'speed_increased'
            else 'unknown'
        end as speed_behaviour,
        approach_speed,
        departure_speed,
        approach_speed - departure_speed as speed_reduction
    from clean_speed_records
    where duplicate_rank = 1
)
select
    speed_behaviour,
    count(*) as records,
    round(avg(approach_speed), 2) as avg_approach_speed,
    round(avg(departure_speed), 2) as avg_departure_speed,
    round(avg(speed_reduction), 2) as avg_speed_reduction
from sad_prepared_vehicle_events
group by speed_behaviour
order by records desc;


/* 15. Prepared vehicle dataset summary after deduplication */

with clean_speed_records as (
    select
        *,
        row_number() over (
            partition by
                device_id,
                vehicle_event_ts,
                approach_speed,
                departure_speed,
                is_valid
            order by metadata_filename, row_number
        ) as duplicate_rank
    from GRIFFITH_SAD.PAWS_DBT_STD.SIERZEGA_STD_SAD_VEHICLE_RECORDS
    where is_valid = '+'
      and vehicle_event_ts is not null
      and device_id is not null
      and approach_speed between 1 and 150
      and departure_speed between 1 and 150
),
sad_prepared_vehicle_events as (
    select
        device_id,
        vehicle_event_ts,
        date(vehicle_event_ts) as event_date,
        hour(vehicle_event_ts) as event_hour,
        approach_speed,
        departure_speed,
        approach_speed - departure_speed as speed_reduction,
        case
            when approach_speed > departure_speed then 'speed_reduced'
            when approach_speed = departure_speed then 'no_change'
            when approach_speed < departure_speed then 'speed_increased'
            else 'unknown'
        end as speed_behaviour,
        is_valid,
        metadata_filename,
        row_number
    from clean_speed_records
    where duplicate_rank = 1
)
select
    count(*) as prepared_rows,
    round(avg(approach_speed), 2) as avg_approach_speed,
    round(avg(departure_speed), 2) as avg_departure_speed,
    round(avg(speed_reduction), 2) as avg_speed_reduction
from sad_prepared_vehicle_events;


/* 16. Hourly summary for Power BI after deduplication */

with clean_speed_records as (
    select
        *,
        row_number() over (
            partition by
                device_id,
                vehicle_event_ts,
                approach_speed,
                departure_speed,
                is_valid
            order by metadata_filename, row_number
        ) as duplicate_rank
    from GRIFFITH_SAD.PAWS_DBT_STD.SIERZEGA_STD_SAD_VEHICLE_RECORDS
    where is_valid = '+'
      and vehicle_event_ts is not null
      and device_id is not null
      and approach_speed between 1 and 150
      and departure_speed between 1 and 150
),
sad_prepared_vehicle_events as (
    select
        device_id,
        vehicle_event_ts,
        date(vehicle_event_ts) as event_date,
        hour(vehicle_event_ts) as event_hour,
        approach_speed,
        departure_speed,
        approach_speed - departure_speed as speed_reduction,
        case
            when approach_speed > departure_speed then 'speed_reduced'
            when approach_speed = departure_speed then 'no_change'
            when approach_speed < departure_speed then 'speed_increased'
            else 'unknown'
        end as speed_behaviour
    from clean_speed_records
    where duplicate_rank = 1
)
select
    event_date,
    event_hour,
    count(*) as vehicle_count,
    round(avg(approach_speed), 2) as avg_approach_speed,
    round(avg(departure_speed), 2) as avg_departure_speed,
    round(avg(speed_reduction), 2) as avg_speed_reduction,
    count_if(speed_behaviour = 'speed_reduced') as speed_reduced_count,
    count_if(speed_behaviour = 'no_change') as no_change_count,
    count_if(speed_behaviour = 'speed_increased') as speed_increased_count,
    round(
        100 * count_if(speed_behaviour = 'speed_reduced') / nullif(count(*), 0),
        2
    ) as speed_reduction_rate_pct
from sad_prepared_vehicle_events
group by event_date, event_hour
order by event_date, event_hour;


/* 17. Hourly summary consistency check
   Run this immediately after Block 16.
*/

with hourly_summary as (
    select
        event_date,
        event_hour,
        vehicle_count,
        speed_reduced_count,
        no_change_count,
        speed_increased_count
    from table(result_scan(last_query_id()))
)
select
    count(*) as hourly_rows_checked,
    count_if(
        vehicle_count != speed_reduced_count + no_change_count + speed_increased_count
    ) as mismatch_rows
from hourly_summary;


/* 18. Property/site reference data validation */

select
    count(*) as total_properties,
    count_if(gis_id is null or trim(gis_id) = '') as missing_gis_id,
    count_if(site_type is null or trim(site_type) = '') as missing_site_type,
    count_if(latitude is null) as missing_latitude,
    count_if(longitude is null) as missing_longitude,
    count_if(speed is null) as missing_posted_speed,
    count_if(site_type = 'Drive Safe') as drive_safe_sites
from GRIFFITH_SAD.PAWS_DBT_STD.SIERZEGA_STD_SAD_PROPERTIES;


/* 19. Final reporting mart site assignment validation */

select
    count(*) as final_records,
    count_if(property_surrogate_key is null) as missing_property_key,
    count_if(gis_id is null or trim(gis_id) = '') as missing_gis_id,
    count_if(posted_speed is null) as missing_posted_speed,
    count_if(match_status is null or trim(match_status) = '') as missing_match_status,
    count_if(match_status = 'found') as direct_matches,
    count_if(match_status = 'schedule_backfill') as schedule_backfill_matches
from GRIFFITH_SAD.PAWS_DBT_RPT.MART_SIERZEGA_FCT_SAD_VEHICLE_RECORDS_FINAL;


/* 20. Site assignment by match status */

select
    match_status,
    count(*) as total_records,
    count_if(property_surrogate_key is null) as missing_property_key,
    count_if(gis_id is null or trim(gis_id) = '') as missing_gis_id,
    count_if(posted_speed is null) as missing_posted_speed
from GRIFFITH_SAD.PAWS_DBT_RPT.MART_SIERZEGA_FCT_SAD_VEHICLE_RECORDS_FINAL
group by match_status
order by total_records desc;


/* 21. Final clean site-level reporting preview */

select
    device_id,
    vehicle_event_ts,
    date(vehicle_event_ts) as event_date,
    hour(vehicle_event_ts) as event_hour,
    gis_id,
    property_surrogate_key,
    posted_speed,
    approach_speed,
    departure_speed,
    reduction_speed,
    case
        when approach_speed > departure_speed then 'speed_reduced'
        when approach_speed = departure_speed then 'no_change'
        when approach_speed < departure_speed then 'speed_increased'
        else 'unknown'
    end as speed_behaviour,
    match_status
from GRIFFITH_SAD.PAWS_DBT_RPT.MART_SIERZEGA_FCT_SAD_VEHICLE_RECORDS_FINAL
where is_valid_flag = true
  and vehicle_event_ts is not null
  and device_id is not null
  and approach_speed between 1 and 150
  and departure_speed between 1 and 150
  and property_surrogate_key is not null
  and gis_id is not null
  and posted_speed is not null
limit 100;
