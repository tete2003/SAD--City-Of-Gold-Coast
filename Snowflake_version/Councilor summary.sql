use warehouse GRIFFITH_TRANSPORT_WH;
use database GRIFFITH_SAD;
use schema PAWS_DBT_RPT;

create or replace view GRIFFITH_SAD.PAWS_DBT_RPT.MART_SIERZEGA_COUNCILLOR_SUMMARY as
with deployments as (
    select
        concat(
            device_id, ' | ',
            gis_id, ' | ',
            to_char(stay_start, 'YYYY-MM-DD')
        ) as deployment_key,
        device_id,
        property_surrogate_key,
        gis_id,
        division_number,
        street_name as deployment_street,
        site_location as location,
        speed as speed_limit_kmh,
        stay_start as device_installed_ts,
        stay_end as device_removed_ts,
        datediff(
            day,
            to_date(stay_start),
            coalesce(to_date(stay_end), current_date())
        ) + 1 as days_installed
    from GRIFFITH_SAD.PAWS_DBT_RPT.MART_SIERZEGA_DIM_SAD_SITE_SCHEDULING
),

deployment_events as (
    select
        d.deployment_key,
        d.device_id,
        d.property_surrogate_key,
        d.gis_id,
        d.division_number,
        d.deployment_street,
        d.location,
        d.speed_limit_kmh,
        d.device_installed_ts,
        d.device_removed_ts,
        d.days_installed,
        e.vehicle_record_sk,
        e.vehicle_event_ts,
        e.approach_speed,
        e.departure_speed,
        e.reduction_speed
    from deployments d
    left join GRIFFITH_SAD.PAWS_DBT_RPT.MART_SIERZEGA_FCT_SAD_VEHICLE_RECORDS_CLEAN e
        on e.device_id = d.device_id
       and e.property_surrogate_key = d.property_surrogate_key
       and e.vehicle_event_ts >= d.device_installed_ts
       and (
            d.device_removed_ts is null
            or e.vehicle_event_ts < dateadd(hour, 1, d.device_removed_ts)
       )
),

final_summary as (
    select
        deployment_key,
        gis_id,
        current_date() as prepared_on,
        division_number,
        deployment_street,
        location,
        to_date(device_installed_ts) as device_installed,
        to_date(device_removed_ts) as device_removed,
        days_installed,
        count(vehicle_record_sk) as total_vehicles,
        device_id,
        speed_limit_kmh,

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
    group by
        deployment_key,
        gis_id,
        division_number,
        deployment_street,
        location,
        device_installed_ts,
        device_removed_ts,
        days_installed,
        device_id,
        speed_limit_kmh
)

select
    fs.deployment_key,
    fs.gis_id,
    c.councillor_name,
    fs.prepared_on,
    fs.division_number,
    fs.deployment_street,
    fs.location,
    fs.device_installed,
    fs.device_removed,
    fs.days_installed,
    fs.total_vehicles,
    fs.device_id,
    fs.speed_limit_kmh,
    fs.vehicles_over_speed_limit_v1,
    fs.vehicles_over_speed_limit_v2,
    fs.pct_vehicles_over_speed_limit_v1,
    fs.pct_vehicles_over_speed_limit_v2,
    fs.avg_speed_v1_kmh,
    fs.avg_speed_v2_kmh,
    fs.pct_already_complying_v1,
    fs.pct_already_complying_v2,
    fs.avg_speed_reduction_all_slowing_kmh,
    fs.avg_speed_reduction_over_limit_kmh,
    fs.pct_over_limit_slowed_below_limit
from final_summary fs
left join GRIFFITH_SAD.PAWS_DBT_RPT.DIM_COUNCILLOR_NAME c
    on fs.division_number = c.division_number;


