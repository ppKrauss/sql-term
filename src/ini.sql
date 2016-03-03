-- 
-- Module Term (Term0, Term1, Term2 demo models)
-- https://github.com/ppKrauss/pgsql-term
-- Copyright by ppkrauss@gmail.com 2016, MIT license.
--


DROP SCHEMA IF EXISTS term0 CASCADE; 
DROP SCHEMA IF EXISTS term1 CASCADE; 
DROP SCHEMA IF EXISTS term2 CASCADE; 
CREATE EXTENSION IF NOT EXISTS fuzzystrmatch; -- for metaphone() and levenshtein()


--
-- Term0 is the basic and simplest "term manager", with no tag-relation or term-hierarchy.
--

CREATE SCHEMA term0; -- modeling by Term-0 Requirements

CREATE TABLE term0.ns( -- namespace
  nsid smallserial PRIMARY KEY,  -- only few namespaces and language variants
  label varchar(20) NOT NULL,
  description varchar(255) NOT NULL,
  lang char(2) NOT NULL DEFAULT 'en', -- language of term, 
  fk_translationOf smallint REFERENCES term0.ns(nsid), -- when not null is a lang-translation of another ns
  jinfo JSONB,     -- any other metadata.
  UNIQUE(label)
);
INSERT INTO term0.ns(label,description) VALUES ('teste','teste');

CREATE TABLE term0.term(
  id serial PRIMARY KEY,
  fk_ns smallint NOT NULL REFERENCES term0.ns(nsid),
  fk_canonic int REFERENCES term0.term(id), -- NOT NULL WHEN synonym
  term  varchar(500) NOT NULL, -- main term
  jinfo JSONB,     -- any other metadata.
  kx_metaphone varchar(400), -- indexed by metaphone(term)
  kx_tsvector tsvector,      -- indexed by to_tsvector(lang, term)
  created date DEFAULT now(),
  UNIQUE(fk_ns,term)
);


CREATE FUNCTION term0.normalizename() RETURNS trigger AS $f$
-- 
-- Term normalization and cache initialization for the term table.  
--
DECLARE
  words text[];
BEGIN
	SELECT 	 array[string_agg(w,' '), string_agg(metaphone(w,6),' ')] INTO words
	FROM regexp_split_to_table(TRIM(LOWER(NEW.term)), E'[\\s;\\|]+') AS t(w);
	NEW.term :=         words[1]; -- or kx_normalizedterm
	NEW.kx_metaphone := words[2];
	NEW.kx_tsvector := to_tsvector('portuguese', words[1]);
	RETURN NEW;END;
$f$ LANGUAGE plpgsql;
CREATE TRIGGER check_term
    BEFORE INSERT OR UPDATE ON term0.term
    FOR EACH ROW EXECUTE PROCEDURE term0.normalizename()
;

-- -- -- -- --
-- --  LIB  --
-- -- -- -- --

CREATE FUNCTION term0.find(
	text,                      -- 1. query string (usual term or term-fragments)
	char DEFAULT '&', 	   -- 2. '&','|' or free or like-search ('%' or 'p' for prefix)
	int DEFAULT 100,           -- 3. LIMIT
        smallint DEFAULT 1,        -- 4. Namespace
	regconfig DEFAULT 'portuguese'::regconfig  -- 5. used in to_tsquery()	
) RETURNS varchar[] AS $f$
	SELECT CASE WHEN $2='e' THEN (  -- exact
			SELECT array_agg(term) 
			FROM term0.term 
			WHERE fk_ns=$4 AND term = LOWER(TRIM( regexp_replace($1, E'[\\s;\\|]+', ' ', 'g') ))
			LIMIT $3
		) WHEN $2='%' OR $2='p' OR $2='s' THEN (  -- 's'equence or 'p'refix
			SELECT array_agg(term) 
			FROM term0.term 
			WHERE fk_ns=$4 AND term LIKE (
				CASE WHEN $2='p' THEN '' ELSE '%' END ||  LOWER(TRIM( regexp_replace($1, E'[\\s;\\|]+', '%', 'g') ))  || '%'
			) LIMIT $3
		) ELSE (  -- pending, needs also "free tsquery" in $2 for '!' use and complex expressions
			SELECT array_agg(term) 
			FROM term0.term 
			WHERE fk_ns=$4 AND kx_tsvector @@ to_tsquery(
				$5,
				LOWER(TRIM( regexp_replace($1, E'[\\s;\\|]+', $2, 'g') ))
			) LIMIT $3
		) END
	;
$f$ LANGUAGE sql;


--
-- Term1 adds tag-relation to Term0.
--

CREATE SCHEMA term1; -- modeling by Term-1 Requirements

-- ... under construction ...

--
-- Term2 adds Hierarchy to Term1.
--

CREATE SCHEMA term2; -- modeling by Term-2 Requirements

-- ... under construction ...

