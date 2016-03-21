-- 
-- Module Term, version-1. Term1 adds JSON interface, score metric and tag-relation to Term0.
-- No optimizations, only functionality profile.
-- See https://github.com/ppKrauss/pgsql-term
-- See also http://www.jsonrpc.org/specification
--
-- RUN FIRST term_lib.sql
--
-- Copyright by ppkrauss@gmail.com 2016, MIT license.
--

DROP SCHEMA IF EXISTS term1 CASCADE; 
CREATE EXTENSION IF NOT EXISTS fuzzystrmatch; -- for metaphone() and levenshtein()

CREATE SCHEMA term1; -- modeling by Term-0 Requirements

CREATE TABLE term1.ns(
  --
  -- Namespace
  --
  nscount smallserial NOT NULL,  -- only few namespaces (32 for int id). 
  nsid  int PRIMARY KEY, -- automatic cache of term_lib.nsmask(nscount), see trigger
  label varchar(20) NOT NULL,
  description varchar(255) NOT NULL,
  lang char(2) NOT NULL DEFAULT '  ', -- language of term, OR regconfig with language
  is_base boolean NOT NULL DEFAULT true,  -- flag to "base namespace" (not is part-of)
  fk_partOf int REFERENCES term1.ns(nsid), -- when not null is part of another ns. Ex. a translation ns.
  kx_regconf regconfig, -- cache as lang definition (acronym use ''=lang, so regconf is 'simple'),
  jinfo JSONB,     -- any other metadata.
  UNIQUE(nscount),
  UNIQUE(label),
  CHECK(term_lib.lang2regconf(lang) IS NOT NULL), -- see term1.input_ns()
  CHECK(nscount <= 32),  -- 32 when nsid is integer, 64 when bigint.
  CHECK(term_lib.nsmask(array[nscount])=nsid) -- null or check
  -- see also input_ns() trigger.
);

CREATE TABLE term1.term(
  --
  -- Term
  --
  id serial PRIMARY KEY,
  fk_ns int NOT NULL REFERENCES term1.ns(nsid),
  term  varchar(500) NOT NULL, -- main term
  fk_canonic int REFERENCES term1.term(id), -- NOT NULL WHEN synonym
  is_canonic boolean NOT NULL DEFAULT false,
  is_cult boolean, -- NULL, use only for case when was detected as "cult form" (valid dictionary), or not.
  is_suspect boolean NOT NULL DEFAULT false, -- to flag terms, with simultaneous addiction of suspect_cause at jinfo.
  created date DEFAULT now(),
  jinfo JSONB,     -- any other metadata.
  kx_metaphone varchar(400), -- idexed cache
  kx_tsvector tsvector,      -- cache for to_tsvector(lang, term)
  -- kx_lang char(2),   -- for use in dynamic qsquery, with some previous cached configs in json or array of configs. See ns.kx_regconf 
  UNIQUE(fk_ns,term),
  CHECK( (is_canonic AND fk_canonic IS NULL) OR NOT(is_canonic) )
  -- see also input_term() trigger.
);

CREATE TYPE term1.tab AS  (
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

CREATE INDEX term_idx ON term1.term(term); -- need after unique?
CREATE INDEX term_metaphone_idx ON term1.term(kx_metaphone);

-- -- -- -- --
-- VIEWS for internal use or express modeling concepts:

CREATE VIEW term1.term_canonic AS   
   SELECT * from term1.term  where is_canonic;

CREATE VIEW term1.term_synonym AS   
   SELECT * from term1.term  where not(is_canonic);

CREATE VIEW term1.term_synonym_full AS   -- add namespace?
   SELECT s.*, c.term as term_canonic 
   FROM term1.term_synonym s INNER JOIN term1.term_canonic c
     ON  s.fk_canonic=c.id;

CREATE VIEW term1.term_full AS   -- add namespace?
   SELECT s.*, 
   	CASE WHEN is_canonic THEN -- mais de 50%
		s.term 
	ELSE (SELECT term FROM term1.term_canonic t WHERE t.id=s.fk_canonic) 
	END as term_canonic
   FROM term1.term s;

CREATE VIEW term1.term_ns AS   
   SELECT t.*, n.nscount, n.label, n.is_base, n.kx_regconf, n.jinfo as ns_jinfo
   FROM term1.term t INNER JOIN term1.ns n ON  t.fk_ns=n.nsid;

---  ---  ---  ---  ---  
---  ---  ---  ---  --- 
--- TERM1 PUBLIC LIB 
---  ---  ---  ---  ---

-- -- -- -- -- -- -- -- --
-- namespace wrappers:

CREATE FUNCTION term1.basemask(
	--
	-- Generates a nsmask of all namespaces of a base-namespace. 
	--	
	text -- label of the base-namespace.
) RETURNS int AS $f$
SELECT sum(nsid)::int 
FROM (
	WITH basens as (
		SELECT * FROM term1.ns WHERE label=lower($1)
	) SELECT nsid, 1 as x FROM basens WHERE is_base
	  UNION
	  SELECT fk_partOf, 2 FROM basens  WHERE NOT(is_base)
	  UNION 
	  SELECT n.nsid, 3 FROM term1.ns n, basens b 
	  WHERE (b.is_base AND n.fk_partOf=b.nsid) OR (NOT(b.is_base) AND n.fk_partOf=b.fk_partOf)
) t;
$f$ LANGUAGE SQL IMMUTABLE;


CREATE FUNCTION term1.nsget_lang_aux(int,boolean DEFAULT false) RETURNS char(2) AS $f$
	-- 
	-- Namespace language by its nscount (or nsid when $2 false), used by proxy term_lib.nsget_lang().
	--
	SELECT lang FROM term1.ns WHERE CASE WHEN $2 THEN nscount=$1::smallint ELSE nsid=$1 END;
 	-- NULL is error, '' is a valid "no language"
$f$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION term1.nsget_nsid(text) RETURNS int AS $f$ SELECT nsid FROM term1.ns WHERE label=$1; $f$ LANGUAGE SQL IMMUTABLE;
CREATE FUNCTION term1.nsget_nsid(int) RETURNS int AS $f$ SELECT nsid FROM term1.ns WHERE nscount=$1::smallint; $f$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION term1.nsget_conf(int,boolean DEFAULT true) RETURNS regconfig AS $f$
	-- 
	-- Namespace language by its nscount (or nsid when $2 false)
	--
	SELECT kx_regconf FROM term1.ns WHERE CASE WHEN $2 THEN nscount=$1::smallint ELSE nsid=$1 END;
$f$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION term1.nsget_conf(text) RETURNS regconfig AS $f$
	-- 
	-- Namespace language by its label
	--
	SELECT kx_regconf FROM term1.ns WHERE label=$1;
$f$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION term1.set_regconf(anyelement,text) RETURNS regconfig AS $f$  --revisar usabilidade do anyelement
	SELECT  COALESCE( term1.nsget_conf($1), term_lib.lang2regconf($2) );
$f$ LANGUAGE SQL IMMUTABLE;

-- -- -- 

CREATE FUNCTION term1.nsget_nsopt2int(JSONB) RETURNS int AS $f$
	--
	-- Parses the namespace-setter optional parameters. 'ns', 'ns_mask', 'ns_basemask', 'ns_label', 'ns_count'
	--
	DECLARE
		nsuse boolean DEFAULT false;
		nsval int;
	BEGIN
	IF $1->'ns' IS NOT NULL THEN  -- optimizing and friendling
		nsval:= CASE jsonb_typeof($1->'ns')
				WHEN 'number' THEN ($1->>'ns')::int
				WHEN 'string' THEN term1.nsget_nsid(($1->>'ns')::text)
				ELSE NULL::int
			END;
		IF nsval IS NOT NULL THEN
			nsuse := true;
		END IF;
	END IF;
	RETURN CASE
		WHEN nsuse THEN nsval
		WHEN $1->'ns_mask' IS NOT NULL THEN ($1->>'ns_mask')::int -- same effect as 'ns'
		WHEN $1->'ns_basemask' IS NOT NULL THEN term1.basemask($1->>'ns_basemask')
		WHEN $1->'ns_label' IS NOT NULL THEN term1.nsget_nsid(($1->>'ns_label')::text)
		WHEN $1->'ns_count' IS NOT NULL THEN term1.nsget_nsid(($1->>'ns_count')::int)
		ELSE NULL 
	       END;
	END;
$f$ LANGUAGE PLpgSQL IMMUTABLE;


CREATE FUNCTION term1.search(
	-- Wrap for JSONB and outputs as RPC. Se #SQL-TEMPLATE of term1.N2C().
	-- SELECT term1.search('{"op":"%","qs":"embrapa","ns":"wayta-code","lim":5,"otype":"a"}'::jsonb);
	JSONB  -- see all valid params
) RETURNS JSONB AS $f$
DECLARE
	p JSONB;
	r JSONB;
	p_id text;
BEGIN
	p  :=  term_lib.jparams(
		$1,
		'{"lim":null,"osort":true,"otype":"l","qs_is_normalized":true}'::jsonb
	);
	IF p->>'otype'='l' THEN 
		-- FALTA revisar convenção, se for o caso refazer estrutura de t.*, com atributo dado pela score-function 
		SELECT  jsonb_agg(to_jsonb(t)) INTO r
		FROM term1.search_tab(p) t;
	ELSE
		SELECT jsonb_build_object(
			'items',CASE p->>'otype'
				WHEN 'o' THEN 	jsonb_object( array_agg(t.term), array_agg(t.score)::text[] ) -- revisar como usar int[]
				WHEN 'a' THEN 	jsonb_agg(to_jsonb(t.term))
				ELSE 		jsonb_agg(to_jsonb(t))
			END,
			'count', count(*),
			'sc_func',max(t.sc_type)
			)  INTO r
		FROM term1.search_tab(p) t;
	END IF;
	RETURN 	 term_lib.jrpc_ret(r,($1->>'id')::text);
END;
$f$ LANGUAGE PLpgSQL IMMUTABLE;




-- -- -- -- -- -- -- 
-- TERM1 TERM-RESOLVERS:

CREATE FUNCTION term1.N2C_tab(
	-- 
	-- Returns de canonic term from a valid term of a namespace.
	-- Exs. SELECT *  FROM term1.N2C_tab(' - USP - ','wayta-pt'::text,false); 
	--      SELECT term1.N2C_tab('puc-mg',term1.nsget_nsid('wayta-code'),true);
	--
	text,   		-- 1. valid term
	int,     		-- 2. namespace MASK, ex. by term1.basemask().
	boolean DEFAULT true  	-- 3. exact (true) or apply normalization (false)
) RETURNS SETOF term1.tab  AS $f$
	SELECT id, fk_ns as nsid, term_canonic::text, 100::int, is_canonic, fk_canonic, '{"sc_func":"exact"}'::jsonb
	FROM term1.term_full 
	WHERE (fk_ns&$2)::boolean  AND  CASE WHEN $3 THEN term=$1 ELSE term=term_lib.normalizeterm($1) END 
$f$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION term1.N2C_tab(text,text,boolean DEFAULT true) RETURNS SETOF term1.tab  AS $f$
	-- overloading, wrap for N2C_tab() and   basemask().
	SELECT term1.N2C_tab($1, term1.basemask($2), $3);
$f$ LANGUAGE SQL IMMUTABLE;


CREATE FUNCTION term1.N2C(
	-- Wrap for JSONB and outputs as RPC
	JSONB  -- see all valid params
) RETURNS JSONB AS $f$
DECLARE
	p JSONB;
	r JSONB;
	p_id text;
	n int;
BEGIN
	p  :=  term_lib.jparams(
		$1,
		'{"lim":null,"osort":true,"otype":"l","qs_is_normalized":true}'::jsonb
	);
	SELECT jsonb_build_object(
		'items',CASE p->>'otype'
			WHEN 'o' THEN 	jsonb_object( array_agg(t.term), array_agg(t.score)::text[] ) -- revisar se pode usar int[]
			WHEN 'a' THEN 	jsonb_agg(to_jsonb(t.term))
			ELSE 		jsonb_agg(to_jsonb(t))
		END,
		'count', count(*)
		)  INTO r
	FROM term1.N2c_tab(
		p->>'qs', term1.nsget_nsopt2int(p), (p->>'qs_is_normalized')::boolean
	) t;
	-- 'sucess': FOUND
	-- GET DIAGNOSTICS n = ROW_COUNT;
	RETURN 	term_lib.jrpc_ret(r, ($1->>'id')::text );
END;
$f$ LANGUAGE PLpgSQL IMMUTABLE;


-- -- --
-- N2Ns:

CREATE FUNCTION term1.N2Ns_tab(
	-- 
	-- Returns canonic and all the synonyms of a valid term (of a namespace).
	-- Ex. SELECT * FROM term1.N2Ns_tab(' - puc-mg - ',4,false);  -- 
	--
	text,            	-- 1. valid term
	int DEFAULT 1,     	-- 2. namespace MASK
	boolean DEFAULT true,	-- 3. exact (true) or apply normalization (false)
	boolean DEFAULT true	-- 4. (non-used, enforcing sort) to sort by ns, term
) RETURNS SETOF term1.tab AS $f$
   -- TO DO: optimize (see explain) and simplify using term1.term_full 
   SELECT t.id, t.fk_ns as nsid, t.term, 100::int, is_canonic, fk_canonic, '{"sc_func":"exact"}'::jsonb
   FROM term1.term t  INNER JOIN   (
	SELECT CASE WHEN is_canonic THEN -- caso comum, mais de 60% sao canonicos
			s.id 
		ELSE (SELECT id FROM term1.term_canonic t WHERE t.id=s.fk_canonic) -- caso nao-canonico
		END as canonic_id
	   FROM term1.term s
	   WHERE (fk_ns&$2)::boolean  AND  CASE WHEN $3 THEN term=$1 ELSE term=term_lib.normalizeterm($1) END
       ) c
       ON t.id=c.canonic_id OR fk_canonic=c.canonic_id
   ORDER BY t.fk_ns, t.term;
$f$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION term1.N2Ns_tab(text,text,boolean DEFAULT true) RETURNS SETOF term1.tab AS $f$
	-- Wrap for N2Ns_tab() and nsget_nsid().
	SELECT term1.N2Ns_tab($1, term1.nsget_nsid($2), $3);  -- old basemask(), preffer restrictive
$f$ LANGUAGE SQL IMMUTABLE;


CREATE FUNCTION term1.N2Ns(
	-- Wrap for JSONB and outputs as RPC. Se #SQL-TEMPLATE of term1.N2C().
	JSONB  -- see all valid params
) RETURNS JSONB AS $f$
DECLARE
	p JSONB;
	r JSONB;
	p_id text;
BEGIN
-- FALTA num itens
	p  :=  term_lib.jparams(
		$1,
		'{"lim":null,"osort":true,"otype":"l","qs_is_normalized":true}'::jsonb
	);
	p_id := ($1->>'id')::text; -- from original, webservice caller-ID
	SELECT CASE p->>'otype'
		WHEN 'o' THEN 	term_lib.jrpc_ret( array_agg(t.term), array_agg(t.score)::text[], p_id ) -- revisar se pode usar int[]
		WHEN 'a' THEN 	term_lib.jrpc_ret( jsonb_agg(to_jsonb(t.term)), p_id )
		ELSE 		term_lib.jrpc_ret( jsonb_agg(to_jsonb(t)), p_id )
		END
	INTO r
	FROM term1.N2Ns_tab(
		p->>'qs', term1.nsget_nsopt2int(p), (p->>'qs_is_normalized')::boolean
	) t;

	RETURN 	 r;
END;
$f$ LANGUAGE PLpgSQL IMMUTABLE;


-- -- -- -- -- -- -- --
-- TERM-SEARCH ENGINES:

CREATE or replace FUNCTION term1.search_tab(
	--
	--  Executes all search forms, by similar terms, and all output modes provided for the system.
	--  Debug with 'search-json'
	--  Namespace: use scalar for ready mask, or array of nscount for build mask. 
	--  @DEFAULT-PARAMS "op": "=", "lim": 5, "scfunc": "dft", "metaphone": false, "sc_maxd": 100, "metaphone_len": 6, ...
	--
	JSONB -- 1. all input parameters. 
) RETURNS SETOF term1.tab AS $f$ 
      
DECLARE
	p JSONB;
	p_scfunc text; 	-- Score function label
	p_qs text;
	p_nsmask int;
	p_maxd int;    	-- Param max_d in levenshtein_less_equal(a,b,max_d). Ex. average input lenght
	p_lim bigint;
	p_mlen int;
	p_conf regconfig;
	jetc jsonb;
BEGIN
	p := jsonb_build_object( -- all default values
		'op','=', 'lim',5, 'etc',1, 'scfunc','dft', 'sc_maxd',100, 'metaphone',false, 'metaphone_len',6, 
		'qs_lang','pt', 'nsmask',255, 
		'debug',null 
	) || CASE WHEN $1->'params' IS NOT NULL THEN $1->'params' ELSE $1 END;
	IF p->>'debug'='search-json' THEN 
		RAISE EXCEPTION 'debug search-json, params=%', p;
	END IF;
	p_qs := term_lib.normalizeterm($1->>'qs');
	IF p_qs IS NULL OR char_length(p_qs)<2 THEN 
		RETURN QUERY SELECT -10 as id, 'NULL querystring, input jsonb need params/qs', NULL;
	END IF;
	p_nsmask:= term1.nsget_nsopt2int(p);
	p_scfunc := p->>'sc_func';
	jetc   :=   p->'sc_func';   -- || other
	p_maxd :=   p->>'sc_maxd';  -- ::int
	p_lim  :=   p->>'lim';
	IF p->>'metaphone' THEN
		p_mlen := (p->>'metaphone_len')::int;
		CASE p->>'op'
		WHEN 'e','=' THEN  		-- exact
			RETURN QUERY SELECT t.id, t.fk_ns, t.term::text, term_lib.score(p_qs, t.term,p_scfunc, p_maxd), t.is_canonic, t.fk_canonic, jetc
			FROM term1.term t
			WHERE (t.fk_ns&p_nsmask)::boolean AND t.kx_metaphone = term_lib.multimetaphone(p_qs,p_mlen,' ')
			ORDER BY 4 DESC, 3
			LIMIT p_lim;
		WHEN '%','p','s' THEN 	 	-- s'equence OR p'refix
			RETURN QUERY SELECT t.id, t.fk_ns, t.term::text, term_lib.score(p_qs, t.term,p_scfunc, p_maxd), t.is_canonic, t.fk_canonic, jetc
			FROM term1.term t
			WHERE (t.fk_ns&p_nsmask)::boolean AND t.kx_metaphone LIKE (
				CASE WHEN p->>'op'='p' THEN '' ELSE '%' END || term_lib.multimetaphone(p_qs,p_mlen,'%') || '%'
			) 
			ORDER BY 4 DESC, 3			
			LIMIT p_lim;
		ELSE  				-- pending, needs also "free tsquery" in $2 for '!' use and complex expressions
			RETURN QUERY SELECT t.id, t.fk_ns, t.term::text, term_lib.score(p_qs, t.term,p_scfunc, p_maxd), t.is_canonic, t.fk_canonic, jetc
			FROM term1.term t
			WHERE (t.fk_ns&p_nsmask)::boolean AND to_tsvector('simple',t.kx_metaphone) @@ to_tsquery(
				'simple',
				term_lib.multimetaphone(p_qs,p_mlen,p->>'op'::text)
			) 
			ORDER BY 4 DESC, 3
			LIMIT p_lim;
		END CASE;

	ELSE CASE p->>'op'    			-- DIRECT TERMS:
 
		WHEN 'e', '=' THEN  		-- exact
			RETURN QUERY SELECT t.id, t.fk_ns, t.term::text, term_lib.score(p_qs, t.term,p_scfunc, p_maxd), t.is_canonic, t.fk_canonic, jetc
			FROM term1.term t
			WHERE (t.fk_ns&p_nsmask)::boolean AND t.term = p_qs
			ORDER BY 4 DESC, 3
			LIMIT p_lim;
		WHEN '%', 'p', 's' THEN  	-- 's'equence or 'p'refix
			RETURN QUERY SELECT t.id, t.fk_ns, t.term::text, term_lib.score(p_qs, t.term,p_scfunc, p_maxd), t.is_canonic, t.fk_canonic, jetc
			FROM term1.term t
			WHERE (t.fk_ns&p_nsmask)::boolean AND t.term LIKE (
				CASE WHEN  p->>'op'='p' THEN '' ELSE '%' END || replace(p_qs, ' ', '%')  || '%'
			) 
			ORDER BY 4 DESC, 3
			LIMIT p_lim;
		ELSE				-- '&', '|', etc. resolved by tsquery.
			RETURN QUERY SELECT t.id, t.fk_ns, t.term::text, term_lib.score(p_qs, t.term,p_scfunc, p_maxd), t.is_canonic, t.fk_canonic, jetc
			FROM term1.term_ns t
			WHERE (t.fk_ns&p_nsmask)::boolean AND kx_tsvector @@ to_tsquery(   -- not optimized
				kx_regconf,  replace(p_qs,' ',p->>'op')
			)
			ORDER BY 4 DESC, 3
			LIMIT p_lim;
		END CASE;
	END IF;
	END;
	-- PENDING (FUTURE IMPLEMENTATIONS), on tsquery:
	--  * use of ts_rank(), need good configs.
	--  * "free tsquery" in  p->>'op', for '!' and other complex qsquery expressions.
$f$ LANGUAGE PLpgSQL IMMUTABLE;


--- REVISAR a partir daaqui...

CREATE FUNCTION term1.search2c_tab(
	--
	-- term1.search_tab() complement, to reduce the output to only canonic forms.
	--
	JSONB -- 1. all input parameters. 
) RETURNS term1.tab AS $f$
	SELECT 	max( COALESCE(s.fk_canonic,s.id) ) AS cid, -- the s.id is the canonic when c.term is null
		max(s.nsid) as nsid,        		-- certo é array_agg(distinct s.fk_ns)
		COALESCE(c.term,s.term) AS cterm, 	-- the s.term is the canonic when c.term is null
		max(s.score) as score,  	-- or first_value()
		true::boolean as is_canonic, 	-- all are canonic
		NULL::int as fk_canonic,  	-- all are null
		jsonb_build_object( 'sc_func',max(s.jetc->>'sc_func'), 'synonyms_count', count(*) )
	FROM term1.search_tab($1) s LEFT JOIN term1.term_canonic c ON c.id=s.fk_canonic
	GROUP BY cterm
	ORDER BY score DESC, cterm;
$f$ LANGUAGE SQL IMMUTABLE;


CREATE or replace FUNCTION term1.search2c(
	-- Wrap for JSONB and outputs as RPC. Se #SQL-TEMPLATE of term1.N2C().
	JSONB  -- see all valid params
) RETURNS JSONB AS $f$
DECLARE
	p JSONB;
	r JSONB;
	p_id text;
BEGIN
	p  :=  term_lib.jparams(
		$1,
		'{"lim":null,"osort":true,"otype":"l","qs_is_normalized":true}'::jsonb
	);
	p_id := ($1->>'id')::text; -- from original, webservice caller-ID
	
	SELECT CASE p->>'otype'
		WHEN 'o' THEN 	term_lib.jrpc_ret( array_agg(t.term), array_agg(t.score)::text[], p_id ) -- revisar se pode usar int[]
		WHEN 'a' THEN 	term_lib.jrpc_ret( jsonb_agg(to_jsonb(t.term)), p_id )
		ELSE 		term_lib.jrpc_ret( jsonb_agg(to_jsonb(t)), p_id )
		END INTO r
	FROM term1.search2c_tab(p) t;
	
	RETURN 	 r;
END;
$f$ LANGUAGE PLpgSQL IMMUTABLE;


--- REVIANDI


CREATE or replace FUNCTION term1.find_tab(
--
-- Find a term, or "nearest term", by an heuristic of search strategies. 
-- PS: only didactic illustration, it is not a good algorithm.
--
	text, -- input qs
	JSONB DEFAULT NULL -- input params
) RETURNS JSONB AS $f$
DECLARE
  result JSONB;
  params JSONB;
  lim int DEFAULT 100;          -- LIMIT  (remove??)
  ns smallint DEFAULT 1;        -- Namespace  (remove??)
  mlen int DEFAULT 6;		-- p_metaphone_len  (remove??)
  otype char DEFAULT 'a';
BEGIN
	IF $2 IS NULL THEN 
		params := jsonb_build_object('otype',otype);
	ELSIF $2->'otype' IS NULL THEN 
		params := $2 || jsonb_build_object('otype',otype);
	ELSE
 		params := $2;
		otype  := params->>'otype';
	END IF;
	IF params->'lim' IS NOT NULL THEN lim:=params->>'lim'; END IF;
	IF params->'ns' IS NOT NULL THEN  ns:=params->>'ns'; END IF;


	result := term1.search_tab($1,'=',lim,ns,params); -- exact
	IF (result->'error' IS NOT NULL) THEN  -- checks only the first
		RETURN result;
	ELSIF (result->'result'->>'n')::int >0 THEN
		RETURN result;
	END IF;

	result := term1.search_tab($1,'&',lim,ns,params); -- all words, any order
	IF (result->'result'->>'n')::int >0 THEN
		RETURN result;
	END IF;
	result := term1.search_tab($1,'p',lim,ns,params); -- prefix
	IF (result->'result'->>'n')::int >0 THEN
		RETURN result;
	END IF;

	params := params || jsonb_build_object('metaphone',true); -- enforces metaphone
	IF params->'metaphone_len' IS NOT NULL THEN mlen:=params->>'metaphone_len'; END IF;
	
	result := term1.search_tab($1,'=',lim,ns,mlen,params); -- exact metaphone
	IF (result->'result'->>'n')::int >0 THEN
		RETURN result;
	END IF;
	result := term1.search_tab($1,'&',lim,ns,mlen,params); -- all metaphones, any order
	IF (result->'result'->>'n')::int >0 THEN
		RETURN result;
	END IF;
	result := term1.search_tab($1,'p',lim,ns,mlen,params); -- prefix
	return result;
END;
$f$ LANGUAGE PLpgSQL IMMUTABLE;




---  ---  ---  ---  ---  ---  ---  ---  --- 
---  ---  ---  ---  ---  ---  ---  ---  --- 
---  WRITE PROCEDURES                   --- 
---  ---  ---  ---  ---  ---  ---  ---  --- 


CREATE FUNCTION term1.input_ns() RETURNS TRIGGER AS $f$
BEGIN
	NEW.nsid := term_lib.nsmask(array[NEW.nscount]);
  	NEW.kx_regconf := term_lib.lang2regconf(NEW.lang);
	-- optional to CHECK: IF NEW.kx_regconf IS NULL THEN RAISE
  	IF NEW.fk_partOf IS NOT NULL THEN
		NEW.is_base := false;
	END IF; -- else nothing to say, can be both.
	RETURN NEW;
END;
$f$ LANGUAGE PLpgSQL;
CREATE TRIGGER check_ns
    BEFORE INSERT OR UPDATE ON term1.ns 
    FOR EACH ROW EXECUTE PROCEDURE term1.input_ns()
;


CREATE FUNCTION term1.input_term() RETURNS TRIGGER AS $f$
	-- 
	-- Term normalization and cache initialization for the term table.
	-- OOPS, check term1.ns.lang!
	--
DECLARE
  words text[];
BEGIN
	NEW.term := term_lib.normalizeterm(NEW.term); -- or kx_normalizedterm
	NEW.kx_metaphone := term_lib.multimetaphone(NEW.term,6);  -- IMPORTANT 6, to use in ALL DEFAULTS
	NEW.kx_tsvector  := to_tsvector( term_lib.lang2regconf(term_lib.nsget_lang(NEW.fk_ns)), NEW.term);
	--   IF NEW.is_suspect AND NEW.jinfo->>'suspect_cause' IS NULL THEN RAISE
	RETURN NEW;
END;
$f$ LANGUAGE PLpgSQL;
CREATE TRIGGER check_term
    BEFORE INSERT OR UPDATE ON term1.term
    FOR EACH ROW EXECUTE PROCEDURE term1.input_term()
;

CREATE FUNCTION term1.upsert(
	-- 
	-- UPDATE OR INSERT for term1.term write.  To update only p_name, use direct update.
	--
	p_name text,
	p_ns int,   -- exact ns (not a mask)
	p_info JSONB DEFAULT NULL, -- all data in jsonb
	p_iscanonic boolean DEFAULT false,
        p_fkcanonic int DEFAULT NULL
) RETURNS integer AS $f$
DECLARE
  q_id  int;
BEGIN
	p_name := term_lib.normalizeterm(p_name);
	SELECT id INTO q_id FROM term1.term WHERE term=p_name AND fk_ns=p_ns;
	IF p_name='' OR p_name IS NULL OR p_ns IS NULL THEN
		q_id:=NULL;
	ELSIF q_id IS NOT NULL THEN -- CONDITIONAL UPDATE
		IF p_info IS NOT NULL THEN 
			UPDATE term1.term
			SET  fk_ns=p_ns,  -- ?can change by upsert? 
			     jinfo=p_info, is_canonic=p_iscanonic, fk_canonic=p_fkcanonic -- modified=now()
			WHERE id = q_id;
		END IF; -- else do nothing
	ELSE -- INSERT
		INSERT INTO term1.term (fk_ns, term, jinfo, is_canonic,fk_canonic)
		VALUES (p_ns, p_name, p_info, p_iscanonic, p_fkcanonic)
		RETURNING id INTO q_id;
	END IF;
	RETURN q_id;
END;
$f$ LANGUAGE PLpgSQL;


CREATE FUNCTION term1.ns_upsert(
	--
	-- Inserts when not exist, and sanitize label. Returns ID of the label.
	--
	text, -- label
	char(2),  -- lang
	text  -- description
) RETURNS integer AS $f$
DECLARE
	q_label text;
	r_id  smallint;
BEGIN
	q_label := term_lib.normalizeterm($1); -- only sanitizes
	SELECT nsid INTO r_id FROM term1.ns WHERE label=q_label;
	IF r_id IS NULL THEN
		INSERT INTO term1.ns (label,description,lang) VALUES (q_label,$3,$2) RETURNING nsid INTO r_id;
	END IF;
	RETURN r_id;
END;
$f$ LANGUAGE PLpgSQL;

