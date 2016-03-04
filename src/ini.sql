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

CREATE INDEX term_idx ON term0.term(term);
CREATE INDEX term_metaphone_idx ON term0.term(kx_metaphone);


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

-- PRIVATE --
CREATE FUNCTION term0.multimetaphone(text,int DEFAULT 6,varchar DEFAULT ' ') 
RETURNS text AS $f$
	SELECT 	 string_agg(metaphone(w,$2),$3) 
	FROM regexp_split_to_table($1, E'[\\s;\\|]+') AS t(w);
$f$ LANGUAGE sql;


-- PUBLIC --


CREATE FUNCTION term0.search(
--
-- Search terms by a query string. 
--
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


CREATE FUNCTION term0.search_metaphone(
--
-- Same as term0.search() but using metaphone.
--
	text,                      -- 1. query string (usual term or term-fragments)
	char DEFAULT '&', 	   -- 2. '=', '&','|' or free or like-search ('%' or 'p' for prefix)
	int DEFAULT 100,           -- 3. LIMIT
        smallint DEFAULT 1,        -- 4. Namespace
	int DEFAULT 6              -- 5. metaphone-length	
) RETURNS varchar[] AS $f$
	SELECT CASE WHEN $2='e' or $2='=' THEN (  -- exact
			SELECT array_agg(term) 
			FROM term0.term 
			WHERE fk_ns=$4 AND kx_metaphone = term0.multimetaphone($1)
			LIMIT $3
		) WHEN $2='%' OR $2='p' OR $2='s' THEN (  -- 's'equence or 'p'refix
			SELECT array_agg(term) 
			FROM term0.term 
			WHERE fk_ns=$4 AND kx_metaphone LIKE (
				CASE WHEN $2='p' THEN '' ELSE '%' END || term0.multimetaphone($1,$5,'%') || '%'
			) LIMIT $3
		) ELSE (  -- pending, needs also "free tsquery" in $2 for '!' use and complex expressions
			SELECT array_agg(term) 
			FROM term0.term 
			WHERE fk_ns=$4 AND to_tsvector('simple',kx_metaphone) @@ to_tsquery(
				'simple',
				term0.multimetaphone($1,$5,$2)
			) LIMIT $3
		) END;
$f$ LANGUAGE sql;


CREATE FUNCTION term0.find(
--
-- Find a term, or "nearest term", by an heuristic of search strategies. 
--
	text,                      -- 1. query string (usual term or term-fragments)
	int DEFAULT 100,           -- 2. LIMIT
        smallint DEFAULT 1,        -- 3. Namespace
	int DEFAULT 6              -- 4. metaphone-length	
-- FALTA tipo de search! 
) RETURNS varchar[] AS $f$
DECLARE
  items text[];
BEGIN
	items := term0.search($1,'=',$2,$3);
	IF array_length(items,1)=1 THEN
		RETURN items;
	END IF;
	items := term0.search($1,'&',$2,$3);
	IF array_length(items,1)>0 THEN
		RETURN items;
	END IF;
	items := term0.search($1,'p',$2,$3);
	IF array_length(items,1)>0 THEN
		RETURN items;
	END IF;
	items := term0.search_metaphone($1,'=',$2,$3,$4);
	IF array_length(items,1)>0 THEN
		RETURN items;
	END IF;
	items := term0.search_metaphone($1,'&',$2,$3,$4);
	IF array_length(items,1)>0 THEN
		RETURN items;
	END IF;
	items := term0.search_metaphone($1,'p',$2,$3,$4);
	return items;
END;
$f$ LANGUAGE plpgsql;


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

