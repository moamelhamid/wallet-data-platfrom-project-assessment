-- ============================================================
-- 01_create_database.sql
-- Creates the operational database.
--
-- NOTE: when using the provided docker-compose.yml this database
-- is created automatically (POSTGRES_DB=wallet_oltp). This script
-- exists for native / manual PostgreSQL installations.
--
-- Run against the default "postgres" database:
--   psql -U postgres -f oltp/01_create_database.sql
-- ============================================================

CREATE DATABASE wallet_oltp
    WITH ENCODING 'UTF8'
    TEMPLATE template0;

COMMENT ON DATABASE wallet_oltp IS
    'Operational database for the digital wallet / card issuing platform';
