#!/usr/bin/env bash

set -e
sudo /etc/init.d/postgresql start
PGPASSWORD=x1 psql -U x1 -p 5432 -h localhost -w -d x1 -f scripts/create_schema.sql
