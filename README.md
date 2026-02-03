# X1 Geyser Plugin for PostgreSQL

A Geyser plugin that streams account data, transactions, slots, and block metadata from an X1 validator to a PostgreSQL database.

## Quick Start

### 1. Build the Plugin

```bash
cargo build --release
```

This produces `target/release/libx1_geyser_postgres.so` (Linux) or `.dylib` (macOS).

### 2. Set Up PostgreSQL

```bash
# Install PostgreSQL (Ubuntu 24.04)
sudo apt install postgresql

# Create database and user
sudo -u postgres createuser -s x1
sudo -u postgres createdb -O x1 x1

# Set password for x1 user
sudo -u postgres psql -c "ALTER USER x1 WITH PASSWORD 'x1';"

# Create schema
PGPASSWORD=x1 psql -U x1 -h localhost -d x1 -f scripts/create_schema.sql
```

### 3. Configure the Plugin

Create a config file (e.g., `geyser-config.json`):

```json
{
    "libpath": "/path/to/libx1_geyser_postgres.so",
    "host": "localhost",
    "user": "x1",
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
x1-validator --geyser-plugin-config geyser-config.json ...
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
# Ubuntu 24.04
sudo apt install postgresql

# The service starts automatically after installation
sudo systemctl status postgresql
```

### Configure Access Control

In `/etc/postgresql/16/main/pg_hba.conf`, add entries for your validator nodes:

```
host    all    all    10.138.0.0/24    scram-sha-256
```

Then restart the service:

```bash
sudo systemctl restart postgresql
```

### Performance Tuning

In `/etc/postgresql/16/main/postgresql.conf`:

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

Then restart the service:

```bash
sudo systemctl restart postgresql
```

See `scripts/postgresql.conf` for a complete reference configuration.

### Create Database and Schema

```bash
# Create user and database
sudo -u postgres createuser -s x1
sudo -u postgres createdb -O x1 x1
sudo -u postgres psql -c "ALTER USER x1 WITH PASSWORD 'x1';"

# Create schema
PGPASSWORD=x1 psql -U x1 -h localhost -d x1 -f scripts/create_schema.sql
```

### Drop Schema

```bash
PGPASSWORD=x1 psql -U x1 -h localhost -d x1 -f scripts/drop_schema.sql
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
