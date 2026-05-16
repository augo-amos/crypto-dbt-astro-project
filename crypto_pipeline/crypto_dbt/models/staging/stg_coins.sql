-- Staging models do one thing: clean and standardise the raw source.
-- No joins, no aggregations, no business logic. Just types, casing,
-- renaming, and simple derived columns that belong at the lowest level.
--
-- {{ source('raw', 'coin_metadata') }} references the seeded table.
-- dbt knows this model depends on that seed, so it won't run stg_coins
-- until the seed has been loaded successfully.

with source as (
    select * from {{ source('raw', 'coin_metadata') }}
),

cleaned as (
    select
        -- Standardise casing. CoinGecko returns coin_id in lowercase,
        -- but being explicit here means the model is self-documenting.
        lower(coin_id)                              as coin_id,
        upper(symbol)                               as symbol,
        initcap(name)                               as name,

        market_cap_rank,

        -- Strip any residual HTML tags that slipped through the 500-char truncation.
        -- regexp_replace() in Snowflake removes anything matching the HTML tag pattern.
        regexp_replace(description, '<[^>]+>', '')  as description,

        -- genesis_date is already a DATE type from seeds.yml.
        -- We keep it as-is; downstream models decide how to handle nulls.
        genesis_date,
        hashing_algorithm,
        homepage,
        extracted_at

    from source
)

select * from cleaned