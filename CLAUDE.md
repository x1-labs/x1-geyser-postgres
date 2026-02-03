# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is `x1-geyser-postgres`, an X1 Geyser plugin that streams account data, transactions, slots, and block metadata to a PostgreSQL database. It implements the Geyser Plugin Interface for use with X1 validators.

## Build Commands

```bash
# Build
cargo build

# Run tests (requires PostgreSQL - see Database Setup below)
cargo test -- --nocapture

# Linting
cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- --deny=warnings
```

**Required Rust version**: 1.73.0 (see `ci/rust-version.sh`)

## Database Setup for Testing

Tests require a PostgreSQL 14 database. On Ubuntu:

```bash
# Install PostgreSQL
sudo apt-get install postgresql-14
sudo /etc/init.d/postgresql start

# Create user and database
sudo -u postgres psql --command "CREATE USER solana WITH SUPERUSER PASSWORD 'solana';"
sudo -u postgres createdb -O solana solana

# Initialize schema
PGPASSWORD=solana psql -U solana -p 5432 -h localhost -w -d solana -f scripts/create_schema.sql

# Clean up between test runs (to avoid duplicate key violations)
PGPASSWORD=solana psql -U solana -p 5432 -h localhost -w -d solana -f scripts/drop_schema.sql
```

## Architecture

### Core Components

**GeyserPluginPostgres** (`src/geyser_plugin_postgres.rs`):
- Main plugin entry point implementing `GeyserPlugin` trait
- Loads configuration from JSON file
- Creates selectors for filtering accounts/transactions
- Dispatches updates to PostgreSQL client

**ParallelPostgresClient** (`src/postgres_client.rs`):
- Multi-threaded connection pool using worker threads (default: 100 threads)
- Uses bounded channel (40960 max requests) to queue database operations
- Each worker maintains its own `SimplePostgresClient` with prepared statements
- Supports bulk inserts during startup for performance

**Selectors** (`src/accounts_selector.rs`, `src/transaction_selector.rs`):
- Filter which accounts/transactions to persist
- Support wildcard (`*`) for all, or specific pubkeys/owners

### Data Flow

1. Validator calls plugin hooks (`update_account`, `notify_transaction`, etc.)
2. Plugin filters using selectors, creates work items
3. Work items sent to channel, consumed by worker threads
4. Workers execute prepared statements against PostgreSQL

### Database Schema

Key tables (defined in `scripts/create_schema.sql`):
- `account`: Current account state (pubkey, owner, lamports, data, slot)
- `slot`: Slot metadata with status (processed/confirmed/rooted)
- `transaction`: Full transaction data with signatures and metadata
- `block`: Block metadata including rewards
- `account_audit`: Historical account data (optional, via trigger)
- `spl_token_owner_index` / `spl_token_mint_index`: Token secondary indexes

### Plugin Configuration

JSON config file with key options:
- `host`, `user`, `port` or `connection_str`: PostgreSQL connection
- `threads`: Worker thread count (default: 100)
- `batch_size`: Bulk insert batch size (default: 10)
- `accounts_selector`: Filter accounts by pubkey or owner
- `transaction_selector`: Filter transactions by mentioned accounts
- `panic_on_db_errors`: Abort validator on database errors
- `use_ssl`, `server_ca`, `client_cert`, `client_key`: SSL configuration

### Output Artifact

The build produces a dynamic library:
- Linux: `libx1_geyser_postgres.so`
- macOS: `libx1_geyser_postgres.dylib`

Validators load this via `--geyser-plugin-config <config.json>`.
