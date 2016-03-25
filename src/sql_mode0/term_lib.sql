-- 
-- Module Term_lib, library of functions that can be used with Term0, Term1 or Term2,
-- and can be dropped (DROP SCHEMA term_lib CASCADE) without direct side effect.
--
-- Usually user-adaptations occurs in jrpc_*(), normalizeterm() and score(). 
-- To rebuild system with changes, usa
-- psql -h localhost -U postgres postgres < src/term_lib.sql 
--
-- See https://github.com/ppKrauss/pgsql-term
-- See also http://www.jsonrpc.org/specification
--
-- Copyright by ppkrauss@gmail.com 2016, MIT license.
--

DROP SCHEMA IF EXISTS term_lib CASCADE;
CREATE EXTENSION IF NOT EXISTS fuzzystrmatch; -- for metaphone() and levenshtein()

CREATE SCHEMA term_lib; -- independent lib for all Term schemas.

-- PRIVATE FUNCTIONS --

CREATE FUNCTION term_lib.nsget_lang(int,boolean DEFAULT false) RETURNS char(2) AS $f$
	--
	-- Inter-schema alias for term1.nsget_lang_aux(). 
	--
	SELECT term1.nsget_lang_aux($1,$2);  -- !Change here the calling function to term0 or term2 when necessary!
$f$ LANGUAGE SQL IMMUTABLE;


CREATE FUNCTION term_lib.jparams(
	--
	-- Converts JSONB or JSON-RPC request (with reserved word "params") into JSOB+DEFAULTS.
	--
	-- Ex.SELECT term_lib.jparams('{"x":12}'::jsonb, '{"x":5,"y":34}'::jsonb)
	--
	JSONB,			-- the input request (direct or at "params" property)
	JSONB DEFAULT NULL	-- (optional) default values.
) RETURNS JSONB AS $f$	
	SELECT CASE WHEN $2 IS NULL THEN jo ELSE $2 || jo END
	FROM (SELECT CASE WHEN $1->'params' IS NULL THEN $1 ELSE $1->'params' END AS jo) t;
$f$ LANGUAGE SQL IMMUTABLE;


CREATE FUNCTION term_lib.unpack(
	--
	-- Remove a sub-object and merge its contents.
	-- Ex. SELECT term_lib.unpack('{"x":12,"sub":{"y":34}}'::jsonb,'sub');
	--
	JSONB,	-- full object
	text	-- pack name
) RETURNS JSONB AS $f$	
	SELECT ($1-$2)::JSONB || ($1->>$2)::JSONB;
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


CREATE FUNCTION term_lib.jrpc_ret(
	--
	-- Adds standard term_lib structure to RPC result.
	-- See https://github.com/ppKrauss/sql-term/issues/5
	--
	JSON,      		-- 1. full result (all items) before to pack
	int,       		-- 2. items COUNT of the full result 
	text DEFAULT NULL, 	-- 3. id of callback
	text DEFAULT NULL, 	-- 4. sc_func or null for use 5 
	JSONB DEFAULT NULL      -- 5. json with sc_func and other data, instead of 4.
) RETURNS JSONB AS $f$
	SELECT jsonb_build_object(
		'result', CASE 
			WHEN $5 IS NOT NULL THEN jsonb_build_object('items',$1, 'count',$2) || $5
			WHEN $4 IS NULL THEN jsonb_build_object('items',$1, 'count',$2)
			ELSE jsonb_build_object('items',$1, 'count',$2, 'sc_func',$4)
			END,
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
	-- Define all score functions (sc_func labels). 
	-- Compare, typically by Levenshtein score functions, 2 normalized terms. 
	-- Not so useful and NOT OPTIMIZED (ideal is C library).
	-- Main functions: 'levdiffpercp' as 'std' and 'levdiffperc'.
	-- NOTES: Caution in 'std', when using low p_maxd, long strings. 
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
		-- IF p_label !='exact' THEN:
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
			WHEN 'exact','exact-long' THEN RETURN CASE WHEN $1=$2 THEN 100 ELSE 0 END;  -- bigger is better
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

CREATE TYPE term_lib.tab AS (score int, sc_func text, term text);

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
-- Namespace functions 

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


CREATE FUNCTION term_lib.lang2regconf(text) RETURNS regconfig AS $f$
	-- 
	-- Convention to convert iso2 into regconfig for indexing words. See kx_regconf.
	--
	SELECT  (('{"pt":"portuguese","en":"english","es":"spanish","":"simple","  ":"simple"}'::jsonb)->>$1)::regconfig
$f$ LANGUAGE SQL IMMUTABLE;



