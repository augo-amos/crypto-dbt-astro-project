# Crypto dbt + Astro Project

A production-grade data pipeline for cryptocurrency market analysis, combining **dbt** for data transformation, **Python** for API extraction, and **Astro** for orchestration.

## Overview

This project fetches daily OHLCV (Open, High, Low, Close, Volume) price data and coin metadata from the **CoinGecko API**, transforms it using **dbt** with a carefully structured data warehouse architecture, and surfaces clean analytical datasets for dashboarding and backtesting.

### Key Features

- **Automated Extraction**: Python script with rate-limit handling and retry logic
- **Layered Transformation**: Staging → Intermediate → Mart architecture following dbt best practices
- **Advanced Analytics**: Rolling volatility, cumulative returns, and daily performance metrics
- **Data Quality**: dbt tests ensure integrity at every layer
- **Source Freshness Checks**: Automated validation that raw data hasn't staled
- **Scalable Architecture**: Easy to add new coins or extend metrics

## Data Architecture

```
Raw Data (CSV Seeds)
    ↓
Staging Models (Cleaning & Standardization)
    ↓
Intermediate Models (Business Logic)
    ↓
Mart Models (Analytical Datasets)
```

### Layer Breakdown

#### **Staging** (`models/staging/`)
- `stg_coins`: Cleaned coin metadata (one row per coin)
- `stg_prices`: Cleaned daily OHLCV prices with derived columns

*Purpose*: Normalize raw data types, casing, and simple calculations without joins or aggregations.

#### **Intermediate** (`models/intermediate/`)
- `int_daily_returns`: Day-over-day returns using window functions
  - `daily_return_pct`: Percentage change from previous close
  - `is_up_day`: Boolean for bullish/bearish days
  - `volume_change_pct`: Volume momentum

*Purpose*: Reusable business logic shared across multiple marts.

#### **Marts** (`models/marts/`)
Optimized for specific use cases:

- **`mart_coin_summary`**: One row per coin
  - Period performance metrics (total return, volatility, Sharpe components)
  - Best/worst day statistics
  - Trading days and volume insights

- **`mart_daily_returns`**: One row per coin per day
  - Full OHLCV + derived metrics
  - **Cumulative return** using geometric compounding (`EXP(SUM(LN(...)))`)
  - Time-series ready for charts and backtesting

- **`mart_price_volatility`**: Rolling volatility metrics
  - 7-day and 30-day rolling standard deviation
  - Daily volatility rank (how volatile was this coin relative to peers?)
  - Rolling average return

## Quick Start

### Prerequisites

- Python 3.9+
- Snowflake account
- dbt installed: `pip install dbt-snowflake`

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/augo-amos/crypto-dbt-astro-project.git
   cd crypto-dbt-astro-project
   ```

2. **Set up Python environment**
   ```bash
   cd crypto_pipeline
   python -m venv venv
   source venv/bin/activate  # On Windows: venv\Scripts\activate
   pip install -r requirements.txt
   ```

3. **Configure dbt profile**
   
   Create `~/.dbt/profiles.yml` with your Snowflake credentials:
   ```yaml
   crypto_dbt:
     target: dev
     outputs:
       dev:
         type: snowflake
         account: [your-account]
         user: [your-user]
         password: [your-password]
         role: [your-role]
         database: dbt_db
         schema: dbt_schema
         threads: 4
         client_session_keep_alive: False
   ```

4. **Set environment variables** (for Python extraction)
   ```bash
   # Create .env file in crypto_pipeline/
   # (Optional: API keys if using authenticated endpoints)
   ```

5. **Extract data**
   ```bash
   python extract.py
   ```
   This fetches 90 days of data for 10 major cryptocurrencies (Bitcoin, Ethereum, Solana, etc.).

6. **Load and transform**
   ```bash
   cd crypto_dbt
   dbt seed          # Load CSV seeds into warehouse
   dbt run           # Build all models
   dbt test          # Validate data quality
   ```

## Project Structure

```
crypto-dbt-astro-project/
├── crypto_pipeline/
│   ├── extract.py              # CoinGecko API client with retry logic
│   ├── requirements.txt         # Python dependencies
│   ├── .gitignore
│   └── crypto_dbt/
│       ├── dbt_project.yml      # dbt configuration
│       ├── models/
│       │   ├── sources.yml      # Source definitions & freshness checks
│       │   ├── staging/
│       │   │   ├── schema.yml
│       │   │   ├── stg_coins.sql
│       │   │   └── stg_prices.sql
│       │   ├── intermediate/
│       │   │   └── int_daily_returns.sql
│       │   └── marts/
│       │       ├── schema.yml
│       │       ├── mart_coin_summary.sql
│       │       ├── mart_daily_returns.sql
│       │       └── mart_price_volatility.sql
│       ├── seeds/
│       │   └── raw/
│       │       ├── coin_metadata.csv
│       │       └── historical_prices.csv
│       └── README.md
└── astro_dbt/                  # Astro orchestration (future)
```

## Key Design Decisions

### Window Functions for Efficiency
- `LAG()` and `FIRST_VALUE()`/`LAST_VALUE()` compute returns and price ranges without joins
- Partitioning by `coin_id` prevents data bleed across coins
- Frame specifications ensure correct aggregation semantics

### Geometric Mean for Cumulative Returns
```sql
EXP(SUM(LN(1 + daily_return_pct / 100))) - 1
```
This accounts for compounding: a 10% gain followed by 10% loss ≠ 0% total return (it's -1%).

### Defensive Filtering
- Models re-filter raw data (`close_usd > 0`, `high_usd >= low_usd`)
- Even though `extract.py` cleans, warehouse-level validation is a best practice

### Intermediate Layer for Reuse
`int_daily_returns` is used by **three marts**:
- Change the formula once → all three marts update automatically
- No duplicate code → no missed updates

## Data Quality

### dbt Tests
- **Uniqueness**: `coin_id` is unique in staging
- **Not Null**: Critical fields (`close_usd`, `date`, `coin_id`) are required
- **Referential Integrity**: Implicit via `{{ ref() }}` dependencies

### Freshness Checks
```bash
dbt source freshness
```
Warns if raw data hasn't been updated in 25 hours; errors at 49 hours.

## Sample Queries

**Top 5 performers over the period:**
```sql
select name, symbol, period_total_return_pct
from mart_coin_summary
order by period_total_return_pct desc nulls last
limit 5;
```

**Volatility vs return for each coin:**
```sql
select 
  name,
  avg_daily_return_pct,
  stddev_daily_return_pct,
  period_total_return_pct
from mart_coin_summary
order by stddev_daily_return_pct desc;
```

**Rolling 30-day volatility for Bitcoin:**
```sql
select date, rolling_30d_volatility, rolling_7d_volatility
from mart_price_volatility
where symbol = 'BTC'
order by date desc;
```

## Orchestration (Astro)

The `astro_dbt/` folder is reserved for Apache Airflow (via Astro) orchestration:
- Schedule daily data extraction
- Trigger dbt runs after seeds load
- Monitor data freshness
- Alert on test failures

*Documentation coming soon.*

## Development Workflow

### Adding a New Cryptocurrency

1. Add coin ID to `COINS` list in `extract.py`
2. Run `python extract.py` to fetch data
3. Run `dbt seed` to reload CSVs
4. All mart models will automatically include the new coin

### Adding a New Metric

1. Create intermediate model in `models/intermediate/` if it's reused
2. Or directly add calculation to relevant mart
3. Add schema.yml documentation + tests
4. Run `dbt run && dbt test`

### Running Specific Models

```bash
dbt run --models stg_prices     # Single model
dbt run --models +int_*          # All intermediates
dbt run --models staging.+       # Staging and downstream
```

## Resources

- [dbt Docs](https://docs.getdbt.com/)
- [CoinGecko API](https://www.coingecko.com/en/api/documentation)
- [Snowflake Window Functions](https://docs.snowflake.com/en/sql-reference/functions/window-functions)
- [Apache Astro](https://www.astronomer.io/docs/astro/)

## Language Composition

- **Python** (98.9%): Data extraction and pipeline orchestration
- **Dockerfile** (1.1%): Containerization for Astro

## Contributing

1. Create a feature branch from `codespace-refactored-space-fortnight-pjwjr7qgpwgphr9jw`
2. Make changes and test locally with `dbt run && dbt test`
3. Open a pull request with a clear description

## License

MIT

---

**Questions?** Check the docstrings in `extract.py` and inline comments in SQL models for detailed explanations of complex logic.
