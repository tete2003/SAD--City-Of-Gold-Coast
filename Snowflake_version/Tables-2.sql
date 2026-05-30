use warehouse GRIFFITH_TRANSPORT_WH;
use database GRIFFITH_SAD;
use schema PAWS_DBT_RPT;

/* 1-TEST THE CLEANED REPORTING LOGIC
   This checks what the final reporting-ready vehicle records
   will look like before creating a permanent table.*/

with clean_vehicle_records as (
    select
        vehicle_record_sk,
        device_id,
        vehicle_event_ts,
        date(vehicle_event_ts) as event_date,
        hour(vehicle_event_ts) as event_hour,
        vehicle_row_number,
        hourly_interval_start,
        latitude,
        longitude,
        sum_vehicles,
        avg_speed,
        avg_speed_reduction,
        approach_speed,
        departure_speed,
        reduction_speed,
        case
            when approach_speed > departure_speed then 'speed_reduced'
            when approach_speed = departure_speed then 'no_change'
            when approach_speed < departure_speed then 'speed_increased'
            else 'unknown'
        end as speed_behaviour,
        is_valid_flag,
        property_surrogate_key,
        gis_id,
        posted_speed,
        -- classify whether speed reduced, stayed the same, or increased
        case
            when posted_speed is null then null
            when approach_speed > posted_speed then true
            else false
        end as above_posted_speed_on_approach,
        match_status,
        vehicle_wh_inserted_date,
        vehicle_metadata_filename
    from GRIFFITH_SAD.PAWS_DBT_RPT.MART_SIERZEGA_FCT_SAD_VEHICLE_RECORDS_FINAL
    where is_valid_flag = true
      and vehicle_event_ts is not null
      and device_id is not null
      and approach_speed is not null
      and departure_speed is not null
      and approach_speed between 10 and 150
      and departure_speed between 10 and 150
      and property_surrogate_key is not null
      and gis_id is not null
      and posted_speed is not null
)
select *
from clean_vehicle_records
limit 100;

/* 2-VALIDATE THE CLEANED LOGIC NUMERICALLY
   This confirms row count, uniqueness, behaviour split,
   and average speed metrics before creating the table.*/
   
with clean_vehicle_records as (
    select
        vehicle_record_sk,
        device_id,
        vehicle_event_ts,
        approach_speed,
        departure_speed,
        reduction_speed,
        property_surrogate_key,
        gis_id,
        posted_speed,
        case
            when approach_speed > departure_speed then 'speed_reduced'
            when approach_speed = departure_speed then 'no_change'
            when approach_speed < departure_speed then 'speed_increased'
            else 'unknown'
        end as speed_behaviour
    from GRIFFITH_SAD.PAWS_DBT_RPT.MART_SIERZEGA_FCT_SAD_VEHICLE_RECORDS_FINAL
    where is_valid_flag = true
      and vehicle_event_ts is not null
      and device_id is not null
      and approach_speed is not null
      and departure_speed is not null
      and approach_speed between 10 and 150
      and departure_speed between 10 and 150
      and property_surrogate_key is not null
      and gis_id is not null
      and posted_speed is not null
)
select
    count(*) as clean_rows,
    count(distinct vehicle_record_sk) as distinct_vehicle_record_sk,
    count_if(speed_behaviour = 'speed_reduced') as speed_reduced_count,
    count_if(speed_behaviour = 'no_change') as no_change_count,
    count_if(speed_behaviour = 'speed_increased') as speed_increased_count,
    round(avg(approach_speed), 2) as avg_approach_speed,
    round(avg(departure_speed), 2) as avg_departure_speed,
    round(avg(reduction_speed), 2) as avg_speed_reduction
from clean_vehicle_records;

/* 3-CREATE THE PERMANENT CLEAN DETAIL TABLE
   This becomes the detailed reporting-ready source table*/

create or replace table GRIFFITH_SAD.PAWS_DBT_RPT.MART_SIERZEGA_FCT_SAD_VEHICLE_RECORDS_CLEAN as
with source_data as (
    select
        vehicle_record_sk,
        device_id,
        vehicle_event_ts,
        date(vehicle_event_ts) as event_date,
        hour(vehicle_event_ts) as event_hour,
        vehicle_row_number,
        hourly_interval_start,
        latitude,
        longitude,
        sum_vehicles,
        avg_speed,
        avg_speed_reduction,
        approach_speed,
        departure_speed,
        reduction_speed,
        is_valid_flag,
        property_surrogate_key,
        gis_id,
        posted_speed,
        match_status,
        vehicle_wh_inserted_date,
        vehicle_metadata_filename
    from GRIFFITH_SAD.PAWS_DBT_RPT.MART_SIERZEGA_FCT_SAD_VEHICLE_RECORDS_FINAL
    where is_valid_flag = true
      and vehicle_event_ts is not null
      and device_id is not null
      and approach_speed is not null
      and departure_speed is not null
      and approach_speed between 10 and 150
      and departure_speed between 10 and 150
      and property_surrogate_key is not null
      and gis_id is not null
      and posted_speed is not null
)
select
    vehicle_record_sk,
    device_id,
    vehicle_event_ts,
    event_date,
    event_hour,
    vehicle_row_number,
    hourly_interval_start,
    latitude,
    longitude,
    sum_vehicles,
    avg_speed,
    avg_speed_reduction,
    approach_speed,
    departure_speed,
    reduction_speed,
    case
        when approach_speed > departure_speed then 'speed_reduced'
        when approach_speed = departure_speed then 'no_change'
        when approach_speed < departure_speed then 'speed_increased'
        else 'unknown'
    end as speed_behaviour,
    is_valid_flag,
    property_surrogate_key,
    gis_id,
    posted_speed,
    case
        when posted_speed is null then null
        when approach_speed > posted_speed then true
        else false
    end as above_posted_speed_on_approach,
    match_status,
    vehicle_wh_inserted_date,
    vehicle_metadata_filename
from source_data;

/* Quick row count check after table creation */

select count(*) as clean_table_rows
from GRIFFITH_SAD.PAWS_DBT_RPT.MART_SIERZEGA_FCT_SAD_VEHICLE_RECORDS_CLEAN;


/*create the permanent hourly summary table.
  This is the main dashboard-friendly table for Power BI.*/

create or replace table GRIFFITH_SAD.PAWS_DBT_RPT.MART_SIERZEGA_FCT_SAD_HOURLY_SITE_SUMMARY as
select
    property_surrogate_key,
    gis_id,
    device_id,
    event_date,
    event_hour,
    date_trunc('hour', vehicle_event_ts) as interval_start,
    posted_speed,
    count(*) as vehicle_count,
    round(avg(approach_speed), 2) as avg_approach_speed,
    round(avg(departure_speed), 2) as avg_departure_speed,
    round(avg(reduction_speed), 2) as avg_speed_reduction,
    count_if(speed_behaviour = 'speed_reduced') as speed_reduced_count,
    count_if(speed_behaviour = 'no_change') as no_change_count,
    count_if(speed_behaviour = 'speed_increased') as speed_increased_count,
    count_if(above_posted_speed_on_approach = true) as above_posted_speed_count,
    round(
        100 * count_if(speed_behaviour = 'speed_reduced') / nullif(count(*), 0),
        2
    ) as speed_reduction_rate_pct,
    round(
        100 * count_if(above_posted_speed_on_approach = true) / nullif(count(*), 0),
        2
    ) as above_posted_speed_rate_pct
from GRIFFITH_SAD.PAWS_DBT_RPT.MART_SIERZEGA_FCT_SAD_VEHICLE_RECORDS_CLEAN
group by
    property_surrogate_key,
    gis_id,
    device_id,
    event_date,
    event_hour,
    date_trunc('hour', vehicle_event_ts),
    posted_speed;
    
/* Summary row count check */

select count(*) as hourly_summary_rows
from GRIFFITH_SAD.PAWS_DBT_RPT.MART_SIERZEGA_FCT_SAD_HOURLY_SITE_SUMMARY;

/* Sample rows for visual inspection */

select *
from GRIFFITH_SAD.PAWS_DBT_RPT.MART_SIERZEGA_FCT_SAD_HOURLY_SITE_SUMMARY
limit 20;

/* CREATE THE CURRENT SITES VIEW
   This provides active Drive Safe site metadata for
   slicers, labels, and maps.*/

create or replace view GRIFFITH_SAD.PAWS_DBT_RPT.MART_SIERZEGA_DIM_SAD_CURRENT_SITES as
select
    surrogate_key as property_surrogate_key,
    gis_id,
    site_type,
    street_name,
    site_location,
    suburb,
    division_number,
    speed as posted_speed,
    latitude,
    longitude,
    valid_from,
    valid_to,
    is_current
from GRIFFITH_SAD.PAWS_DBT_EDW.SIERZEGA_DIM_SAD_PROPERTY
where is_current = true
  and site_type = 'Drive Safe'
  and gis_id is not null
  and trim(gis_id) <> '';
  
/* Current site count check */

select count(*) as current_sites_rows
from GRIFFITH_SAD.PAWS_DBT_RPT.MART_SIERZEGA_DIM_SAD_CURRENT_SITES;

/* Sample current sites */

select *
from GRIFFITH_SAD.PAWS_DBT_RPT.MART_SIERZEGA_DIM_SAD_CURRENT_SITES
limit 20;


/* FINAL VALIDATION CHECKS
   These checks confirm the new reporting layer is clean,
   complete, and internally consistent.*/

-- 1. Clean detail table quality
select
    count(*) as clean_rows,
    count_if(vehicle_record_sk is null) as missing_vehicle_record_sk,
    count_if(device_id is null or trim(device_id) = '') as missing_device_id,
    count_if(vehicle_event_ts is null) as missing_vehicle_event_ts,
    count_if(property_surrogate_key is null) as missing_property_key,
    count_if(gis_id is null or trim(gis_id) = '') as missing_gis_id,
    count_if(posted_speed is null) as missing_posted_speed,
    count_if(approach_speed is null or approach_speed not between 10 and 150) as invalid_approach_speed,
    count_if(departure_speed is null or departure_speed not between 10 and 150) as invalid_departure_speed
from GRIFFITH_SAD.PAWS_DBT_RPT.MART_SIERZEGA_FCT_SAD_VEHICLE_RECORDS_CLEAN;

-- 2. Speed behaviour distribution
select
    speed_behaviour,
    count(*) as total_rows,
    round(avg(approach_speed), 2) as avg_approach_speed,
    round(avg(departure_speed), 2) as avg_departure_speed,
    round(avg(reduction_speed), 2) as avg_speed_reduction
from GRIFFITH_SAD.PAWS_DBT_RPT.MART_SIERZEGA_FCT_SAD_VEHICLE_RECORDS_CLEAN
group by speed_behaviour
order by total_rows desc;

-- 3. Hourly summary consistency
select
    count(*) as summary_rows,
    count_if(vehicle_count <= 0) as non_positive_vehicle_count_rows,
    count_if(
        vehicle_count != speed_reduced_count + no_change_count + speed_increased_count
    ) as mismatch_rows
from GRIFFITH_SAD.PAWS_DBT_RPT.MART_SIERZEGA_FCT_SAD_HOURLY_SITE_SUMMARY;

-- 4. Current sites availability
select
    count(*) as current_drive_safe_sites,
    count_if(gis_id is null or trim(gis_id) = '') as missing_gis_id,
    count_if(posted_speed is null) as missing_posted_speed,
    count_if(latitude is null or longitude is null) as missing_coordinates
from GRIFFITH_SAD.PAWS_DBT_RPT.MART_SIERZEGA_DIM_SAD_CURRENT_SITES;
