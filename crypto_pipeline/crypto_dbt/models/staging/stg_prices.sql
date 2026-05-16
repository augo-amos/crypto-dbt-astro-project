with source as (
    select * from {{ source('raw', 'historical_prices') }}
),

cleaned as (
    select
        lower(coin_id)  as coin_id,
        date as date,
        open_usd as open_usd,
        high_usd as high_usd,
        low_usd as low_usd,
        close_usd as close_usd,
        volume_usd as volume_usd,
        market_cap_usd as market_cap_usd,

        -- Intraday price range in dollars.
        -- Calculated here in staging so every downstream model gets it
        -- without repeating the formula.
        round(high_usd - low_usd, 6)                    as intraday_range_usd,

        -- Range as a percentage of the day's open.
        -- This is more comparable across coins than the raw dollar amount.
        -- A $2,000 BTC swing means something very different to a $0.002 swing
        -- on a penny coin. The percentage normalises that.
        -- nullif(open_usd, 0) prevents division by zero on any rows where
        -- the open price was somehow recorded as exactly zero.
        round(
            (high_usd - low_usd) / nullif(open_usd, 0) * 100,
            4
        )                                               as intraday_range_pct,

        extracted_at

    from source
    -- Defensive filter: even though extract.py removed these rows,
    -- good practice is to filter again in the warehouse.
    -- If someone manually edits the CSV and re-seeds, the model still holds.
    where close_usd > 0
      and high_usd >= low_usd
)

select * from cleaned