/**
 * Migration script for Agave 2.2.x compatibility
 * Run this on existing databases to update the schema
 */

-- Extend slot status column to accommodate longer status names
ALTER TABLE slot ALTER COLUMN status TYPE VARCHAR(32);

-- Add new transaction error codes for Agave 2.2.x
ALTER TYPE "TransactionErrorCode" ADD VALUE IF NOT EXISTS 'ProgramCacheHitMaxLimit';
ALTER TYPE "TransactionErrorCode" ADD VALUE IF NOT EXISTS 'CommitCancelled';