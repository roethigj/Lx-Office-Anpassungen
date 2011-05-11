-- @tag: discountgroup
-- @description: Erweitert die Datenbank für Rabattgruppen
-- @depends: release_2_6_2
-- @charset: utf-8
ALTER TABLE business ADD COLUMN partsgroup_id integer;
ALTER TABLE business ALTER COLUMN partsgroup_id SET STORAGE PLAIN;
ALTER TABLE business ADD COLUMN s_date date;
ALTER TABLE business ALTER COLUMN s_date SET STORAGE PLAIN;
ALTER TABLE business ALTER COLUMN s_date SET DEFAULT '1900-01-01'::date;
ALTER TABLE business ADD COLUMN e_date date;
ALTER TABLE business ALTER COLUMN e_date SET STORAGE PLAIN;
ALTER TABLE business ALTER COLUMN e_date SET DEFAULT '9999-12-31'::date;
ALTER TABLE business ADD COLUMN follow_up text;
ALTER TABLE business ALTER COLUMN follow_up SET STORAGE EXTENDED;
INSERT INTO partsgroup (partsgroup) VALUES ('Artikel ohne Warengruppe');
UPDATE parts SET partsgroup_id = (SELECT DISTINCT id FROM partsgroup WHERE partsgroup LIKE 'Artikel ohne Warengruppe') WHERE partsgroup_id = '0';
ALTER TABLE customer ADD COLUMN business_id_new text;
ALTER TABLE customer ALTER COLUMN business_id_new SET STORAGE EXTENDED;
UPDATE customer AS c SET business_id_new=(SELECT b.description FROM business AS b WHERE b.id=c.business_id);
ALTER TABLE customer DROP COLUMN business_id;
ALTER TABLE customer RENAME COLUMN business_id_new TO business_id;
ALTER TABLE vendor ADD COLUMN business_id_new text;
ALTER TABLE vendor ALTER COLUMN business_id_new SET STORAGE EXTENDED;
UPDATE vendor AS v SET business_id_new=(SELECT b.description FROM business AS b WHERE b.id=v.business_id);
ALTER TABLE vendor DROP COLUMN business_id;
ALTER TABLE vendor RENAME COLUMN business_id_new TO business_id;
ALTER TABLE invoice ADD COLUMN tradediscount real;
ALTER TABLE invoice ALTER COLUMN tradediscount SET STORAGE PLAIN;
ALTER TABLE orderitems ADD COLUMN tradediscount real;
ALTER TABLE orderitems ALTER COLUMN tradediscount SET STORAGE PLAIN;
ALTER TABLE delivery_order_items ADD COLUMN tradediscount real;
ALTER TABLE delivery_order_items ALTER COLUMN tradediscount SET STORAGE PLAIN;
ALTER TABLE delivery_order_items ADD COLUMN pricegroup_id integer;
ALTER TABLE delivery_order_items ALTER COLUMN pricegroup_id SET STORAGE PLAIN;
CREATE or REPLACE FUNCTION Update_business() RETURNS integer AS 
'
DECLARE 
btype RECORD;
pgroup RECORD;
dummy integer;
BEGIN
FOR btype IN SELECT description,discount,customernumberinit,salesman FROM business LOOP
  FOR pgroup IN SELECT id FROM partsgroup LOOP
    INSERT INTO business (description,discount,customernumberinit,salesman,partsgroup_id)
    VALUES (btype.description,btype.discount,btype.customernumberinit,btype.salesman,pgroup.id);
  END LOOP;
END LOOP;
dummy := 1;
RETURN dummy;
END;
'
LANGUAGE plpgsql;
SELECT Update_business();
DELETE FROM business WHERE partsgroup_id IS NULL;
DELETE FROM business WHERE description IS NULL;
