-- One row per coin. Answers the question:
-- "How did each coin perform over this 90-day period?"

with returns as (
    select * from {{ ref('int_daily_returns') }}
),

coins as (
    select * from {{ ref('stg_coins') }}
),

-- We need each coin's first and last close price for the total period return.
-- We compute these separately as a CTE to avoid repeating the correlated
-- subquery pattern from the previous version, which is expensive.
-- This approach (first/last per partition) is cleaner in Snowflake.
first_last as (
    select
        coin_id,
        first_value(close_usd) over (
            partition by coin_id
            order by date asc
            rows between unbounded preceding and unbounded following
        )                           as first_close,
        last_value(close_usd) over (
            partition by coin_id
            order by date asc
            rows between unbounded preceding and unbounded following
        )                           as last_close
    from returns
),
-- The default frame is: rows between unbounded preceding and current row, 
--- which means first_value would return the first value up to the current row, 
-- not the true first value. 
-- By specifying rows between unbounded preceding and unbounded following, 
-- we ensure that first_value and last_value consider all rows in the partition, 
-- giving us the true first and last close_usd for each coin_id.
aggregated as (
    select
        r.coin_id,
        c.name,
        c.symbol,
        c.market_cap_rank,
        c.genesis_date,

        min(r.date)                                     as first_date,
        max(r.date)                                     as last_date,
        count(*)                                        as trading_days,

        -- Price range across the full period
        round(min(r.low_usd),   4)                      as period_low_usd,
        round(max(r.high_usd),  4)                      as period_high_usd,
        round(avg(r.close_usd), 4)                      as avg_close_usd,

        -- Return statistics
        -- avg daily return: the typical day-over-day move
        round(avg(r.daily_return_pct),    4)            as avg_daily_return_pct,
        -- stddev of daily returns is the standard proxy for volatility in finance.
        -- Higher = more erratic price movement.
        round(stddev(r.daily_return_pct), 4)            as stddev_daily_return_pct,
        round(max(r.daily_return_pct),    4)            as best_day_return_pct,
        round(min(r.daily_return_pct),    4)            as worst_day_return_pct,

        sum(case when r.is_up_day = true  then 1 else 0 end) as up_days,
        sum(case when r.is_up_day = false then 1 else 0 end) as down_days,

        -- Volume
        round(avg(r.volume_usd), 0)                     as avg_daily_volume_usd,
        round(max(r.volume_usd), 0)                     as max_daily_volume_usd

    from returns r
    left join coins c on r.coin_id = c.coin_id
    group by r.coin_id, c.name, c.symbol, c.market_cap_rank, c.genesis_date
),

-- Join in the first/last close values for total period return.
-- We use a subquery of first_last deduplicated by coin_id because
-- the window function produces the same value on every row.
with_period_return as (
    select distinct coin_id, first_close, last_close
    from first_last
),

final as (
    select
        a.*,
        round(
            (p.last_close - p.first_close)
            / nullif(p.first_close, 0) * 100,
            2
        )                                               as period_total_return_pct
    from aggregated a
    left join with_period_return p on a.coin_id = p.coin_id
)

select * from final
order by market_cap_rank asc nulls last