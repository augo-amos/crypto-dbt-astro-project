-- int_daily_returns computes day-over-day return for each coin using
-- the LAG() window function. LAG() looks at the previous row within
-- a partition — here, the previous calendar day for the same coin.
--
-- Why an intermediate model rather than putting this in the mart?
-- Because three different marts will use daily_return_pct.
-- Defining it once here means: change the formula → every mart updates.
-- Duplicate it in each mart → one day you'll update two and forget the third.

with prices as (
    -- ref() instead of source() because stg_prices is a dbt model, not a source table.
    -- dbt builds the full dependency graph from ref() calls and runs models
    -- in the correct order automatically. You never specify an execution order.
    select * from {{ ref('stg_prices') }}
),

with_lag as (
    select
        coin_id,
        date,
        open_usd,
        high_usd,
        low_usd,
        close_usd,
        volume_usd,
        market_cap_usd,
        intraday_range_pct,

        -- LAG(close_usd) fetches the close_usd from the previous row
        -- within each coin's partition, ordered by date ascending.
        -- PARTITION BY coin_id ensures we don't bleed across coins —
        -- without it, Bitcoin's last row would be the "previous day"
        -- for Ethereum's first row, which is meaningless.
        lag(close_usd) over (
            partition by coin_id
            order by date asc
        )                           as prev_close_usd,

        lag(volume_usd) over (
            partition by coin_id
            order by date asc
        )                           as prev_volume_usd

    from prices
),

with_returns as (
    select
        *,

        -- Daily return: how much did the close price move since yesterday?
        -- Expressed as a percentage. The first row per coin has null
        -- prev_close_usd (no "yesterday" exists), so daily_return_pct
        -- is null for those rows. That's correct — don't impute a fake value.
        round(
            (close_usd - prev_close_usd)
            / nullif(prev_close_usd, 0) * 100,
            4
        )                           as daily_return_pct,

        -- Simple boolean: was today a green candle?
        case
            when close_usd > prev_close_usd then true
            when close_usd < prev_close_usd then false
            else null                    -- null for first row or flat day
        end                         as is_up_day,

        -- Volume change vs previous day
        round(
            (volume_usd - prev_volume_usd)
            / nullif(prev_volume_usd, 0) * 100,
            4
        )                           as volume_change_pct

    from with_lag
)

select * from with_returns