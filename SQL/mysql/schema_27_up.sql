-- Add cover column to albums for standalone album artwork (e.g., box set covers)
-- that may not be associated with any specific track
ALTER TABLE albums ADD COLUMN cover text;
