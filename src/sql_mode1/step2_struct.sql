--
-- Module TermStore, mode1. Defines and isolates (in the tstore schema) data structure of the project.
-- Mode1 have no optimizations, but express a complete "functionality profile" of the project.
-- To the project's presentation, see https://github.com/ppKrauss/pgsql-term
-- To frontend, see also http://www.jsonrpc.org/specification
--
-- RUN FIRST step1_libDefs.sql
--
-- Copyright by ppkrauss@gmail.com 2016, MIT license.
--

DROP SCHEMA IF EXISTS tstore CASCADE;
CREATE EXTENSION IF NOT EXISTS fuzzystrmatch; -- for metaphone() and levenshtein()

CREATE SCHEMA tstore; -- modeling by Term-0 Requirements

CREATE TABLE tstore.ns(
  --
  -- Namespace
  --
  nscount smallserial NOT NULL,  -- only few namespaces (32 for int id).
  nsid  int PRIMARY KEY, -- automatic cache of tlib.nsmask(nscount), see trigger
  label varchar(20) NOT NULL,
  description varchar(255) NOT NULL,
  lang char(2) NOT NULL DEFAULT '  ', -- language of term, OR regconfig with language
  is_base boolean NOT NULL DEFAULT true,  -- flag to "base namespace" (not is part-of)
  fk_partOf int REFERENCES tstore.ns(nsid), -- when not null is part of another ns. Ex. a translation ns.
  kx_regconf regconfig, -- cache as lang definition (acronym use ''=lang, so regconf is 'simple'),
  jinfo JSONB,     -- any other metadata.  group_unique=true or false
  UNIQUE(nscount),
  UNIQUE(label),
  CHECK(tlib.lang2regconf(lang) IS NOT NULL), -- see tstore.input_ns()
  CHECK(nscount <= 32),  -- 32 when nsid is integer, 64 when bigint.
  CHECK(tlib.nsmask(array[nscount])=nsid) -- null or check
  -- see also input_ns() trigger.
);

CREATE TABLE tstore.term(
  --
  -- Term
  --
  id serial PRIMARY KEY,
  fk_ns int NOT NULL REFERENCES tstore.ns(nsid),
  term  varchar(500) NOT NULL, -- main term
  fk_canonic int REFERENCES tstore.term(id), -- NOT NULL WHEN synonym
  is_canonic boolean NOT NULL DEFAULT false,
  is_cult boolean, -- NULL, use only for case when was detected as "cult form" (valid dictionary), or not.
  is_suspect boolean NOT NULL DEFAULT false, -- to flag terms, with simultaneous addiction of suspect_cause at jinfo.
  created date DEFAULT now(),
  jinfo JSONB,     -- any other metadata.
  kx_metaphone varchar(400), -- idexed cache
  kx_tsvector tsvector,      -- cache for to_tsvector(lang, term)
  -- kx_lang char(2),   -- for use in dynamic qsquery, with some previous cached configs in json or array of configs. See ns.kx_regconf
  UNIQUE(fk_ns,term),
  CHECK( (is_canonic AND fk_canonic IS NULL) OR NOT(is_canonic) ),
  CHECK( fk_canonic != id )  -- self-reference not valid
  -- see also input_term() trigger.
);

CREATE TYPE tstore.tab AS  (
	--
	-- Used as internal standard for data interchange and data reporting.
	--
	id int,
	nsid int,
	term text,
	score int,
	is_canonic boolean,
	fk_canonic int,
	jetc JSONB  -- 	sc_func, synonyms_count, etc.
);

CREATE INDEX term_idx ON tstore.term(term); -- need after unique?
CREATE INDEX term_metaphone_idx ON tstore.term(kx_metaphone);

-- -- -- -- --
-- VIEWS for internal use or express modeling concepts:

CREATE VIEW tstore.term_canonic AS
   SELECT * from tstore.term  where is_canonic;

CREATE VIEW tstore.term_synonym AS
   SELECT * from tstore.term  where not(is_canonic);

CREATE VIEW tstore.term_synonym_full AS   -- add namespace?
   SELECT s.*, c.term as term_canonic
   FROM tstore.term_synonym s INNER JOIN tstore.term_canonic c
     ON  s.fk_canonic=c.id;

CREATE VIEW tstore.term_full AS   -- add namespace?
   SELECT s.*,
   	CASE WHEN is_canonic THEN -- mais de 50%
		s.term
	ELSE (SELECT term FROM tstore.term_canonic t WHERE t.id=s.fk_canonic)
	END as term_canonic
   FROM tstore.term s;

CREATE VIEW tstore.term_ns AS
   SELECT t.*, n.nscount, n.label, n.is_base, n.kx_regconf, n.jinfo as ns_jinfo
   FROM tstore.term t INNER JOIN tstore.ns n ON  t.fk_ns=n.nsid;


---  ---  ---  ---  ---  ---  ---  ---  ---
---  ---  ---  ---  ---  ---  ---  ---  ---
---  WRITE PROCEDURES                   ---
---  ---  ---  ---  ---  ---  ---  ---  ---


CREATE FUNCTION tstore.input_ns() RETURNS TRIGGER AS $f$
BEGIN
	NEW.nsid := tlib.nsmask(array[NEW.nscount]);
  	NEW.kx_regconf := tlib.lang2regconf(NEW.lang);
	-- optional to CHECK: IF NEW.kx_regconf IS NULL THEN RAISE
  	IF NEW.fk_partOf IS NOT NULL THEN
		NEW.is_base := false;
	END IF; -- else nothing to say, can be both.
	RETURN NEW;
END;
$f$ LANGUAGE PLpgSQL;
CREATE TRIGGER check_ns
    BEFORE INSERT OR UPDATE ON tstore.ns
    FOR EACH ROW EXECUTE PROCEDURE tstore.input_ns()
;


CREATE FUNCTION tstore.input_term() RETURNS TRIGGER AS $f$
	--
	-- Term normalization and cache initialization for the term table.
	-- OOPS, check tstore.ns.lang!
	--
DECLARE
  words text[];
BEGIN
	NEW.term := tlib.normalizeterm(NEW.term); 		-- or kx_normalizedterm
	NEW.kx_metaphone := tlib.multimetaphone(NEW.term);  	-- IMPORTANT DEFAULT 6, CHECK TLIB!
	NEW.kx_tsvector  := to_tsvector(
		(SELECT kx_regconf FROM tstore.ns WHERE nsid=NEW.fk_ns),  -- same as
		-- tlib.nsget_regconf(NEW.fk_ns) or tlib.lang2regconf(tlib.nsget_lang(NEW.fk_ns))
		NEW.term
	);
	-- CONSTRAINT HERE: IF NEW.is_suspect AND NEW.jinfo->>'suspect_cause' IS NULL THEN RAISE END IF;
	RETURN NEW;
END;
$f$ LANGUAGE PLpgSQL;

CREATE TRIGGER check_term
    BEFORE INSERT OR UPDATE ON tstore.term
    FOR EACH ROW EXECUTE PROCEDURE tstore.input_term()
;

CREATE FUNCTION tstore.upsert(
	--
	-- UPDATE OR INSERT for tstore.term write.  To update only p_name, use direct update.
	--
	p_name text,               -- 1. term
	p_ns int,                  -- 2. exact ns (not a mask?)
	p_info JSONB DEFAULT NULL, -- 3. all data in jsonb
	p_iscanonic boolean DEFAULT false,  -- 4.
	p_fkcanonic int DEFAULT NULL        -- 5.
) RETURNS integer AS $f$
DECLARE
  q_id  int;
  q_uniquegroup boolean;
BEGIN
	p_name := tlib.normalizeterm(p_name);

  SELECT COALESCE((jinfo->>'group_unique')::boolean, false) INTO q_uniquegroup
  FROM tstore.ns
  WHERE nsid=(SELECT CASE WHEN is_base THEN nsid ELSE fk_partOf END  FROM tstore.ns WHERE nsid=p_ns);

	SELECT id INTO q_id
  FROM tstore.term
  WHERE term=p_name AND CASE WHEN q_uniquegroup THEN (fk_ns&tlib.basemask(p_ns))::boolean ELSE fk_ns=p_ns END;

	IF p_name='' OR p_name IS NULL OR p_ns IS NULL THEN
		q_id:=NULL;
	ELSIF q_id IS NOT NULL THEN -- CONDITIONAL UPDATE  (deixar para update explicito o resto)
		IF p_info IS NOT NULL THEN
			UPDATE tstore.term
			SET  fk_ns=p_ns,  -- ?can change by upsert?
			     jinfo=p_info, fk_canonic=p_fkcanonic -- modified=now()
			WHERE id = q_id AND NOT(is_canonic);  -- salvaguarda para não remover canonicos
		END IF; -- else do nothing
	ELSE -- INSERT
		INSERT INTO tstore.term (fk_ns, term, jinfo, is_canonic,fk_canonic)
		VALUES (p_ns, p_name, p_info, p_iscanonic, p_fkcanonic)
		RETURNING id INTO q_id;
	END IF;
	RETURN q_id;
END;
$f$ LANGUAGE PLpgSQL;


CREATE FUNCTION tstore.ns_upsert(
	--
	-- Inserts when not exist, and sanitize label. Returns ID of the label.
	--
	text,            -- 1. label
	char(2),         -- 2. lang
	text,            -- 3. description
  boolean DEFAULT NULL,  -- 4. is_base
  JSONB DEFAULT NULL     -- 5. jinfo
) RETURNS integer AS $f$
DECLARE
	q_label text;
	r_id  smallint;
BEGIN
	q_label := tlib.normalizeterm($1); -- only sanitizes
	SELECT nsid INTO r_id FROM tstore.ns WHERE label=q_label;
	IF r_id IS NULL THEN
    IF $4 IS NULL THEN  -- is_base stay with create table default
		  INSERT INTO tstore.ns (label,description,lang,jinfo) VALUES (q_label,$3,$2,$5) RETURNING nsid INTO r_id;
    ELSE   -- use param
      INSERT INTO tstore.ns (label,description,lang,is_base,jinfo) VALUES (q_label,$3,$2,$4,$5) RETURNING nsid INTO r_id;
    END IF;
	END IF;
	RETURN r_id;
END;
$f$ LANGUAGE PLpgSQL;
