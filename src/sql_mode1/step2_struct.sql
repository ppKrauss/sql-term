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
  created date DEFAULT now(),
  UNIQUE(nscount),
  UNIQUE(label),
  CHECK(tlib.lang2regconf(lang) IS NOT NULL), -- see tstore.input_ns()
  CHECK(nscount <= 32),  -- 32 when nsid is integer, 64 when bigint.
  CHECK(tlib.nsmask(array[nscount])=nsid) -- null or check
  -- see also input_ns() trigger.
);

CREATE TABLE tstore.source(
  --
  -- Source of the canonic form.
  -- A creativeWork metadata, a list of sources or a data-package fields descriptor.
  --
  id serial PRIMARY KEY,
  name text, -- short label, use tlib.normalizeterm()
  jinfo JSONB,     -- JSON-LD with optional root "@tableSchema" https://www.w3.org/TR/tabular-metadata/
  --kx_islist boolean DEFAULT false,   -- when true have "list", an array of IDs of other sources
  --kx_ispackinfo boolean DEFAULT false, -- when true have "packinfo", see
  created date DEFAULT now(),
  CHECK( char_length(name)<40 AND name=lower(trim(name)) ),
  UNIQUE(name)
);

CREATE TABLE tstore.term(
  --
  -- Term
  --
  id serial PRIMARY KEY,
  fk_ns int NOT NULL REFERENCES tstore.ns(nsid),
  term  varchar(500) NOT NULL, -- main term
  fk_canonic int REFERENCES tstore.term(id), -- NOT NULL WHEN synonym
  fk_source int[], -- ELEMENT REFERENCES tstore.source(id), -- NOT NULL WHEN is_canonic
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
  CHECK( fk_canonic != id ),  -- self-reference not valid
  CHECK( NOT(is_canonic) OR fk_source IS NOT NULL )
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
 ---  ---  ---  ---  ASSERTS  ---  ---  ---

CREATE TABLE tstore._assert (
  id serial PRIMARY KEY NOT NULL,
  alabel varchar(180), -- assert-group label
  sql_select text NOT NULL,
  result text,
  UNIQUE (sql_select),
  CHECK ( trim(sql_select)>'' )
);


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

DROP FUNCTION IF EXISTS array_distinct(anyarray);
CREATE FUNCTION array_distinct(anyarray)
  RETURNS anyarray AS $f$
  SELECT array_agg(DISTINCT x) FROM unnest($1) t(x);
$f$ LANGUAGE SQL IMMUTABLE;


CREATE FUNCTION tstore.input_term() RETURNS TRIGGER AS $f$
	--
	-- Term normalization and cache initialization for the term table.
	-- OOPS, check tstore.ns.lang!
	--
DECLARE
  words text[];
  nchecked int;
BEGIN
	NEW.term := tlib.normalizeterm(NEW.term); 		-- or kx_normalizedterm
  IF EXISTS ( -- check homonyms in the namespace-group
    SELECT 1 FROM tstore.term
    WHERE (fk_ns&tlib.basemask(NEW.fk_ns))::boolean AND term=NEW.term AND fk_canonic!=NEW.fk_canonic
  ) THEN
    -- RAISE EXCEPTION 'trying to insert term % with canonic "%", characterizong homonyms.', NEW.term, NEW.fk_canonic;
    NEW.jinfo := CASE WHEN NEW.jinfo IS NULL THEN '{"test":"repetiu"}'::jsonb  ELSE NEW.jinfo || '{"test":"repetiu"}'::jsonb END;
    -- NEW.fk_canonic = xid;
  END IF;
  -- IF NEW.is_suspect AND NEW.jinfo->>'suspect_cause' IS NULL THEN
  --   RAISE EXCEPTION 'All is_suspect need jinfo-suspect_cause (be not null).';
  -- END IF;
  IF (NEW.fk_source IS NOT NULL) THEN -- check element references
    NEW.fk_source := array_distinct(NEW.fk_source);
    SELECT count(fid) INTO nchecked
    FROM UNNEST(NEW.fk_source) t(fid) INNER JOIN tstore.source s ON s.id=t.fid;
    IF nchecked != array_length(NEW.fk_source,1) THEN
      RAISE EXCEPTION 'array element of fk_source not in souce table.';
    END IF;
  END IF;
	NEW.kx_metaphone := tlib.multimetaphone(NEW.term);  	-- IMPORTANT DEFAULT 6, CHECK TLIB!
	NEW.kx_tsvector  := to_tsvector(
		(SELECT kx_regconf FROM tstore.ns WHERE nsid=NEW.fk_ns),  -- same as
		-- tlib.nsget_regconf(NEW.fk_ns) or tlib.lang2regconf(tlib.nsget_lang(NEW.fk_ns))
		NEW.term
	);
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
	p_iscanonic boolean DEFAULT false,  -- 4. is canonic
	p_fkcanonic int DEFAULT NULL,     	-- 5. link
	p_issuspect boolean DEFAULT false,  -- 6. is suspect, ops default proprio
	p_iscult boolean DEFAULT NULL, 		  -- 7. is cult, ops default proprio
  p_ref int DEFAULT NULL              -- 8. source ID
) RETURNS integer AS $f$
DECLARE
  q_id  int;
  q_uniquegroup boolean;
  q_refs  int[];
BEGIN
  p_name := tlib.normalizeterm(p_name);
  q_refs := CASE WHEN p_ref IS NULL THEN NULL ELSE array[p_ref] END;
  -- q_uniquegroup checker is dangerous into the trigger function. Preserve here.
	SELECT COALESCE((jinfo->>'group_unique')::boolean, false) INTO q_uniquegroup
		FROM tstore.ns
		WHERE nsid=(SELECT CASE WHEN is_base THEN nsid ELSE fk_partOf END  FROM tstore.ns WHERE nsid=p_ns);
	SELECT id INTO q_id
		FROM tstore.term
		WHERE
		 CASE WHEN q_uniquegroup THEN (fk_ns&tlib.basemask(p_ns))::boolean ELSE fk_ns=p_ns END
		 AND term=p_name;
	IF p_name='' OR p_name IS NULL OR p_ns IS NULL OR p_ns<1 THEN
		q_id:=NULL;
	ELSIF q_id IS NOT NULL THEN -- CONDITIONAL UPDATE  (deixar para update explicito o resto)
		IF q_id!=p_fkcanonic  THEN -- enforce coherence?  AND fk_ns=p_ns
			UPDATE tstore.term
			SET  --is_canonic=p_iscanonic,
           jinfo      = CASE WHEN p_info IS NULL THEN jinfo WHEN jinfo IS NULL THEN p_info ELSE jinfo||p_info END,
			     fk_canonic = CASE WHEN p_iscanonic THEN NULL ELSE p_fkcanonic END,
           fk_source   = array_distinct(q_refs || fk_source)
				-- is_suspect?
			WHERE id = q_id       AND NOT(is_canonic);  -- salvaguarda para não remover canonicos
			-- IF no_affected THEN q_id:= NULL;
		ELSE
			q_id:= NULL;
		END IF; -- else do nothing
	ELSE -- INSERT
		INSERT INTO tstore.term (fk_ns, term, jinfo, is_canonic, fk_canonic,is_suspect,is_cult, fk_source)
		VALUES (p_ns, p_name, p_info, p_iscanonic, p_fkcanonic, p_issuspect, p_iscult, q_refs)
		RETURNING id INTO q_id;
	END IF;
	RETURN q_id;
END;
$f$ LANGUAGE PLpgSQL;

CREATE FUNCTION tstore.upsert(
  text, int, JSONB, boolean, int, boolean, boolean,
  text  -- label no lugar de ID
) RETURNS integer AS $f$
  SELECT tstore.upsert($1,$2,$3,$4,$5,$6,$7, (SELECT id FROM tstore.source WHERE name=$8 LIMIT 1) );
$f$ LANGUAGE SQL;


CREATE FUNCTION tstore.source_add1(
  --
  -- Add or replace the source descriptor.
  -- Usual descriptores are in dce format, The Dublin Core Metadata Element Set.
  --
   author text,
   title text,
   url text
 ) RETURNS JSONB AS $f$
    SELECT jsonb_build_object(
        '@context', 'http://schema.org'
        ,'@type',   'Dataset'
        ,'author',  author
        ,'name',    title
        ,'url',     url
    );
$f$ LANGUAGE SQL;


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
