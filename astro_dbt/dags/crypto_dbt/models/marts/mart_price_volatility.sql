-- Daily rolling volatility metrics per coin.
-- Useful for time series charts showing how risky each coin was day-by-day.

with returns as (
    select * from {{ ref('int_daily_returns') }}
),

volatility as (
    select
        coin_id,
        date,
        close_usd,
        daily_return_pct,
        intraday_range_pct,

        -- 7-day rolling standard deviation of daily returns.
        -- ROWS BETWEEN 6 PRECEDING AND CURRENT ROW gives a 7-row window.
        -- stddev() on 7 values gives you short-term volatility —
        -- how wildly the coin moved in the past week.
        round(
            stddev(daily_return_pct) over (
                partition by coin_id
                order by date asc
                rows between 6 preceding and current row
            ),
            4
        )                                       as rolling_7d_volatility,

        -- 30-day rolling volatility for longer-term trend context.
        -- Compare 7d vs 30d: if 7d > 30d, volatility is increasing.
        round(
            stddev(daily_return_pct) over (
                partition by coin_id
                order by date asc
                rows between 29 preceding and current row
            ),
            4
        )                                       as rolling_30d_volatility,

        -- 7-day rolling average return.
        -- Together with rolling volatility, this is the start of a
        -- Sharpe ratio calculation (return / volatility).
        round(
            avg(daily_return_pct) over (
                partition by coin_id
                order by date asc
                rows between 6 preceding and current row
            ),
            4
        )                                       as rolling_7d_avg_return,

        -- How volatile was this coin relative to all others on this date?
        -- RANK() gives 1 to the most volatile coin each day.
        rank() over (
            partition by date
            order by intraday_range_pct desc nulls last
        )                                       as daily_volatility_rank

    from returns
    where daily_return_pct is not null
)

select * from volatility
order by coin_id, date