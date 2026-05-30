use warehouse GRIFFITH_TRANSPORT_WH;
use database GRIFFITH_SAD;
use schema PAWS_DBT_RPT;

create or replace view GRIFFITH_SAD.PAWS_DBT_RPT.MART_SIERZEGA_COUNCILLOR_SIDE_PANEL as
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

scheduling_base as (
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
        to_date(stay_start) as period_start_date,
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

vehicle_totals as (
    select
        s.property_surrogate_key,
        s.device_id,
        s.gis_id,
        s.stay_start,
        s.stay_end,
        count(v.vehicle_record_sk) as total_vehicles
    from scheduling_base s
    left join GRIFFITH_SAD.PAWS_DBT_RPT.MART_SIERZEGA_FCT_SAD_VEHICLE_RECORDS_CLEAN v
        on v.property_surrogate_key = s.property_surrogate_key
       and v.device_id = s.device_id
       and v.vehicle_event_ts >= s.stay_start
       and (
            s.stay_end is null
            or v.vehicle_event_ts < dateadd(hour, 1, s.stay_end)
       )
    group by
        s.property_surrogate_key,
        s.device_id,
        s.gis_id,
        s.stay_start,
        s.stay_end
)

select
    s.deployment_key,
    s.property_surrogate_key,
    s.device_id,
    s.gis_id,
    s.period_type,
    s.period_start_date,
    s.installed_date,
    s.removed_date,
    s.days_installed,
    s.division_number,
    c.councillor_name,
    s.suburb,
    s.street_name,
    s.location,
    s.speed_limit_kmh,
    s.latitude,
    s.longitude,
    coalesce(v.total_vehicles, 0) as total_vehicles
from scheduling_base s
left join GRIFFITH_SAD.PAWS_DBT_RPT.DIM_COUNCILLOR_NAME c
    on s.division_number = c.division_number
left join vehicle_totals v
    on s.property_surrogate_key = v.property_surrogate_key
   and s.device_id = v.device_id
   and s.gis_id = v.gis_id
   and s.stay_start = v.stay_start
   and (
        (s.stay_end is null and v.stay_end is null)
        or s.stay_end = v.stay_end
   );

