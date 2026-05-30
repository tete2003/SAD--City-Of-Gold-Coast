{{
    config(
        materialized="view"
    )
}}

-- depends_on: {{ ref('sierzega_dim_sad_property') }}

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
from {{ ref("sierzega_dim_sad_property") }}
where is_current = true
  and site_type = 'Drive Safe'
  and gis_id is not null
  and trim(gis_id) <> ''
