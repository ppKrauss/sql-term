-- 
-- Module Term, version-1. Term1 adds JSON interface, score metric and tag-relation to Term0.
-- https://github.com/ppKrauss/pgsql-term
-- Copyright by ppkrauss@gmail.com 2016, MIT license.
-- See also http://www.jsonrpc.org/specification
--
-- nova diretiva = controle de namespaces nas buscas!  por exemplo SciELO precisa separar inglês de portugues
--
-- PS: ideal de busca é adaptar à lang da mask a cada busca, ou seja, muda-se o metaphone e/ou vetor de busca conforme namespace
--   em que se está buscando... Portano um CASE dentro do WHERE, para uma array prefixada em função da fk_ns 

DROP SCHEMA IF EXISTS term_lib CASCADE;

CREATE SCHEMA term_lib; -- independent lib for all Term schemas.

-- PRIVATE FUNCTIONS --

CREATE FUNCTION term_lib.jparams(
	--
	-- Converts JSONB or JSON-RPC request (with reserved word "params") into JSOB+DEFAULTS.
	--
	-- Ex.SELECT term_lib.jparams('{"x":123}'::jsonb, '{"x":1,"y":999}'::jsonb)
	--
	JSONB,			-- the input request (direct or at "params" property)
	JSONB DEFAULT NULL	-- (optional) default values.
) RETURNS JSONB AS $f$	
	SELECT CASE WHEN $2 IS NULL THEN jo ELSE $2 || jo END
	FROM (SELECT CASE WHEN $1->'params' IS NULL THEN $1 ELSE $1->'params' END AS jo) t;
$f$ LANGUAGE SQL IMMUTABLE;


CREATE FUNCTION term_lib.jrpc_error(
	--
	-- Converts input into a JSON RPC error-object.
	--
	-- Ex. SELECT term_lib.jrpc_error('ops error',123,'i2');
	--
	text,         		-- 1. error message
	int DEFAULT -1,  	-- 2. error code
	text DEFAULT NULL	-- 3. (optional) calling id (when NULL it is assumed to be a notification) 
) RETURNS JSONB AS $f$
	SELECT jsonb_build_object(
		'error',jsonb_build_object('code',$2, 'message', $1), 
		'id',$3, 
		'jsonrpc','2.0'
	);
$f$ LANGUAGE SQL IMMUTABLE;


CREATE FUNCTION term_lib.jrpc_ret(
	--
	-- Converts input into a JSON RPC result scalar or single object.
	--
	-- Ex. SELECT term_lib.jrpc_ret(123,'i1');      SELECT term_lib.jrpc_ret('123'::text,'i1');
	--     SELECT term_lib.jrpc_ret(123,'i1','X');  SELECT term_lib.jrpc_ret(array['123']);
	--     SELECT term_lib.jrpc_ret(array[1,2,3],'i1','X');
	-- Other standars, see Elasticsearch output at http://wayta.scielo.org/
	--
	anyelement,		-- 1. the result value
	text DEFAULT NULL, 	-- 2. (optional) calling id (when NULL it is assumed to be a notification) 
	text DEFAULT NULL 	-- 3. (optional) the result sub-object name
) RETURNS JSONB AS $f$
	SELECT jsonb_build_object(
		'result', CASE WHEN $3 IS NULL THEN to_jsonb($1) ELSE jsonb_build_object($3,$1) END,
		'id',$2,
		'jsonrpc','2.0'
		);
$f$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION term_lib.jrpc_ret(
	--
	-- jrpc_ret() overload to convert to a dictionary (object with many names).
	--
	-- Ex. SELECT term_lib.jrpc_ret(array['a'],array['123']);
	--     SELECT term_lib.jrpc_ret(array['a','b','c'],array[1,2,3],'i1');
	--
	text[],		  	-- 1. the result keys
	anyarray, 	  	-- 2. the result values
	text DEFAULT NULL 	-- 3. (optional) calling id (when NULL it is assumed to be a notification) 
) RETURNS JSONB AS $f$
	SELECT jsonb_build_object(
		'result', (SELECT jsonb_object_agg(k,v) FROM (SELECT unnest($1), unnest($2)) as t(k,v)),
		'id',$3,
		'jsonrpc',' 2.0'
		);
$f$ LANGUAGE SQL IMMUTABLE;


-- -- -- -- -- -- -- --
--- PUBLIC FUNCTIONS

CREATE FUNCTION term_lib.normalizeterm(
	--
	-- Converts string into standard sequence of lower-case words.
	--
	text,       		-- 1. input string (many words separed by spaces or punctuation)
	text DEFAULT ' ', 	-- 2. separator
	int DEFAULT 255		-- 3. max lenght of the result (system limit)
) RETURNS text AS $f$
  SELECT  substring(
	LOWER(TRIM( regexp_replace(  -- for review: regex(regex()) for ` , , ` remove
		trim(regexp_replace($1,E'[\\+/,;:\\(\\)\\{\\}\\[\\]="\\s]*[\\+/,;:\\(\\)\\{\\}\\[\\]="]+[\\+/,;:\\(\\)\\{\\}\\[\\]="\\s]*|\\s+[–\\-]\\s+',' , ', 'g'),' ,'),   -- s*ps*|s-s
		E'[\\s;\\|"]+[\\.\'][\\s;\\|"]+|[\\s;\\|"]+',    -- s.s|s
		$2,
		'g'
	), $2 )),
  1,$3
  );
$f$ LANGUAGE SQL IMMUTABLE;


CREATE FUNCTION term_lib.multimetaphone( 
	--
	-- Converts string (spaced words) into standard sequence of metaphones.
	-- Copied from term_lib.normalizeterm(). Check optimization with 
	--
	text,       		-- 1. input string (many words separed by spaces or punctuation)
	int DEFAULT 6, 		-- 2. metaphone length
	text DEFAULT ' ', 	-- 3. separator
	int DEFAULT 255		-- 4. max lenght of the result (system limit)
) RETURNS text AS $f$
	SELECT 	 substring(  trim( string_agg(metaphone(w,$2),$3) ,$3),  1,$4)
	FROM regexp_split_to_table($1, E'[\\+/,;:\\(\\)\\{\\}\\[\\]="\\s\\|]+[\\.\'][\\+/,;:\\(\\)\\{\\}\\[\\]="\\s\\|]+|[\\+/,;:\\(\\)\\{\\}\\[\\]="\\s\\|]+') AS t(w);  -- s.s|s  -- já contemplado pelo espaço o \s[–\\-]\s
$f$ LANGUAGE SQL IMMUTABLE;


CREATE FUNCTION term_lib.score(
	-- 
	-- Levenshtein comparison score functions. Compare 2 normalized terms. NOT USEFUL, NOT OPTIMIZED (if more 1 need a C library).
	-- Caution: when using low p_maxd, long strings 
	--
	-- Ex. SELECT term_lib.score('foo','foo') as eq, term_lib.score('foo','floor') as similar, term_lib.score('foo','bar') as dif;
	-- 
	text,                   	-- 1. input string
	text,                    	-- 2. input string, to levenshtein($1,$2).
	p_label text DEFAULT NULL, 	-- 3. score function label. NULL is optimized to 'std'.
	p_maxd int DEFAULT 100    	-- 4. Param max_d in levenshtein_less_equal(a,b,max_d). Ex. average input lenght
) RETURNS int AS $f$
	DECLARE
		rlev float; -- result of levenshtein
		glen float;
		label varchar(32);
		cklong boolean;
	BEGIN
		cklong := (right(p_label,5)='-long');
		rlev  := CASE 
			WHEN p_maxd IS NULL AND cklong THEN levenshtein($1,$2,2,1,1) -- score penalty for longer strings 
			WHEN p_maxd IS NULL THEN levenshtein($1,$2,1,1,1)
			WHEN cklong THEN levenshtein_less_equal($1,$2, 2,1,1,p_maxd)
			ELSE  levenshtein_less_equal($1,$2,1,1,1,p_maxd) 
			END;
		glen  := CASE WHEN NOT(cklong) AND p_maxd IS NOT NULL 
			      THEN least( p_maxd*2, greatest(char_length($1),char_length($2)) )::float
			      ELSE greatest(char_length($1),char_length($2))::float END;
		CASE p_label::text 
			WHEN 'lev','lev-long' 	   	THEN RETURN  rlev;  -- less is better
			WHEN 'lev500','lev500-long' 	THEN RETURN 500.0 - rlev; -- bigger is better
			WHEN 'lev500perc','lev500perc-long' 	THEN RETURN ((500.0 - rlev)/glen); -- bigger is better
			WHEN 'lev500percp','lev500percp-long' 	THEN RETURN ((500.0 - rlev)/(glen+rlev)); -- bigger			
			WHEN 'levdiffperc','levdiffperc-long'   THEN RETURN (100.0*(glen-rlev) / glen);  -- bigger is better
			ELSE RETURN 100.0*(glen-rlev) / (glen+rlev); -- '6','levdiffpercp' -- bigger is better
		END CASE;
	END;
$f$ LANGUAGE PLpgSQL IMMUTABLE;


CREATE or replace FUNCTION term_lib.score(
	-- Ex. SELECT term_lib.score('{"a":"foo","b":"fox","sc_maxd":3}'::jsonb)
	JSONB			-- all parameters
) RETURNS int AS $f$  
	-- wrap function
	WITH j AS( SELECT term_lib.jparams($1, '{"sc_func":"std","sc_maxd":100}'::jsonb) AS p )
	SELECT term_lib.score(j.p->>'a',j.p->>'b',j.p->>'sc_func', (j.p->>'sc_maxd')::int) FROM j;
$f$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION term_lib.ws_score(
	-- 
	-- Webservice direct callback for a request. Wrap function.
	-- Ex. SELECT term_lib.ws_score('{"id":123,"params":{"a":"foo","b":"fox","sc_maxd":1}}'::jsonb)
	-- 
	JSONB			-- JSON input
) RETURNS JSONB AS $f$
	SELECT term_lib.jrpc_ret( term_lib.score($1), $1->>'id' );
$f$ LANGUAGE SQL IMMUTABLE;


--- --- ---
-- Scoring pairs functions:

CREATE TYPE term_lib.tab AS (score int, sc_type text, term text);

CREATE FUNCTION term_lib.score_pairs_tab(
	-- 
	-- Term-array comparison, scoring and reporting preffered results.
	-- Ex. SELECT * FROM term_lib.score_pairs_tab('foo', array['foo','bar','foos','fo','x']);
	-- 
	text,             	-- 1. qs, query string or ref. term.
	text[],           	-- 2. list, compared terms.
	int DEFAULT NULL, 	-- 3. cut, apenas itens com score>=corte. Se negativo, score<corte.
	int DEFAULT NULL, 	-- 4. LIMIT (NULL=ALL) 
	text DEFAULT 'std', 	-- 5. score function label for term_lib.score($8,$5)
	int DEFAULT 50,    	-- 6. Param max_d in levenshtein_less_equal(a,b,max_d). Ex. 50.
	boolean DEFAULT true  	-- 7. Sort flag.
) RETURNS SETOF term_lib.tab AS $f$
	WITH q AS (
		SELECT term_lib.score($1,cmp,$5,$6) as sc,  $5, cmp
		FROM unnest($2) t(cmp)
	) 
	   SELECT *
	   FROM q
	   WHERE CASE WHEN $3 IS NULL THEN true  WHEN $3<0 THEN sc<(-1*$3) ELSE sc>=$3 END
	   ORDER BY 
		CASE WHEN $7 THEN sc ELSE 0 END DESC, 
		CASE WHEN $7 THEN cmp ELSE '' END
	   LIMIT $4;
$f$ LANGUAGE SQL IMMUTABLE;


CREATE OR REPLACE FUNCTION term_lib.score_pairs(
	--
	-- Wrap for term_lib.score_pairs() using jsonb as input and output.
	-- Ex. SELECT * FROM term_lib.score_pairs('foo'::text, array['foo','bar','foos','fo','x'],'{"id":3333,"otype":"o"}'::jsonb);
	-- 
	text,             	-- 1. qs, query string or ref. term.
	text[],           	-- 2. list, compared terms.
	JSONB			-- 3. all other parameters (see conventions for 'cut', 'lim', etc.)
) RETURNS JSONB AS $f$
DECLARE
	p JSONB;
	r JSONB;
	id text;
BEGIN
	p  :=  term_lib.jparams(
		$3,
		'{"cut":null,"lim":null,"sc_func":"std","sc_maxd":50,"osort":true,"otype":"l"}'::jsonb
	);
	id := ($3->>'id')::text; -- from original
	SELECT CASE p->>'otype'
		WHEN 'o' THEN 	term_lib.jrpc_ret( array_agg(t.term), array_agg(t.score), id )
		WHEN 'a' THEN 	term_lib.jrpc_ret( jsonb_agg(to_jsonb(t.term)), id )
		ELSE 		term_lib.jrpc_ret( jsonb_agg(to_jsonb(t)), id )
		END  
	INTO r
	FROM term_lib.score_pairs_tab(
			$1, 			$2,
			(p->>'cut')::int, 	(p->>'lim')::int, 
			 p->>'sc_func', 	(p->>'sc_maxd')::int,    (p->>'osort')::boolean
	) t;
	RETURN 	 r;
END;
$f$ LANGUAGE PLpgSQL IMMUTABLE;

CREATE or replace FUNCTION term_lib.score_pairs(JSONB) RETURNS JSONB AS $f$
	-- Wrap function to full-JSOND input in term_lib.score_pairs().
	WITH j AS( SELECT term_lib.jparams($1) AS p )
	SELECT x
	FROM (SELECT term_lib.score_pairs(
		j.p->>'qs', 
		( SELECT array_agg(x) FROM jsonb_array_elements_text(j.p->'list') t(x) ),
		$1    -- from original
	) as x FROM j) t;
$f$ LANGUAGE SQL IMMUTABLE;



--- --- ---
-- Other functions 

CREATE FUNCTION term_lib.nsmask(
	--
	-- Build mask for namespaces (ns). See nsid at term1.ns. Also builds nsid from nscount by array[nscount].
	-- Ex. SELECT  term_lib.nsmask(array[2,3,4])::bit(32);
	-- Range 1..32.
	-- 
	int[]  -- List of namespaces (nscount of each ns)
) RETURNS int AS $f$
	SELECT sum( (1::bit(32) << (x-1) )::int )::int 
	FROM unnest($1) t(x) 
	WHERE x>0 AND x<=32;
$f$ LANGUAGE SQL IMMUTABLE;


--- --- --- --- --- --- --- --- ---
--- --- --- --- --- --- --- --- ---
--- --- --- --- --- --- --- --- ---


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
  CHECK(ARRAY['pt','en','es','  ']::char(2)[] @> ARRAY[lang]), -- see term1.input_ns()
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
  created date DEFAULT now(),
  jinfo JSONB,     -- any other metadata.
  kx_metaphone varchar(400), -- idexed cache
  kx_tsvector tsvector,      -- cache for to_tsvector(lang, term)
  -- kx_lang char(2),   -- for use in dynamic qsquery, with some previous cached configs in json or array of configs. See ns.kx_regconf 
  UNIQUE(fk_ns,term),
  CHECK( (is_canonic AND fk_canonic IS NULL) OR NOT(is_canonic) )
  -- see also input_term() trigger.
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



-- -- -- -- -- -- -- 
-- TERM1 TERM-RESOLVERS:
CREATE TYPE term1.tab AS (id int, nsid int, score int, sc_type text, term text);

CREATE or replace FUNCTION term1.N2C_tab(
	-- 
	-- Returns de canonic term from a valid term of a namespace.
	-- Exs. SELECT *  FROM term1.N2C_tab(' - USP - ','wayta-pt'::text,false); 
	--      SELECT term1.N2C_tab('puc-mg',term1.nsget_nsid('wayta-code'),true);
	--
	text,   		-- 1. valid term
	int,     		-- 2. namespace MASK, ex. by term1.basemask().
	boolean DEFAULT true  	-- 3. exact (true) or apply normalization (false)
) RETURNS SETOF term1.tab  AS $f$
	SELECT id, fk_ns as nsid, 100::int, 'exact'::text, term_canonic::text
	FROM term1.term_full 
	WHERE (fk_ns&$2)::boolean  AND  CASE WHEN $3 THEN term=$1 ELSE term=term_lib.normalizeterm($1) END 
$f$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION term1.N2C_tab(text,text,boolean DEFAULT true) RETURNS SETOF term1.tab  AS $f$
  -- overloading 
  SELECT term1.N2C_tab($1, term1.basemask($2), $3);
$f$ LANGUAGE SQL IMMUTABLE;

CREATE or replace FUNCTION term1.N2C(JSONB) RETURNS JSONB AS $f$
--- revisar
	-- JSONB io overloading
	-- ex. SELECT term1.N2C('{"qs":"puc-mg","nsmask":30,"qs_is_normalized":true}'::jsonb);
	SELECT to_jsonb(t) FROM term1.N2C_tab($1->>'qs', term1.nsget_opt2int($1), ($1->>'qs_is_normalized')::boolean) t;
$f$ LANGUAGE SQL IMMUTABLE;

-- -- --
-- N2Ns:
CREATE FUNCTION term1.N2Ns_tab(
	-- 
	-- Returns canonic and all the synonyms of a valid term (of a namespace).
	-- Ex. SELECT * FROM term1.N2Ns_tab(' - puc-mg - ',4,false);  -- 
	--
	text,            	-- 1. valid term
	int DEFAULT 1,     	-- 2. namespace MASK
	boolean DEFAULT true	-- 3. exact (true) or apply normalization (false)
) RETURNS SETOF term1.tab AS $f$
   SELECT t.id, t.fk_ns as nsid, 100::int, 'exact'::text, t.term
   FROM term1.term t, (
	   SELECT CASE WHEN is_canonic THEN -- mais de 50%
			s.id 
		ELSE (SELECT id FROM term1.term_canonic t WHERE t.id=s.fk_canonic) 
		END as canonic_id
	   FROM term1.term s
	   WHERE (fk_ns&$2)::boolean  AND  CASE WHEN $3 THEN term=$1 ELSE term=term_lib.normalizeterm($1) END
   ) c
   WHERE t.id=c.canonic_id OR fk_canonic=c.canonic_id
   ORDER BY t.fk_ns, t.term;
$f$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION term1.N2Ns_tab(text,text,boolean DEFAULT true) RETURNS SETOF term1.tab AS $f$
	SELECT term1.N2Ns_tab($1, term1.basemask($2), $3);
$f$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION term1.N2Ns(JSONB) RETURNS JSONB AS $f$
-- revisar, dar opções de ns_mask=dado, ns_maskbase=term1.basemask(), ns_masklabel=term1.getns_by?() e ns_maskcount=term1.getns_by?()
	-- JSONB io overloading
	-- ex. SELECT term1.N2Ns('{"qs":"fumcap","basemask":"wayta-pt","qs_is_normalized":true}'::jsonb);
	SELECT to_jsonb(t) FROM term1.N2Ns_tab($1->>'qs', term1.nsget_opt2int($1), ($1->>'qs_is_normalized')::boolean) t;
$f$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION term1.nsget_opt2int(JSONB) RETURNS int AS $f$
--  dar opções de ns_mask=dado, ns_maskbase=term1.basemask(), ns_masklabel=term1.getns_by?() e ns_maskcount=term1.getns_by?()
	-- nao confere se era válido como mascara
$f$ LANGUAGE SQL IMMUTABLE;



-- -- -- -- -- -- -- --
-- TERM-SEARCH ENGINES:

CREATE FUNCTION term1.search_tab(
	--
	--  Executes all search forms, by similar terms, and all output modes provided for the system.
	--  Debug with 'search-json'
	--  Namespace: use scalar for ready mask, or array of nscount for build mask. 
	--  Lang or namespace of the query string (qs_lang or qs_ns), qs_ns is used when qs_lang is null.
	--  @DEFAULT-PARAMS "op": "=", "lim": 5, "scfunc": "dft", "metaphone": false, "sc_maxd": 100, "metaphone_len": 6, ...
	--
	JSONB -- 1. all input parameters. 
) RETURNS TABLE(id int, term varchar, score int, is_canonic boolean, fk_canonic int) AS $f$ 
DECLARE
	p JSONB;
	p_scfunc text; 	-- Score function label
	p_qs text;
	p_nsmask int;
	p_maxd int;    	-- Param max_d in levenshtein_less_equal(a,b,max_d). Ex. average input lenght
	p_lim bigint;
	p_mlen int;
	p_conf regconfig;
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
	p_nsmask:= CASE WHEN jsonb_typeof(p->'nsmask')='array' THEN term_lib.nsmask((p->'nsmask')::int[]) ELSE (p->>'nsmask') END;
	p_scfunc := p->>'sc_func';
	p_maxd :=   p->>'sc_maxd';
	p_lim  :=   p->>'lim';
	IF p->>'metaphone' THEN
		p_mlen := (p->>'metaphone_len')::int;
		CASE p->>'op'
		WHEN 'e','=' THEN  		-- exact
			RETURN QUERY SELECT t.id, t.term, term_lib.score(p_qs, t.term,p_scfunc, p_maxd), t.is_canonic, t.fk_canonic
			FROM term1.term t
			WHERE (t.fk_ns&p_nsmask)::boolean AND t.kx_metaphone = term_lib.multimetaphone(p_qs,p_mlen,' ')
			ORDER BY 3 DESC, 2
			LIMIT p_lim;
		WHEN '%','p','s' THEN 	 	-- s'equence OR p'refix
			RETURN QUERY SELECT t.id, t.term, term_lib.score(p_qs,t.term,p_scfunc,p_maxd), t.is_canonic, t.fk_canonic 
			FROM term1.term t
			WHERE (t.fk_ns&p_nsmask)::boolean AND t.kx_metaphone LIKE (
				CASE WHEN p->>'op'='p' THEN '' ELSE '%' END || term_lib.multimetaphone(p_qs,p_mlen,'%') || '%'
			) 
			ORDER BY 3 DESC, 2			
			LIMIT p_lim;
		ELSE  				-- pending, needs also "free tsquery" in $2 for '!' use and complex expressions
			RETURN QUERY SELECT t.id, t.term, term_lib.score(p_qs,t.term,p_scfunc,p_maxd), t.is_canonic, t.fk_canonic
			FROM term1.term t
			WHERE (t.fk_ns&p_nsmask)::boolean AND to_tsvector('simple',t.kx_metaphone) @@ to_tsquery(
				'simple',
				term_lib.multimetaphone(p_qs,p_mlen,p->>'op'::text)
			) 
			ORDER BY 3 DESC, 2
			LIMIT p_lim;
		END CASE;
	ELSE CASE p->>'op'
		WHEN 'e', '=' THEN  		-- exact
			RETURN QUERY SELECT t.id, t.term, term_lib.score(p_qs,t.term,p_scfunc,p_maxd), t.is_canonic, t.fk_canonic 
			FROM term1.term t
			WHERE (t.fk_ns&p_nsmask)::boolean AND t.term = p_qs
			ORDER BY 3 DESC, 2
			LIMIT p_lim;
		WHEN '%', 'p', 's' THEN  	-- 's'equence or 'p'refix
			RETURN QUERY SELECT t.id, t.term, term_lib.score(p_qs,t.term,p_scfunc,p_maxd), t.is_canonic, t.fk_canonic
			FROM term1.term t
			WHERE (t.fk_ns&p_nsmask)::boolean AND t.term LIKE (
				CASE WHEN  p->>'op'='p' THEN '' ELSE '%' END || replace(p_qs, ' ', '%')  || '%'
			) 
			ORDER BY 3 DESC, 2
			LIMIT p_lim;
		ELSE				-- '&', '|', etc. resolved by tsquery.
			p_conf := term1.set_regconf(p->>'qs_ns',p->>'qs_lang'); -- ns by label or nscount, lang by iso2
			IF p_conf IS NULL THEN
			  RETURN QUERY SELECT -15, 'NULL namespace, input jsonb need params/qs', NULL;
			ELSE
			  RETURN QUERY SELECT t.id, t.term, term_lib.score(p_qs,t.term,p_scfunc,p_maxd), t.is_canonic, t.fk_canonic
			  FROM term1.term t
			  WHERE (t.fk_ns&p_nsmask)::boolean AND kx_tsvector @@ to_tsquery(
				p_conf,  replace(p_qs,' ',p->>'op')
			  )
			  ORDER BY 3 DESC, 2
			  LIMIT p_lim;
			END IF;
		END CASE;
	END IF;
	END;
	-- PENDING (FUTURE IMPLEMENTATIONS)
	--  * use of ts_rank(), need good configs.
	--  * "free tsquery" in  p->>'op', for '!' and other complex qsquery expressions.
$f$ LANGUAGE PLpgSQL IMMUTABLE;

CREATE FUNCTION term1.search(JSONB) RETURNS JSONB AS $f$
	-- Wrap function for term1.search_tab(), returning standard JSON-RPC.
	SELECT 	term_lib.jrpc_ret(
			jsonb_agg( to_jsonb(t) ),  
			$1->>'id'
		)
	FROM term1.search_tab($1) t
$f$ LANGUAGE SQL IMMUTABLE;


CREATE FUNCTION term1.search2c_tab(
	--
	-- term1.search_tab() complement to reduce the putput to only canonic forms.
	--
	JSONB -- 1. all input parameters. 
) RETURNS TABLE(id int, term varchar, score int) AS $f$
	SELECT 	max( COALESCE(s.fk_canonic,s.id) ) AS cid,   -- the s.id is the canonic when c.term is null
		COALESCE(c.term,s.term) AS cterm,           -- the s.term is the canonic when c.term is null
		max(s.score) as score
	FROM term1.search_tab($1) s LEFT JOIN term1.term_canonic c ON c.id=s.fk_canonic
	GROUP BY cterm
	ORDER BY score DESC, cterm;
$f$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION term1.search2c(JSONB) RETURNS JSONB AS $f$
	-- Wrap function for term1.search2c_tab(), returning standard JSON-RPC.
	SELECT 	jsonb_agg( to_jsonb(t) ) 
	FROM term1.search2c_tab($1) t
$f$ LANGUAGE SQL IMMUTABLE;
 

CREATE FUNCTION term1.search_oldWrap(
	--
	-- Overload term1.search(), wrap to enforce use of normal-search.
	--
	text,                      -- 1. query string (usual term or term-fragments)
	text DEFAULT '&', 	   -- 2. '=', '&','|' or free or like-search ('%' or 'p' for prefix)
	int DEFAULT 100,           -- 3. LIMIT
        smallint DEFAULT 1,        -- 4. Namespace
	jsonb DEFAULT NULL	   -- 5. Other parameters (overhiden)
) RETURNS JSONB AS $f$
	-- qs_lang e qs_ns são alternativas válidas, importante parametrizar isso, ou restringir a lang.
	SELECT CASE WHEN $5 IS NULL THEN term1.search(oo) ELSE term1.search($5 || oo) END
	FROM (SELECT jsonb_build_object('qs',$1, 'op',$2, 'lim',$3, 'ns',$4, 'metaphone',false) as oo) t;
$f$ LANGUAGE SQL IMMUTABLE;


CREATE FUNCTION term1.search_metaphone(
--
-- Wrap to term1.search(), enforsing use of metaphone-search.
--
	text,                      -- 1. query string (usual term or term-fragments)
	text DEFAULT '&', 	   -- 2. '=', '&','|' or free or like-search ('%' or 'p' for prefix)
	int DEFAULT 100,           -- 3. LIMIT
        smallint DEFAULT 1,        -- 4. Namespace
	int DEFAULT 6,		   -- 5. p_metaphone_len
	jsonb DEFAULT NULL	   -- 6. Other parameters (overhiden)
) RETURNS JSONB AS $f$
	SELECT CASE WHEN $6 IS NULL THEN term1.search(oo) ELSE term1.search($6 || oo) END
	FROM (SELECT jsonb_build_object('qs',$1, 'op',$2, 'lim',$3, 'ns',$4, 'metaphone',true, 'p_metaphone_len',$5) as oo) t;
$f$ LANGUAGE SQL IMMUTABLE;


CREATE FUNCTION term1.find(
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
	IF params->'metaphone_len' IS NOT NULL THEN mlen:=params->>'metaphone_len'; END IF;

	result := term1.search($1,'=',lim,ns,params); -- exact
	IF (result->'error' IS NOT NULL) THEN  -- checks only the first
		RETURN result;
	ELSIF (result->'result'->>'n')::int >0 THEN
		RETURN result;
	END IF;

	result := term1.search($1,'&',lim,ns,params); -- all words, any order
	IF (result->'result'->>'n')::int >0 THEN
		RETURN result;
	END IF;
	result := term1.search($1,'p',lim,ns,params); -- prefix
	IF (result->'result'->>'n')::int >0 THEN
		RETURN result;
	END IF;

	result := term1.search_metaphone($1,'=',lim,ns,mlen,params); -- exact metaphone
	IF (result->'result'->>'n')::int >0 THEN
		RETURN result;
	END IF;
	result := term1.search_metaphone($1,'&',lim,ns,mlen,params); -- all metaphones, any order
	IF (result->'result'->>'n')::int >0 THEN
		RETURN result;
	END IF;
	result := term1.search_metaphone($1,'p',lim,ns,mlen,params); -- prefix
	return result;
END;
$f$ LANGUAGE PLpgSQL IMMUTABLE;

-- -- -- -- -- -- -- -- --
-- lang and conf wrappers:

-- see also term1.basemask().
CREATE FUNCTION term1.nsget_nsid(text) RETURNS int AS $f$ SELECT nsid FROM term1.ns WHERE label=$1; $f$ LANGUAGE SQL IMMUTABLE;
CREATE FUNCTION term1.nsget_nsid(int) RETURNS int AS $f$ SELECT nsid FROM term1.ns WHERE nscount=$1::smallint; $f$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION term1.nsget_lang(int,boolean DEFAULT true) RETURNS char(2) AS $f$
-- 
-- Namespace language by its nscount (or nsid when $2 false)
--
	SELECT lang FROM term1.ns WHERE CASE WHEN $2 THEN nscount=$1::smallint ELSE nsid=$1 END;
 	-- NULL is error, '' is a valid "no language"
$f$ LANGUAGE SQL IMMUTABLE;
CREATE FUNCTION term1.lang2regconf(lang char(2)) RETURNS regconfig AS $f$
-- 
-- Convention to convert iso2 into regconfig for indexing words. See kx_regconf.
--
	SELECT  (('{"pt":"portuguese","en":"english","es":"spanish","":"simple","  ":"simple"}'::jsonb)->>$1)::regconfig
$f$ LANGUAGE SQL IMMUTABLE;



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
CREATE FUNCTION term1.lang2regconf(lang char(2),nscount int,boolean DEFAULT true) RETURNS regconfig AS $f$
-- 
-- Overload for lang=NULL and nscount/nsid option.
--
	SELECT  COALESCE( term1.lang2regconf($1), term1.nsget_conf($2,$3) );
$f$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION term1.set_regconf(anyelement,text) RETURNS regconfig AS $f$  --revisar usabilidade do anyelement
	SELECT  COALESCE( term1.nsget_conf($1), term1.lang2regconf($2) );
$f$ LANGUAGE SQL IMMUTABLE;



---  ---  ---  ---  ---  ---  ---  ---  --- 
---  ---  ---  ---  ---  ---  ---  ---  --- 
---  WRITE PROCEDURES                   --- 
---  ---  ---  ---  ---  ---  ---  ---  --- 


CREATE FUNCTION term1.input_ns() RETURNS TRIGGER AS $f$
BEGIN
	NEW.nsid := term_lib.nsmask(array[NEW.nscount]);
  	NEW.kx_regconf := term1.lang2regconf(NEW.lang);
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
	NEW.kx_tsvector := to_tsvector('portuguese', NEW.term); -- use term1.ns.lang!
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




