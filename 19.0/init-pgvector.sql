-- Initialize pgvector extension for Odoo 19.0 AI features
-- This script runs automatically when the PostgreSQL container starts

-- Create the vector extension
CREATE EXTENSION IF NOT EXISTS vector;

-- Grant usage to odoo user
GRANT USAGE ON SCHEMA public TO odoo;
GRANT CREATE ON SCHEMA public TO odoo;

-- Log successful initialization
DO $$
BEGIN
    RAISE NOTICE 'pgvector extension initialized successfully for Odoo AI features';
END $$;
