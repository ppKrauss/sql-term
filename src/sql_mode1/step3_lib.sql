
---  ---  ---  ---  ---
---  ---  ---  ---  ---
--- TSTORE PUBLIC LIB
---  ---  ---  ---  ---

-- -- -- -- -- -- -- -- --
-- namespace wrappers:

CREATE FUNCTION tlib.basemask(
	--
	-- Generates a nsmask of all namespaces of a base-namespace.
	--
	text -- label of the base-namespace.
) RETURNS int AS $f$
SELECT sum(nsid)::int
FROM (
	WITH basens as (
		SELECT * FROM tstore.ns WHERE label=lower($1) -- um  so
	) SELECT nsid, 1 as x FROM basens WHERE is_base
	  UNION
	  SELECT fk_partOf, 2 FROM basens  WHERE NOT(is_base)
	  UNION
	  SELECT n.nsid, 3 FROM tstore.ns n, basens b
	  WHERE (b.is_base AND n.fk_partOf=b.nsid) OR (NOT(b.is_base) AND n.fk_partOf=b.fk_partOf)
) t;
$f$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION tlib.basemask(
	-- Overload, wrap for int ns.
	int -- valid nsid!
) RETURNS int AS $f$
	SELECT tlib.basemask(label) FROM tstore.ns WHERE nsid=$1;
$f$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION tlib.nsget_nsid(text) RETURNS int AS $f$ SELECT nsid FROM tstore.ns WHERE label=$1; $f$ LANGUAGE SQL IMMUTABLE;
CREATE FUNCTION tlib.nsget_nsid(int) RETURNS int AS $f$ SELECT nsid FROM tstore.ns WHERE nscount=$1::smallint; $f$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION tlib.nsid2label(int) RETURNS text AS $f$ SELECT label FROM tstore.ns WHERE nsid=$1; $f$ LANGUAGE SQL IMMUTABLE;
CREATE FUNCTION tlib.nsid2lang(int) RETURNS text AS $f$ SELECT lang::text FROM tstore.ns WHERE nsid=$1; $f$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION tlib.nsget_conf(int,boolean DEFAULT true) RETURNS regconfig AS $f$
	--
	-- Namespace language by its nscount (or nsid when $2 false)
	--
	SELECT kx_regconf FROM tstore.ns WHERE CASE WHEN $2 THEN nscount=$1::smallint ELSE nsid=$1 END;
$f$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION tlib.nsget_conf(text) RETURNS regconfig AS $f$
	--
	-- Namespace language by its label
	--
	SELECT kx_regconf FROM tstore.ns WHERE label=$1;
$f$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION tlib.set_regconf(anyelement,text) RETURNS regconfig AS $f$  --revisar usabilidade do anyelement
	SELECT  COALESCE( tlib.nsget_conf($1), tlib.lang2regconf($2) );
$f$ LANGUAGE SQL IMMUTABLE;

-- -- --

CREATE FUNCTION tlib.nsget_nsopt2int(JSONB) RETURNS int AS $f$
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
				WHEN 'string' THEN tlib.nsget_nsid(($1->>'ns')::text)
				ELSE NULL::int
			END;
		IF nsval IS NOT NULL THEN
			nsuse := true;
		END IF;
	END IF;
	RETURN CASE
		WHEN nsuse THEN nsval
		WHEN $1->'ns_mask' IS NOT NULL THEN ($1->>'ns_mask')::int -- same effect as 'ns'
		WHEN $1->'ns_basemask' IS NOT NULL THEN tlib.basemask($1->>'ns_basemask')
		WHEN $1->'ns_label' IS NOT NULL THEN tlib.nsget_nsid(($1->>'ns_label')::text)
		WHEN $1->'ns_count' IS NOT NULL THEN tlib.nsget_nsid(($1->>'ns_count')::int)
		ELSE NULL
	       END;
	END;
$f$ LANGUAGE PLpgSQL IMMUTABLE;



-- -- -- -- -- -- --
-- TSTORE TERM-RESOLVERS:

CREATE FUNCTION tlib.N2C_tab(
	--
	-- Returns de canonic term from a valid term of a namespace.
	-- Exs. SELECT *  FROM tlib.N2C_tab(' - USP - ','wayta-pt'::text,false);
	--      SELECT tlib.N2C_tab('puc-mg',tlib.nsget_nsid('wayta-code'),true);
	--
	text,   		-- 1. valid term
	int,     		-- 2. namespace MASK, ex. by tlib.basemask().
	boolean DEFAULT true,  	-- 3. exact (true) or apply normalization (false)
	int DEFAULT 1				-- 4. LIMIT  1, and ignore Id and fk_ns.
) RETURNS SETOF tstore.tab  AS $f$
	SELECT id, fk_ns as nsid, term_canonic::text, 100::int, is_canonic, fk_canonic, '{"sc_func":"exact"}'::jsonb
	FROM tstore.term_full
	WHERE (fk_ns&$2)::boolean  AND  CASE WHEN $3 THEN term=$1 ELSE term=tlib.normalizeterm($1) END
	LIMIT $4  -- or array_agg(id,fk_ns)
$f$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION tlib.N2C_tab(text,text,boolean DEFAULT true) RETURNS SETOF tstore.tab  AS $f$
	-- overloading, wrap for N2C_tab() and   basemask().
	SELECT tlib.N2C_tab($1, tlib.basemask($2), $3);
$f$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION tlib.N2id(text,int,boolean DEFAULT false) RETURNS int  AS $f$
	-- internal use in configs
	SELECT CASE WHEN is_canonic THEN id ELSE fk_canonic END
	FROM tstore.term
	WHERE (fk_ns&$2)::boolean  AND  CASE WHEN $3 THEN term=$1 ELSE term=tlib.normalizeterm($1) END
$f$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION tlib.N2C_tab(
	-- overloading, wrap for N2C_tab()
	JSONB
) RETURNS SETOF tstore.tab  AS $f$
DECLARE
	p JSONB;
BEGIN
	p  :=  tlib.jparams(
		$1,
		'{"lim":null,"osort":true,"otype":"l","qs_is_normalized":true}'::jsonb
	);
	RETURN QUERY SELECT * FROM tlib.N2C_tab( p->>'qs', tlib.nsget_nsopt2int(p), (p->>'qs_is_normalized')::boolean );
END;
$f$ LANGUAGE PLpgSQL IMMUTABLE;


CREATE FUNCTION tlib.N2C(
	-- Wrap for output as RPC.
	JSONB  -- see all valid params
) RETURNS JSONB AS $f$
	SELECT tlib.jrpc_ret(
		  jsonb_build_object(
			'items',CASE (tlib.jparams($1))->>'otype'
				WHEN 'o' THEN 	jsonb_object( array_agg(t.term), array_agg(t.score)::text[] ) -- revisar se pode usar int[]
				WHEN 'a' THEN 	jsonb_agg(to_jsonb(t.term))
				ELSE 		jsonb_agg(tlib.unpack(to_jsonb(t),'jetc'))
			END,
			'count', count(*),
			'sc_func',max(t.jetc->>'sc_func')
		  ),
		  ($1->>'id')::text
		)
	FROM tlib.N2C_tab($1) t;
$f$ LANGUAGE SQL IMMUTABLE;


-- -- --
-- N2Ns:

CREATE or replace FUNCTION tlib.N2Ns_tab(
	--
	-- Returns canonic (of any namespace) and all the synonyms of a valid term of a namespace/mask.
	-- Ex. SELECT * FROM tlib.N2Ns_tab(' - puc-mg - ',4,NULL,false);
	--
	text,            	-- 1. valid term
	int DEFAULT 1,     	-- 2. namespace MASK
	int DEFAULT NULL,       -- 3. Limit
	boolean DEFAULT true,	-- 4. exact (true) or apply normalization (false)
	boolean DEFAULT true	-- 5. (non-used, enforcing sort) to sort by ns, term
) RETURNS SETOF tstore.tab AS $f$
	-- TO DO: optimize (see explain) and simplify using tstore.term_full
	WITH can AS (
		SELECT CASE
			  WHEN is_canonic THEN s.id -- commum case, mais de 60% sao canonicos
			  ELSE (SELECT id FROM tstore.term_canonic t WHERE t.id=s.fk_canonic) -- caso nao-canonico
			END as canonic_id
		FROM tstore.term s
		WHERE (fk_ns&$2)::boolean  AND  CASE WHEN $4 THEN term=$1 ELSE term=tlib.normalizeterm($1) END
		LIMIT 1 -- danger, not works with homonyms
	)
	SELECT t.id, t.fk_ns as nsid, t.term, 100::int, is_canonic, fk_canonic, '{"sc_func":"exact"}'::jsonb
	FROM tstore.term t, can
	WHERE 	(t.id=can.canonic_id OR fk_canonic=can.canonic_id) -- link canonic
		AND (t.is_canonic OR (t.fk_ns&$2)::boolean)  -- restriction to mask-namespace
	ORDER BY t.fk_ns, t.term -- $5 future
	LIMIT $3
$f$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION tlib.N2Ns_tab(text,text,int DEFAULT NULL,boolean DEFAULT true,boolean DEFAULT true) RETURNS SETOF tstore.tab AS $f$
	-- Overload wrap for N2Ns_tab() and nsget_nsid().
	SELECT tlib.N2Ns_tab($1, tlib.nsget_nsid($2), $3, $4, $5);  -- old basemask(), prefer restrictive
$f$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION tlib.N2Ns_tab(
	-- Overload wrap for N2Ns_tab()
	JSONB
) RETURNS SETOF tstore.tab  AS $f$
DECLARE
	p JSONB;
BEGIN
	p  :=  tlib.jparams(
		$1,
		'{"lim":null,"osort":true,"otype":"l","qs_is_normalized":true}'::jsonb
	);
	RETURN QUERY SELECT *
	             FROM tlib.N2Ns_tab(
			p->>'qs', tlib.nsget_nsopt2int(p), (p->>'lim')::int,
			(p->>'qs_is_normalized')::boolean,  (p->>'osort')::boolean
		     );
END;
$f$ LANGUAGE PLpgSQL IMMUTABLE;

CREATE FUNCTION tlib.N2Ns(
	-- Wrap for N2Ns_tab() output as JSON-RPC.  See #SQL-STRUCTURE of tlib.N2C().
	JSONB  -- see all valid params
) RETURNS JSONB AS $f$
	SELECT CASE WHEN max(t.id)<0 THEN
		  tlib.jrpc_error(
			max(t.term),
			max(t.id),
			($1->>'id')::text
		  )
		ELSE tlib.jrpc_ret(
		  jsonb_build_object(
			'items',CASE (tlib.jparams($1))->>'otype'
				WHEN 'o' THEN 	jsonb_object( array_agg(t.term), array_agg(t.score)::text[] ) -- revisar se pode usar int[]
				WHEN 'a' THEN 	jsonb_agg(to_jsonb(t.term))
				ELSE 		jsonb_agg(tlib.unpack(to_jsonb(t),'jetc'))
			END,
			'count', count(*),
			'sc_max', max(t.score),
			'sc_func',max(t.jetc->>'sc_func'),
			'synonyms_count', sum((t.jetc->>'synonyms_count')::int)
		  ),
		  ($1->>'id')::text
		)
		END
	FROM tlib.N2Ns_tab($1) t;
$f$ LANGUAGE SQL IMMUTABLE;


-- -- -- -- -- -- -- --
-- TERM-SEARCH ENGINES:

CREATE FUNCTION tlib.search_tab(
	--
	--  Executes all search forms, by similar terms, and all output modes provided for the system.
	--  Debug with 'search-json'
	--  Namespace: use scalar for ready mask, or array of nscount for build mask.
	--  @DEFAULT-PARAMS "op": "=", "lim": 5, "sc_func": "dft", "metaphone": false, "sc_maxd": 100, "metaphone_len": 6, ...
	--
	JSONB -- 1. all input parameters.
) RETURNS SETOF tstore.tab AS $f$
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
	p := tlib.jparams($1, jsonb_build_object( -- all default values
		'op','=', 'lim',5, 'etc',1, 'sc_func','dft', 'sc_maxd',100, 'metaphone',false, 'metaphone_len',6,
		'qs_lang','pt', 'nsmask',255, 'debug',null
	));
	p_qs := tlib.normalizeterm(p->>'qs');
	p_nsmask := tlib.nsget_nsopt2int(p);

	IF p->>'debug'='search-json' THEN
		RAISE EXCEPTION 'DEBUG search-json: nsmask=%, qs="%", params=%', p_nsmask::text, p_qs, p;
	END IF;
	IF p_qs IS NULL OR char_length(p_qs)<2 THEN
	  RETURN QUERY SELECT -10::int, null::int, 'Empty or one-letter querystring'::text, NULL::int, NULL::boolean, NULL::int, NULL::jsonb;
	END IF;
	IF p_nsmask IS NULL OR p_nsmask=0 THEN
	  RETURN QUERY SELECT -11::int, null::int, 'NULL or invalid namespace'::text,     NULL::int, NULL::boolean, NULL::int, NULL::jsonb;
	END IF;

	p_scfunc := p->>'sc_func';
	jetc   :=   jsonb_build_object('sc_func', p->>'sc_func');   -- || other
	p_maxd :=   p->>'sc_maxd';  -- ::int
	p_lim  :=   p->>'lim';
	IF p->>'metaphone' THEN
		p_mlen := (p->>'metaphone_len')::int;
		CASE p->>'op'
		WHEN 'e','=' THEN  		-- exact
			RETURN QUERY SELECT t.id, t.fk_ns, t.term::text, tlib.score(p_qs, t.term,p_scfunc, p_maxd), t.is_canonic, t.fk_canonic, jetc
			FROM tstore.term t
			WHERE (t.fk_ns&p_nsmask)::boolean AND t.kx_metaphone = tlib.multimetaphone(p_qs,p_mlen,' ')
			ORDER BY 4 DESC, 3
			LIMIT p_lim;
		WHEN '%','p','s' THEN 	 	-- s'equence OR p'refix
			RETURN QUERY SELECT t.id, t.fk_ns, t.term::text, tlib.score(p_qs, t.term,p_scfunc, p_maxd), t.is_canonic, t.fk_canonic, jetc
			FROM tstore.term t
			WHERE (t.fk_ns&p_nsmask)::boolean AND t.kx_metaphone LIKE (
				CASE WHEN p->>'op'='p' THEN '' ELSE '%' END || tlib.multimetaphone(p_qs,p_mlen,'%') || '%'
			)
			ORDER BY 4 DESC, 3
			LIMIT p_lim;
		ELSE  				-- pending, needs also "free tsquery" in $2 for '!' use and complex expressions
			RETURN QUERY SELECT t.id, t.fk_ns, t.term::text, tlib.score(p_qs, t.term,p_scfunc, p_maxd), t.is_canonic, t.fk_canonic, jetc
			FROM tstore.term t
			WHERE (t.fk_ns&p_nsmask)::boolean AND to_tsvector('simple',t.kx_metaphone) @@ to_tsquery(
				'simple',
				tlib.multimetaphone(p_qs,p_mlen,p->>'op'::text)
			)
			ORDER BY 4 DESC, 3
			LIMIT p_lim;
		END CASE;

	ELSE CASE p->>'op'    			-- DIRECT TERMS:

		WHEN 'e', '=' THEN  		-- exact
			RETURN QUERY SELECT t.id, t.fk_ns, t.term::text, tlib.score(p_qs, t.term,p_scfunc, p_maxd), t.is_canonic, t.fk_canonic, jetc
			FROM tstore.term t
			WHERE (t.fk_ns&p_nsmask)::boolean AND t.term = p_qs
			ORDER BY 4 DESC, 3
			LIMIT p_lim;
		WHEN '%', 'p', 's' THEN  	-- 's'equence or 'p'refix
			RETURN QUERY SELECT t.id, t.fk_ns, t.term::text, tlib.score(p_qs, t.term,p_scfunc, p_maxd), t.is_canonic, t.fk_canonic, jetc
			FROM tstore.term t
			WHERE (t.fk_ns&p_nsmask)::boolean AND t.term LIKE (
				CASE WHEN  p->>'op'='p' THEN '' ELSE '%' END || replace(p_qs, ' ', '%')  || '%'
			)
			ORDER BY 4 DESC, 3
			LIMIT p_lim;
		ELSE				-- '&', '|', etc. resolved by tsquery.
			RETURN QUERY SELECT t.id, t.fk_ns, t.term::text, tlib.score(p_qs, t.term,p_scfunc, p_maxd), t.is_canonic, t.fk_canonic, jetc
			FROM tstore.term_ns t
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


CREATE FUNCTION tlib.search(
	--
	-- Wrap for output as JSON-RPC. Se #SQL-TEMPLATE of tlib.N2Ns().
	-- SELECT tlib.search('{"op":"%","qs":"embrapa","ns":"wayta-code","lim":5,"otype":"a"}'::jsonb);
	--
	JSONB  -- all valid params
) RETURNS JSONB AS $f$
	SELECT CASE WHEN max(t.id)<0 THEN
		  tlib.jrpc_error(
			max(t.term),
			max(t.id),
			($1->>'id')::text
		  )
		ELSE tlib.jrpc_ret(
		  jsonb_build_object(
			'items',CASE p.p->>'otype'
				WHEN 'o' THEN 	jsonb_object( array_agg(t.term), array_agg(t.score)::text[] ) -- revisar se pode usar int[]
				WHEN 'a' THEN 	jsonb_agg(to_jsonb(t.term))
				ELSE 		jsonb_agg(tlib.unpack(to_jsonb(t),'jetc'))
			END,
			'count', count(*),
			'sc_max', max(t.score),
			'sc_func',max(t.jetc->>'sc_func'),
			--'synonyms_count', sum((t.jetc->>'synonyms_count')::int),
			'op', max(p.p->>'op'),
			'lim', max(p.p->>'lim'),
			'metaphone', max(p.p->>'metaphone')
		  ),
		  ($1->>'id')::text
		)
		END
	FROM tlib.search_tab($1) t,
	     tlib.jparams($1, jsonb_build_object('op','=', 'lim',5, 'metaphone',false)) p(p)
	GROUP BY p.p;
$f$ LANGUAGE SQL IMMUTABLE;


----

CREATE FUNCTION tlib.search2c_tab(
	--
	-- tlib.search_tab() complement, to reduce the output to only canonic forms.
	--
	JSONB -- 1. all input parameters.
) RETURNS SETOF tstore.tab AS $f$
	SELECT 	max( COALESCE(s.fk_canonic,s.id) ) AS cid, -- the s.id is the canonic when c.term is null
		max(s.nsid) as nsid,        		-- certo é array_agg(distinct s.fk_ns)
		COALESCE(c.term,s.term) AS cterm, 	-- the s.term is the canonic when c.term is null
		max(s.score) as score,  	-- or first_value()
		true::boolean as is_canonic, 	-- all are canonic
		NULL::int as fk_canonic,  	-- all are null
		jsonb_build_object( 'sc_func',max(s.jetc->>'sc_func'), 'synonyms_count', count(*) )
	FROM tlib.search_tab(tlib.jparams($1) || jsonb_build_object('lim',NULL)) s
	     LEFT JOIN tstore.term_canonic c
	     ON c.id=s.fk_canonic
	GROUP BY cterm
	ORDER BY score DESC, cterm
	LIMIT (tlib.jparams($1,jsonb_build_object('lim',NULL))->>'lim')::int
$f$ LANGUAGE SQL IMMUTABLE;


CREATE FUNCTION tlib.search2c(
	-- Wrap for JSONB and outputs as JSON-RPC. See #SQL-structure tlib.N2Ns().
	JSONB  -- see all valid params
) RETURNS JSONB AS $f$
	SELECT CASE WHEN max(t.id)<0 THEN
		  tlib.jrpc_error(
			max(t.term),
			max(t.id),
			($1->>'id')::text
		  )
		ELSE tlib.jrpc_ret(
		  jsonb_build_object(
			'items',CASE p.p->>'otype'
				WHEN 'o' THEN 	jsonb_object( array_agg(t.term), array_agg(t.score)::text[] ) -- revisar se pode usar int[]
				WHEN 'a' THEN 	jsonb_agg(to_jsonb(t.term))
				ELSE 		jsonb_agg(tlib.unpack(to_jsonb(t),'jetc'))
			END,
			'count', count(*),
			'sc_max', max(t.score),
			'sc_func',max(t.jetc->>'sc_func'),
			'synonyms_count', sum((t.jetc->>'synonyms_count')::int),
			'op', max(p.p->>'op'),
			'lim', max(p.p->>'lim'),
			'metaphone', max(p.p->>'metaphone')
		  ),
		  ($1->>'id')::text
		)
		END
	FROM tlib.search2c_tab($1) t,
	     tlib.jparams($1,jsonb_build_object('op','=', 'lim',5, 'metaphone',false)) p(p)
	GROUP BY p.p;
$f$ LANGUAGE SQL IMMUTABLE;

---

CREATE FUNCTION tlib.find(
	--
	-- Find a term, or "nearest term", by an heuristic of search strategies.
	-- PS: only didactic illustration, it is not a good algorithm.
	--
	JSONB DEFAULT NULL -- input params
) RETURNS JSONB AS $f$
DECLARE
  p JSONB;
  nwords int;
  result JSONB;
BEGIN
	p := tlib.jparams( $1, '{"metaphone":false}'::jsonb );
	result := tlib.search( p || '{"op":"="}'::jsonb ); -- exact
	IF (result->'result'->>'count')::int >0 THEN  -- OR result->'error' IS NOT NULL
		RETURN result;
	END IF;
	SELECT 1 + char_length(x) - char_length(replace(x,' ','')) INTO nwords
	FROM tlib.multimetaphone(p->>'qs') t(x);
	IF nwords > 2 THEN
		result := tlib.search( p || '{"op":"p"}'::jsonb ); -- prefixed frag-words in offered order
		IF (result->'result'->>'count')::int >0 THEN  -- OR result->'error' IS NOT NULL
			RETURN result;
		END IF;
	END IF;
	result := tlib.search( p || '{"op":"&"}'::jsonb ); -- all words in any order
	IF (result->'result'->>'count')::int >0 THEN
		RETURN result;
	END IF;
	IF nwords > 1 OR char_length(trim(p->>'qs'))>5 THEN
		result := tlib.search( p || '{"op":"%"}'::jsonb ); -- all frag-words in offered order
		IF (result->'result'->>'n')::int >0 THEN
			RETURN result;
		END IF;
	END IF;

	p := tlib.jparams( $1, '{"metaphone":true}'::jsonb ); -- enforces metaphone
	result := tlib.search( p || '{"op":"="}'::jsonb );
	IF (result->'result'->>'count')::int >0 THEN
		RETURN result;
	END IF;
	IF nwords > 2 THEN
		result := tlib.search( p || '{"op":"p"}'::jsonb ); -- all frag-words in offered order
		IF (result->'result'->>'count')::int >0 THEN  -- OR result->'error' IS NOT NULL
			RETURN result;
		END IF;
	END IF;
	result := tlib.search( p || '{"op":"&"}'::jsonb ); -- all words in any order
	IF (result->'result'->>'count')::int >0 THEN
		RETURN result;
	END IF;
	RETURN tlib.search( p || '{"op":"%"}'::jsonb );
END;
$f$ LANGUAGE PLpgSQL IMMUTABLE;


CREATE FUNCTION tlib.find2c(
	--
	-- Same as find() but using search2c() into.
	--
	JSONB DEFAULT NULL -- input params
) RETURNS JSONB AS $f$
DECLARE
  p JSONB;
  nwords int;
  result JSONB;
BEGIN
	p := tlib.jparams( $1, '{"metaphone":false}'::jsonb );
	result := tlib.search2c( p || '{"op":"="}'::jsonb ); -- exact
	IF (result->'result'->>'count')::int >0 THEN  -- OR result->'error' IS NOT NULL
		RETURN result;
	END IF;
	SELECT 1 + char_length(x) - char_length(replace(x,' ','')) INTO nwords
	FROM tlib.multimetaphone(p->>'qs') t(x);
	IF nwords > 2 THEN
		result := tlib.search2c( p || '{"op":"p"}'::jsonb ); -- prefixed frag-words in offered order
		IF (result->'result'->>'count')::int >0 THEN  -- OR result->'error' IS NOT NULL
			RETURN result;
		END IF;
	END IF;
	result := tlib.search2c( p || '{"op":"&"}'::jsonb ); -- all words in any order
	IF (result->'result'->>'count')::int >0 THEN
		RETURN result;
	END IF;
	IF nwords > 1 OR char_length(trim(p->>'qs'))>5 THEN
		result := tlib.search2c( p || '{"op":"%"}'::jsonb ); -- all frag-words in offered order
		IF (result->'result'->>'n')::int >0 THEN
			RETURN result;
		END IF;
	END IF;

	p := tlib.jparams( $1, '{"metaphone":true}'::jsonb ); -- enforces metaphone
	result := tlib.search2c( p || '{"op":"="}'::jsonb );
	IF (result->'result'->>'count')::int >0 THEN
		RETURN result;
	END IF;
	IF nwords > 2 THEN
		result := tlib.search2c( p || '{"op":"p"}'::jsonb ); -- all frag-words in offered order
		IF (result->'result'->>'count')::int >0 THEN  -- OR result->'error' IS NOT NULL
			RETURN result;
		END IF;
	END IF;
	result := tlib.search2c( p || '{"op":"&"}'::jsonb ); -- all words in any order
	IF (result->'result'->>'count')::int >0 THEN
		RETURN result;
	END IF;
	RETURN tlib.search2c( p || '{"op":"%"}'::jsonb );
END;
$f$ LANGUAGE PLpgSQL IMMUTABLE;


-- -- -- -- -- -- -- --
-- -- -- -- -- -- -- --

CREATE FUNCTION tlib.export_j2regex1(
	--
	-- Export json for REGEX resolver type1
	-- BUG: not preserving ORDER, use TAB (record) output! and _tab variations
	--
	p_nsbase text,
	p_nsexclude text DEFAULT NULL,
	p_outpairs boolean DEFAULT false,
	p_use_suspect boolean DEFAULT true,
	p_check_canoniclink boolean DEFAULT true,
	p_use_length boolean DEFAULT true
) RETURNS jsonb AS $f$
SELECT jsonb_agg(jsonb_build_object(lang, list)) as jout  -- not jsonb for order preservation in p_outpairs=true
FROM (
	WITH items AS (
		SELECT tlib.nsid2lang(fk_ns) as lang, term, fk_canonic
		FROM tstore.term
		WHERE 	(CASE WHEN p_nsexclude IS NULL
							THEN fk_ns & tlib.basemask(p_nsbase)
							ELSE fk_ns & tlib.basemask(p_nsbase) & (~tlib.nsget_nsid(p_nsexclude))
							END
			)::boolean -- ns mask
			AND CASE WHEN p_use_suspect THEN NOT(is_suspect) ELSE  true END
			AND CASE WHEN p_check_canoniclink THEN fk_canonic IS NOT NULL ELSE  true END
			   -- equiv. AND NOT((NOT(is_canonic) AND fk_canonic  IS NULL))
			AND CASE WHEN p_use_length THEN char_length(term)>3 ELSE  true END
		ORDER BY fk_ns, char_length(term) desc, term
	) SELECT lang,
			CASE WHEN p_outpairs
				THEN jsonb_object( array_agg(term), array_agg(fk_canonic)::text[] )  -- not jsonb for order
				ELSE jsonb_agg(term)
			END  as list
	  FROM items
	  GROUP BY lang
 ) as t;
$f$ LANGUAGE SQL IMMUTABLE;

--- --- ---
--- ASSERT HELPER

CREATE FUNCTION tlib._assert(p_maxerrors int DEFAULT 3, p_caller_id text DEFAULT NULL) RETURNS jsonb AS $f$
	--
	-- Parse and run the asserts of tstore._assert table. See use at packLoad.
	-- Not use assert clause, it is not a local bug-check, http://www.postgresql.org/docs/9.5/static/plpgsql-errors-and-messages.html#PLPGSQL-STATEMENTS-ASSERT
	-- It is a "test-kit" as http://tsqlt.org or (as small as) http://www.bigsmoke.us/postgresql-unit-testing
	--  or debug http://stackoverflow.com/a/754570/287948
	--
	DECLARE
		r RECORD;
		out text;
		ret JSONB[] := array[]::JSONB[];
		nerrors int := 0;
		test boolean;
	BEGIN
	FOR r IN SELECT * FROM tstore._assert ORDER BY alabel,id  LOOP
		EXECUTE CASE WHEN lower(substring(trim(r.sql_select),1,6))='select' THEN '' ELSE 'SELECT ' END || r.sql_select
			INTO out;
		--IF r.result!=out THEN
		test := (r.result=out); -- (trim(r.result::text)=trim(out));
		ret := array_append( ret, jsonb_build_object(
			'sucess',test, 'id',r.id, 'alabel',r.alabel, 'sql_select',r.sql_select, 'result_expected', r.result, 'result_run',out
		));
		nerrors := nerrors + (not(test))::int;
		EXIT WHEN nerrors > p_maxerrors;
	END LOOP;
	RETURN tlib.jrpc_ret(
		jsonb_build_object(
			'items',  array_to_json(ret), --(SELECT to_jsonb(x) FROM unnest(ret) tt(x))
			'errors', nerrors
		),
		p_caller_id
	);
END;
$f$ LANGUAGE PLpgSQL;

CREATE FUNCTION tlib._assert_outextab(
	p_showsucess boolean DEFAULT false,
	p_maxerrors int DEFAULT 3,
	p_fulloutput boolean DEFAULT false,
	p_caller_id text DEFAULT NULL
) RETURNS text AS $f$
	WITH xerrors AS (
		SELECT (r->>'sucess')::boolean as sucess, (r->>'id')::int as id, r->>'alabel' as alabel,
			r->>'result_run' as result_run, r->>'sql_select' as qsql, r->>'result_expected' as result_expected
		FROM jsonb_array_elements((tlib._assert($2,$4)->'result')->'items') t(r)
	) SELECT array_to_string( array_agg(CASE
			WHEN sucess THEN alabel || ': sucess on id_assert ' || id
			ELSE alabel || ': ERROR on id_assert ' || id || CASE
			   WHEN p_fulloutput THEN E'\n\tSQL: ' || qsql || E'\n\tEXPECTED RESULT: ' || result_expected|| E'\n\tRESULT: ' || result_run
			   ELSE '' END
			END
	    ), E'\n', '-' ) AS txt
	  FROM xerrors
		WHERE p_showsucess OR NOT(sucess);
$f$ LANGUAGE SQL;
