{{
    config(
        materialized="table"
    )
}}

-- depends_on: {{ ref('mart_sierzega_fct_sad_vehicle_records_clean') }}

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
from {{ ref("mart_sierzega_fct_sad_vehicle_records_clean") }}
group by
    property_surrogate_key,
    gis_id,
    device_id,
    event_date,
    event_hour,
    date_trunc('hour', vehicle_event_ts),
    posted_speed
