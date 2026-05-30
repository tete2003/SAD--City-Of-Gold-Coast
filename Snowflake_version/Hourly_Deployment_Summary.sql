use warehouse GRIFFITH_TRANSPORT_WH;
use database GRIFFITH_SAD;
use schema PAWS_DBT_RPT;

create or replace table GRIFFITH_SAD.PAWS_DBT_RPT.MART_SIERZEGA_FCT_SAD_HOURLY_DEPLOYMENT_SUMMARY as
with scheduling_dedup as (
    select
        property_surrogate_key,
        device_id,
        gis_id,
        division_number,
        street_name,
        site_location as location,
        suburb,
        speed as speed_limit_kmh,
        property_latitude as latitude,
        property_longitude as longitude,
        stay_start,
        stay_end,
        duration_hours
    from GRIFFITH_SAD.PAWS_DBT_RPT.MART_SIERZEGA_DIM_SAD_SITE_SCHEDULING
    qualify row_number() over (
        partition by
            property_surrogate_key,
            device_id,
            gis_id,
            stay_start,
            stay_end
        order by stay_start
    ) = 1
),

deployment_base as (
    select
        concat(
            property_surrogate_key, ' | ',
            device_id, ' | ',
            gis_id, ' | ',
            to_char(stay_start, 'YYYY-MM-DD HH24:MI:SS'), ' | ',
            coalesce(to_char(stay_end, 'YYYY-MM-DD HH24:MI:SS'), 'OPEN')
        ) as deployment_key,
        property_surrogate_key,
        device_id,
        gis_id,
        division_number,
        street_name,
        location,
        suburb,
        speed_limit_kmh,
        latitude,
        longitude,
        stay_start,
        stay_end,
        to_date(stay_start) as installed_date,
        to_date(stay_end) as removed_date,
        datediff(
            day,
            to_date(stay_start),
            coalesce(to_date(stay_end), current_date())
        ) + 1 as days_installed,
        case
            when row_number() over (
                partition by property_surrogate_key, device_id, gis_id
                order by stay_start desc
            ) = 1 then 'Latest'
            else 'Historical'
        end as period_type
    from scheduling_dedup
),

deployment_events as (
    select
        d.deployment_key,
        d.property_surrogate_key,
        d.device_id,
        d.gis_id,
        d.division_number,
        d.street_name,
        d.location,
        d.suburb,
        d.speed_limit_kmh,
        d.latitude,
        d.longitude,
        d.installed_date,
        d.removed_date,
        d.days_installed,
        d.period_type,
        v.vehicle_record_sk,
        v.vehicle_event_ts,
        v.event_date,
        v.event_hour,
        date_trunc('hour', v.vehicle_event_ts) as interval_start,
        v.approach_speed,
        v.departure_speed,
        v.reduction_speed,
        v.speed_behaviour,
        v.above_posted_speed_on_approach
    from deployment_base d
    left join GRIFFITH_SAD.PAWS_DBT_RPT.MART_SIERZEGA_FCT_SAD_VEHICLE_RECORDS_CLEAN v
        on v.property_surrogate_key = d.property_surrogate_key
       and v.device_id = d.device_id
       and v.vehicle_event_ts >= d.stay_start
       and (
            d.stay_end is null
            or v.vehicle_event_ts < dateadd(hour, 1, d.stay_end)
       )
)

select
    deployment_key,
    property_surrogate_key,
    device_id,
    gis_id,
    division_number,
    street_name,
    location,
    suburb,
    speed_limit_kmh,
    latitude,
    longitude,
    installed_date,
    removed_date,
    days_installed,
    period_type,
    event_date,
    event_hour,
    interval_start,
    count(vehicle_record_sk) as vehicle_count,
    round(avg(approach_speed), 2) as avg_approach_speed,
    round(avg(departure_speed), 2) as avg_departure_speed,
    round(avg(reduction_speed), 2) as avg_speed_reduction,
    count_if(speed_behaviour = 'speed_reduced') as speed_reduced_count,
    count_if(speed_behaviour = 'no_change') as no_change_count,
    count_if(speed_behaviour = 'speed_increased') as speed_increased_count,
    count_if(above_posted_speed_on_approach = true) as above_posted_speed_count,
    count_if(approach_speed > speed_limit_kmh) as vehicles_over_speed_limit_v1,
    count_if(departure_speed > speed_limit_kmh) as vehicles_over_speed_limit_v2,
    count_if(approach_speed <= speed_limit_kmh) as vehicles_below_speed_limit_v1,
    count_if(departure_speed <= speed_limit_kmh) as vehicles_below_speed_limit_v2,
    round(
        100 * count_if(speed_behaviour = 'speed_reduced') / nullif(count(vehicle_record_sk), 0),
        2
    ) as speed_reduction_rate_pct,
    round(
        100 * count_if(above_posted_speed_on_approach = true) / nullif(count(vehicle_record_sk), 0),
        2
    ) as above_posted_speed_rate_pct,
    round(
        100 * count_if(approach_speed > speed_limit_kmh) / nullif(count(vehicle_record_sk), 0),
        2
    ) as pct_vehicles_over_speed_limit_v1,
    round(
        100 * count_if(departure_speed > speed_limit_kmh) / nullif(count(vehicle_record_sk), 0),
        2
    ) as pct_vehicles_over_speed_limit_v2,
    round(
        100 * count_if(approach_speed <= speed_limit_kmh) / nullif(count(vehicle_record_sk), 0),
        2
    ) as pct_already_complying_v1,
    round(
        100 * count_if(departure_speed <= speed_limit_kmh) / nullif(count(vehicle_record_sk), 0),
        2
    ) as pct_already_complying_v2,
    round(avg(case when reduction_speed > 0 then reduction_speed end), 2) as avg_speed_reduction_all_slowing_kmh,
    round(
        avg(
            case
                when approach_speed > speed_limit_kmh and reduction_speed > 0
                then reduction_speed
            end
        ),
        2
    ) as avg_speed_reduction_over_limit_kmh,
    round(
        100 * count_if(
            approach_speed > speed_limit_kmh
            and departure_speed <= speed_limit_kmh
        ) / nullif(count_if(approach_speed > speed_limit_kmh), 0),
        2
    ) as pct_over_limit_slowed_below_limit
from deployment_events
group by
    deployment_key,
    property_surrogate_key,
    device_id,
    gis_id,
    division_number,
    street_name,
    location,
    suburb,
    speed_limit_kmh,
    latitude,
    longitude,
    installed_date,
    removed_date,
    days_installed,
    period_type,
    event_date,
    event_hour,
    interval_start;
