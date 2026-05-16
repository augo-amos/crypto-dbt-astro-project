-- The most general-purpose mart. One row per coin per day,
-- with OHLCV, returns, cumulative return, and coin metadata joined.
-- This is the mart a time-series chart or backtesting query would use.

with returns as (
    select * from {{ ref('int_daily_returns') }}
),

coins as (
    select coin_id, name, symbol, market_cap_rank
    from {{ ref('stg_coins') }}
),

final as (
    select
        r.date,
        r.coin_id,
        c.name,
        c.symbol,
        c.market_cap_rank,
        r.open_usd,
        r.high_usd,
        r.low_usd,
        r.close_usd,
        r.volume_usd,
        r.market_cap_usd,
        r.intraday_range_pct,
        r.daily_return_pct,
        r.is_up_day,
        r.volume_change_pct,

        -- Cumulative compound return from the start of the period.
        -- This answers: "If I had invested $1 on day 1, what is it worth today?"
        --
        -- Why EXP(SUM(LN(...))) instead of just SUM(daily_return_pct)?
        -- Because returns compound — a 10% gain followed by a 10% loss
        -- does NOT return you to zero; it leaves you at 99% of your original.
        -- Summing percentages ignores compounding and gives the wrong answer.
        -- The correct formula is: product of (1 + each daily return).
        -- SQL doesn't have a built-in product aggregation, but:
        --   product(x) = EXP(SUM(LN(x)))
        -- So we convert each day's multiplier (1 + r/100) to log space,
        -- sum them (which multiplies in log space), then exponentiate back.
        -- The -1 at the end converts the final multiplier to a percentage return.
        -- nullif(r.daily_return_pct, 0) skips null return rows (first row per coin)
        -- by treating them as zero change.
        round(
            (
                exp(
                    sum(
                        ln(1.0 + coalesce(r.daily_return_pct, 0) / 100.0)
                    ) over (
                        partition by r.coin_id
                        order by r.date asc
                        rows between unbounded preceding and current row
                    )
                ) - 1.0
            ) * 100,
            4
        )                                       as cumulative_return_pct

    from returns r
    left join coins c on r.coin_id = c.coin_id
)

select * from final
order by date desc, market_cap_rank asc nulls last