import pandas as pd
import requests
import os
from datetime import datetime
import time


COINS = [
    "bitcoin", "ethereum", "tether", "binancecoin", "solana",
    "ripple", "usd-coin", "staked-ether", "cardano", "avalanche-2"
]

BASE_URL = "https://api.coingecko.com/api/v3"

# Output goes directly into dbt's seeds folder.
# dbt seed will scan this directory and load whatever it finds.

SEEDS_DIR = "crypto_dbt/seeds/raw"

os.makedirs(SEEDS_DIR, exist_ok=True)

def get_with_retry(url, params, retries=3):
    for attempt in range(retries):
        response = requests.get(url, params=params, timeout=15)
        if response.status_code == 429: # Too Many Requests
            wait = 60 * (attempt + 1)  # Exponential backoff
            print(f"Rate limit hit. Waiting {wait} seconds before retrying...")
            time.sleep(wait)
            continue
        response.raise_for_status() #This will raise an error for non-200 responses, which we want to retry on
        return response
    raise Exception(f"Failed after {retries}: {url}")

def fetch_coin_metadata():
    records = []
    for coin_id in COINS:
        print(f"Metadata {coin_id}")
        response = get_with_retry(
            url = f"{BASE_URL}/coins/{coin_id}",
            params = {
                "localization": "false",
                "tickers": "false",
                "market_data": "true",
                "community_data": "false",
                "developer_data": "false",
            }

        )
        data = response.json()

        records.append({
            "coin_id": data["id"],
            "symbol": data["symbol"].upper(),
            "name": data["name"],
            "market_cap_rank": data.get("market_cap_rank"),

            # Truncate description to 500 chars — dbt seeds have a column size limit
            # by default. We'll configure this in seeds.yml, but truncating here
            # keeps the CSV clean and predictable.
            
            "description":       (data["description"].get("en") or "")[:500],
            "genesis_date":      data.get("genesis_date"),
            "hashing_algorithm": data.get("hashing_algorithm"),
            "homepage":          (data["links"]["homepage"] or [""])[0],
            
            # extracted_at lets us track when this row was pulled.
            # Essential for debugging and for dbt source freshness checks.
            
            "extracted_at":      datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S"),
        })

        time.sleep(1.5)   # Respect free-tier rate limits
    
    df = pd.DataFrame(records)

    # dbt seed reads column names from the CSV header.
    # Lowercase column names here match our SQL model conventions.
    
    path = os.path.join(SEEDS_DIR, "coin_metadata.csv")
    df.to_csv(path, index=False)
    print(f"  Saved {len(df)} rows to {path}")
    return df


def fetch_historical_prices():
    """
    Fetch 90 days of daily OHLCV data per coin.
    
    We merge two endpoints:
      - /coins/{id}/ohlc        → open, high, low, close
      - /coins/{id}/market_chart → volume, market_cap
    
    Both are matched by date string. CoinGecko doesn't always return
    the exact same timestamp for the same calendar day across endpoints,
    so we match on the date portion, not the raw millisecond value.
    """
    all_records = []

    for coin_id in COINS:
        print(f"  Prices: {coin_id}")

        # OHLC endpoint
        ohlc_resp = get_with_retry(
            url    = f"{BASE_URL}/coins/{coin_id}/ohlc",
            params = {
                        "vs_currency": "usd", 
                        "days": "90"
                    }
        )
        ohlc_data = ohlc_resp.json()   # [[timestamp_ms, open, high, low, close], ...]
        time.sleep(1.5)

        # Market chart endpoint for volume + market cap
        chart_resp = get_with_retry(
            url    = f"{BASE_URL}/coins/{coin_id}/market_chart",
            params = {"vs_currency": "usd", "days": "90", "interval": "daily"}
        )
        chart_data = chart_resp.json()
        time.sleep(1.5)

        # Build date-keyed lookups for volume and market cap
        volume_by_date = {
            pd.to_datetime(ts, unit="ms").strftime("%Y-%m-%d"): vol
            for ts, vol in chart_data["total_volumes"]
        }
        mcap_by_date = {
            pd.to_datetime(ts, unit="ms").strftime("%Y-%m-%d"): mc
            for ts, mc in chart_data["market_caps"]
        }

        for row in ohlc_data:
            ts_ms, open_, high, low, close = row
            date_str = pd.to_datetime(ts_ms, unit="ms").strftime("%Y-%m-%d")

            all_records.append({
                "coin_id":        coin_id,
                "date":           date_str,
                "open_usd":       open_,
                "high_usd":       high,
                "low_usd":        low,
                "close_usd":      close,
                "volume_usd":     volume_by_date.get(date_str),
                "market_cap_usd": mcap_by_date.get(date_str),
                "extracted_at":   datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S"),
            })

    df = pd.DataFrame(all_records)

    # Drop rows with no close price — these are genuinely unusable
    # and would fail our dbt test `not_null` on close_usd.
    
    before = len(df)
    df = df.dropna(subset=["close_usd"])
    if before > len(df):
        print(f"  Dropped {before - len(df)} rows with null close_usd")

    # Also drop impossible OHLC rows
    df = df[df["high_usd"] >= df["low_usd"]]
    df = df[df["close_usd"] > 0]

    path = os.path.join(SEEDS_DIR, "historical_prices.csv")
    df.to_csv(path, index=False)
    print(f"  Saved {len(df)} rows → {path}")
    return df


if __name__ == "__main__":
    print("=== Extracting coin metadata ===")
    meta_df = fetch_coin_metadata()

    print("\n=== Extracting historical prices ===")
    prices_df = fetch_historical_prices()

    print(f"\nExtraction complete:")
    print(f"  Metadata rows : {len(meta_df)}")
    print(f"  Price rows    : {len(prices_df)}")
    print(f"\nCSV files written to crypto_dbt/seeds/raw/")
    print("Next step: cd crypto_dbt && dbt seed")
    