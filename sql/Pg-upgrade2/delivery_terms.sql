-- @tag: delivery_terms
-- @description: Neue Tabelle f&uuml;r Lieferbedingungen, Anpassung customer und vendor
-- @depends: release_2_6_2
CREATE TABLE delivery_terms
(
  id integer NOT NULL DEFAULT nextval(('id'::text)::regclass),
  description text,
  description_long text,
  itime timestamp without time zone DEFAULT now(),
  mtime timestamp without time zone,
  CONSTRAINT delivery_terms_pkey PRIMARY KEY (id)
)
WITH (
  OIDS=TRUE
);
CREATE TABLE translation_delivery_terms
(
  delivery_terms_id integer NOT NULL,
  language_id integer NOT NULL,
  description_long text,
  id serial NOT NULL,
  CONSTRAINT translation_delivery_terms_pkey PRIMARY KEY (id),
  CONSTRAINT translation_delivery_terms_language_id_fkey FOREIGN KEY (language_id)
      REFERENCES "language" (id) MATCH SIMPLE
      ON UPDATE NO ACTION ON DELETE NO ACTION,
  CONSTRAINT translation_delivery_terms_delivery_terms_id_fkey FOREIGN KEY (delivery_terms_id)
      REFERENCES delivery_terms (id) MATCH SIMPLE
      ON UPDATE NO ACTION ON DELETE NO ACTION
)
WITH (
  OIDS=TRUE
);
ALTER TABLE customer add column delivery_terms_id integer;
ALTER TABLE vendor add column delivery_terms_id integer;
ALTER TABLE oe add column delivery_terms_id integer;
ALTER TABLE ar add column delivery_terms_id integer;
