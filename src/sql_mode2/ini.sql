-- 
-- Module Term, version 2, cleaning (by "convention over configuration") and optimizing Term1.
-- https://github.com/ppKrauss/pgsql-term
-- Copyright by ppkrauss@gmail.com 2016, MIT license.
--



-- REDO bottlenecks 

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

	ELSE CASE p->>'op'    			-- DIRECT TERMS:
 
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

			--old const. p_conf := term1.set_regconf(p->>'qs_ns',p->>'qs_lang');
-- optimize caching with  SELECT nscount, to_tsquery(kx_regconf,replace(p_qs,' ',p->>'op') as kx from term1.ns where (nsid&p_nsmask)::boolean order by nscount;  so the dictionary q_conv->>fk_ns can be used in q_tsq[q_conv->>fk_ns] of type tsquery[]
-- use fk_ns as index in jsonb hash, that converts fk_ns into 1-n index 
			-- and using term1.term t
			IF p_conf IS NULL THEN
			  RETURN QUERY SELECT -15, 'NULL namespace, input jsonb need params/qs', NULL;
			ELSE
			  RETURN QUERY SELECT t.id, t.term, term_lib.score(p_qs,t.term,p_scfunc,p_maxd), t.is_canonic, t.fk_canonic
			  FROM term1.term_ns t
			  WHERE (t.fk_ns&p_nsmask)::boolean AND kx_tsvector @@ to_tsquery(   -- not optimized
				kx_regconf,  replace(p_qs,' ',p->>'op')
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
