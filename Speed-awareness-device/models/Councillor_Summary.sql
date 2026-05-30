{{
    config(
        materialized="view"
    )
}}

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
    from {{ ref("mart_sierzega_dim_sad_site_scheduling") }}
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

summary_base as (
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
        street_name as deployment_street,
        location,
        suburb,
        speed_limit_kmh,
        latitude,
        longitude,
        stay_start,
        stay_end,
        to_date(stay_start) as period_start_date,
        to_date(stay_start) as device_installed,
        to_date(stay_end) as device_removed,
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
        b.deployment_key,
        b.property_surrogate_key,
        b.device_id,
        b.gis_id,
        b.division_number,
        b.deployment_street,
        b.location,
        b.suburb,
        b.speed_limit_kmh,
        b.latitude,
        b.longitude,
        b.stay_start,
        b.stay_end,
        b.period_start_date,
        b.device_installed,
        b.device_removed,
        b.days_installed,
        b.period_type,
        e.vehicle_record_sk,
        e.vehicle_event_ts,
        e.approach_speed,
        e.departure_speed,
        e.reduction_speed
    from summary_base b
    left join {{ ref("mart_sierzega_fct_sad_vehicle_records_clean") }} e
        on e.property_surrogate_key = b.property_surrogate_key
       and e.device_id = b.device_id
       and e.vehicle_event_ts >= b.stay_start
       and (
            b.stay_end is null
            or e.vehicle_event_ts < dateadd(hour, 1, b.stay_end)
       )
),

summary_metrics as (
    select
        deployment_key,
        count(vehicle_record_sk) as total_vehicles,

        count_if(approach_speed > speed_limit_kmh) as vehicles_over_speed_limit_v1,
        count_if(departure_speed > speed_limit_kmh) as vehicles_over_speed_limit_v2,

        round(
            100 * count_if(approach_speed > speed_limit_kmh)
            / nullif(count(vehicle_record_sk), 0),
            2
        ) as pct_vehicles_over_speed_limit_v1,

        round(
            100 * count_if(departure_speed > speed_limit_kmh)
            / nullif(count(vehicle_record_sk), 0),
            2
        ) as pct_vehicles_over_speed_limit_v2,

        round(avg(approach_speed), 2) as avg_speed_v1_kmh,
        round(avg(departure_speed), 2) as avg_speed_v2_kmh,

        round(
            100 * count_if(approach_speed <= speed_limit_kmh)
            / nullif(count(vehicle_record_sk), 0),
            2
        ) as pct_already_complying_v1,

        round(
            100 * count_if(departure_speed <= speed_limit_kmh)
            / nullif(count(vehicle_record_sk), 0),
            2
        ) as pct_already_complying_v2,

        round(
            avg(case when reduction_speed > 0 then reduction_speed end),
            2
        ) as avg_speed_reduction_all_slowing_kmh,

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
            )
            / nullif(count_if(approach_speed > speed_limit_kmh), 0),
            2
        ) as pct_over_limit_slowed_below_limit

    from deployment_events
    group by deployment_key
)

select
    b.deployment_key,
    b.property_surrogate_key,
    b.device_id,
    b.gis_id,
    current_date() as prepared_on,
    b.period_type,
    b.period_start_date,
    b.device_installed,
    b.device_removed,
    b.days_installed,
    b.division_number,
    c.councillor_name,
    b.deployment_street,
    b.location,
    b.suburb,
    b.speed_limit_kmh,
    b.latitude,
    b.longitude,
    m.total_vehicles,
    m.vehicles_over_speed_limit_v1,
    m.vehicles_over_speed_limit_v2,
    m.pct_vehicles_over_speed_limit_v1,
    m.pct_vehicles_over_speed_limit_v2,
    m.avg_speed_v1_kmh,
    m.avg_speed_v2_kmh,
    m.pct_already_complying_v1,
    m.pct_already_complying_v2,
    m.avg_speed_reduction_all_slowing_kmh,
    m.avg_speed_reduction_over_limit_kmh,
    m.pct_over_limit_slowed_below_limit
from summary_base b
left join GRIFFITH_SAD.PAWS_DBT_RPT.DIM_COUNCILLOR_NAME c
    on b.division_number = c.division_number
left join summary_metrics m
    on b.deployment_key = m.deployment_key