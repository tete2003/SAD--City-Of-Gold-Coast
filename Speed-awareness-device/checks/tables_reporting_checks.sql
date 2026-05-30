/* CHECK 1 - Preview cleaned reporting records */
select *
from {{ ref("mart_sierzega_fct_sad_vehicle_records_clean") }}
limit 100;

/* CHECK 2 - Clean table row count */
select
    count(*) as clean_table_rows
from {{ ref("mart_sierzega_fct_sad_vehicle_records_clean") }};

/* CHECK 3 - Hourly summary row count */
select
    count(*) as hourly_summary_rows
from {{ ref("mart_sierzega_fct_sad_hourly_site_summary") }};

/* CHECK 4 - Preview hourly summary rows */
select *
from {{ ref("mart_sierzega_fct_sad_hourly_site_summary") }}
limit 20;

/* CHECK 5 - Current sites row count */
select
    count(*) as current_sites_rows
from {{ ref("mart_sierzega_dim_sad_current_sites") }};

/* CHECK 6 - Preview current sites rows */
select *
from {{ ref("mart_sierzega_dim_sad_current_sites") }}
limit 20;

/* CHECK 7 - Clean detail table quality */
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
from {{ ref("mart_sierzega_fct_sad_vehicle_records_clean") }};

/* CHECK 8 - Speed behaviour distribution */
select
    speed_behaviour,
    count(*) as total_rows,
    round(avg(approach_speed), 2) as avg_approach_speed,
    round(avg(departure_speed), 2) as avg_departure_speed,
    round(avg(reduction_speed), 2) as avg_speed_reduction
from {{ ref("mart_sierzega_fct_sad_vehicle_records_clean") }}
group by speed_behaviour
order by total_rows desc;

/* CHECK 9 - Hourly summary consistency */
select
    count(*) as summary_rows,
    count_if(vehicle_count <= 0) as non_positive_vehicle_count_rows,
    count_if(
        vehicle_count != speed_reduced_count + no_change_count + speed_increased_count
    ) as mismatch_rows
from {{ ref("mart_sierzega_fct_sad_hourly_site_summary") }};

/* CHECK 10 - Current sites availability */
select
    count(*) as current_drive_safe_sites,
    count_if(gis_id is null or trim(gis_id) = '') as missing_gis_id,
    count_if(posted_speed is null) as missing_posted_speed,
    count_if(latitude is null or longitude is null) as missing_coordinates
from {{ ref("mart_sierzega_dim_sad_current_sites") }};