{{
    config(
        materialized="table"
    )
}}

-- depends_on: {{ ref('mart_sierzega_fct_sad_vehicle_records_final') }}

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
    case
        when posted_speed is null then null
        when approach_speed > posted_speed then true
        else false
    end as above_posted_speed_on_approach,
    match_status,
    vehicle_wh_inserted_date,
    vehicle_metadata_filename
from {{ ref("mart_sierzega_fct_sad_vehicle_records_final") }}
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
