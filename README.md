# Solana Geyser Plugin for PostgreSQL

A Geyser plugin that streams account data, transactions, slots, and block metadata from a Solana validator to a PostgreSQL database.

## Quick Start

### 1. Build the Plugin

```bash
cargo build --release
```

This produces `target/release/libsolana_geyser_plugin_postgres.so` (Linux) or `.dylib` (macOS).

### 2. Set Up PostgreSQL

```bash
# Install PostgreSQL (Ubuntu)
sudo apt-get install postgresql-14
sudo systemctl start postgresql@14-main

# Create database and user
sudo -u postgres createdb solana
sudo -u postgres createuser solana

# Create schema
psql -U solana -d solana -f scripts/create_schema.sql
```

### 3. Configure the Plugin

Create a config file (e.g., `geyser-config.json`):

```json
{
    "libpath": "/path/to/libsolana_geyser_plugin_postgres.so",
    "host": "localhost",
    "user": "solana",
    "port": 5432,
    "threads": 20,
    "batch_size": 20,
    "panic_on_db_errors": true,
    "accounts_selector": {
        "accounts": ["*"]
    },
    "transaction_selector": {
        "mentions": ["*"]
    }
}
```

### 4. Run the Validator

```bash
solana-validator --geyser-plugin-config geyser-config.json ...
```

---

## Configuration Reference

### Connection Settings

| Field | Description |
|:------|:------------|
| `libpath` | Path to the plugin shared library |
| `host` | PostgreSQL server hostname |
| `user` | PostgreSQL username |
| `port` | PostgreSQL port |
| `connection_str` | Alternative: full connection string (see [Rust Postgres Config](https://docs.rs/postgres/0.19.2/postgres/config/struct.Config.html)) |
| `threads` | Number of worker threads (higher = better throughput) |
| `batch_size` | Bulk insert batch size |
| `panic_on_db_errors` | Panic validator on database errors for data consistency |
| `rpc_url` | RPC URL to fetch epoch schedule at startup (e.g., "http://localhost:8899") |
| `slots_per_epoch` | Fallback: slots per epoch if RPC unavailable (default: 432000) |
| `epoch_schedule_warmup` | Fallback: enable warmup for test validators (default: false) |

### SSL Connection

```json
{
    "use_ssl": true,
    "server_ca": "/path/to/server-ca.pem",
    "client_cert": "/path/to/client-cert.pem",
    "client_key": "/path/to/client-key.pem"
}
```

### Account Selection

Select all accounts:
```json
"accounts_selector": {
    "accounts": ["*"]
}
```

Select specific accounts by pubkey:
```json
"accounts_selector": {
    "accounts": ["pubkey-1", "pubkey-2"]
}
```

Select accounts by program owner:
```json
"accounts_selector": {
    "owners": ["program-pubkey-1", "program-pubkey-2"]
}
```

### Transaction Selection

If `transaction_selector` is missing, no transactions are stored.

Select all transactions:
```json
"transaction_selector": {
    "mentions": ["*"]
}
```

Select transactions mentioning specific accounts:
```json
"transaction_selector": {
    "mentions": ["pubkey-1", "pubkey-2"]
}
```

Select all vote transactions:
```json
"transaction_selector": {
    "mentions": ["all_votes"]
}
```

---

## Database Setup

### Install PostgreSQL

```bash
# Ubuntu
sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
sudo apt-get update
sudo apt-get -y install postgresql-14
```

### Configure Access Control

In `/etc/postgresql/14/main/pg_hba.conf`, add entries for your validator nodes:

```
host    all    all    10.138.0.0/24    trust
```

### Performance Tuning

In `/etc/postgresql/14/main/postgresql.conf`:

```
max_connections = 200
shared_buffers = 1GB
effective_io_concurrency = 1000
wal_level = minimal
fsync = off
synchronous_commit = off
full_page_writes = off
max_wal_senders = 0
```

See `scripts/postgresql.conf` for a complete reference configuration.

### Create Database and Schema

```bash
# Start PostgreSQL
sudo systemctl start postgresql@14-main

# Create database and user
sudo -u postgres createdb solana -p 5432
sudo -u postgres createuser -p 5432 solana

# Create schema
psql -U solana -p 5432 -h localhost -d solana -f scripts/create_schema.sql
```

### Drop Schema

```bash
psql -U solana -p 5432 -h localhost -d solana -f scripts/drop_schema.sql
```

---

## Database Schema

### Main Tables

| Table | Description |
|:------|:------------|
| `accounts` | Current account state |
| `slots` | Slot metadata and status |
| `transactions` | Transaction data with signatures and metadata |
| `blocks` | Block metadata including rewards |
| `account_audits` | Historical account data (optional) |

### Index Tables

| Table | Description |
|:------|:------------|
| `spl_token_owner_index` | SPL token owner to account mapping |
| `spl_token_mint_index` | SPL token mint to account mapping |

---

## Historical Account Data

To capture account history, set `store_account_historical_data` to `true` in your config.

The `accounts` table has a trigger that copies old records to `account_audits` on updates:

```sql
CREATE TRIGGER accounts_update_trigger AFTER UPDATE OR DELETE ON accounts
    FOR EACH ROW EXECUTE PROCEDURE audit_account_update();
```

To disable historical tracking:
```sql
DROP TRIGGER accounts_update_trigger ON accounts;
```

### Pruning Historical Data

Keep only the 1000 most recent records per account:

```sql
DELETE FROM account_audits a2 WHERE (pubkey, write_version) IN (
    SELECT pubkey, write_version FROM (
        SELECT pubkey, write_version,
            RANK() OVER (PARTITION BY pubkey ORDER BY write_version DESC) as rnk
        FROM account_audits
    ) ranked
    WHERE ranked.rnk > 1000
);
```

---

## Performance Considerations

- **Validator resources**: Use a powerful machine (e.g., GCP n2-standard-64) when storing all accounts
- **Database resources**: Use a dedicated database server (e.g., GCP n2-highmem-32)
- **Network**: Keep validator and database on the same local network to minimize latency
- **Thread count**: Higher `threads` value improves throughput
- **Batch size**: Larger `batch_size` reduces database round trips during startup

---

## Development

### Build

```bash
cargo build --release
```

### Run Tests

```bash
# Unit tests
cargo test --lib

# Integration tests (requires PostgreSQL)
cargo test
```

### Lint

```bash
cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- --deny=warnings
```
