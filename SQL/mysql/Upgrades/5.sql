-- 
--

ALTER TABLE albums ADD COLUMN contributors varchar(255);

UPDATE metainformation SET version = 5;

COMMIT;
