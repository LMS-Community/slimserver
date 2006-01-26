-- 
-- Force db recreation by upping the schema version

UPDATE metainformation SET version = 19;
