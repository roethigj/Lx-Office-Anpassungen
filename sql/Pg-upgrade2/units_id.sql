-- @tag: units_id
-- @description: ID-Spalte für Tabelle "units"
-- @depends: release_2_6_2
-- @charset: utf-8
ALTER TABLE units ADD COLUMN id serial;
ALTER TABLE units ADD CONSTRAINT units_id_unique UNIQUE (id);
