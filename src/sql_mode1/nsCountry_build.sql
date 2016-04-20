---  ---  ---  ---  ---
---  ---  ---  ---  ---
--- TSTORE FINAL UPDATES
--- NAMESPACE "COUNTRY*", preparing and building from sources.

--
-- Insert canonics into country-code namespace.
--
WITH t AS (SELECT DISTINCT  jinfo->>'iso3166_1_alpha_2' as iso2 FROM tlib.tmp_codes ORDER BY 1)
SELECT tStore.upsert(
	iso2, 			-- the canonic term (a 2-letter ISO abbrev)
	tlib.nsget_nsid('country-code'), -- into country-code namespace
	NULL::jsonb,
	true,			-- yes, is_canonic
	NULL::int,		-- no fk_canonic
	false   -- is_suspect
	,NULL   -- is_cult (codes are non-words... but are standards)
	,'iso3166-1-alpha-2'::text
) FROM t;

--
-- Insert iso3 non-canonics
--
SELECT tStore.upsert(
	jinfo->>'iso3166_1_alpha_3',     -- iso3
	tlib.nsget_nsid('country-code'), -- into country-code namespace
	NULL::jsonb,
	false,		-- not iscanonic
	tlib.N2id(jinfo->>'iso3166_1_alpha_2', tlib.nsget_nsid('country-code'), false)  -- fk_canonic
	,false   -- is_suspect
	,NULL   -- is_cult
	,'iso3166-1-alpha-3'
)
FROM tlib.tmp_codes;

--
-- Insert English names as non-canonics
--
SELECT tStore.upsert(
	name,			-- english name of country
	tlib.nsget_nsid('country-en'),	-- into country-en namespace
	'{"source":"tmp_codes"}'::jsonb,
	false,		-- not iscanonic
	tlib.N2id(jinfo->>'iso3166_1_alpha_2', tlib.nsget_nsid('country-code'), false),  -- fk_canonic
	false   -- is_suspect
	,true   -- is_cult
	,'country-codes'::text
)
FROM tlib.tmp_codes;


--
-- Insert Franch names as non-canonics
--
SELECT tStore.upsert(
	jinfo->>'name_fr',		-- franch name of country
	tlib.nsget_nsid('country-fr'),	-- into country-fr namespace
	'{"source":"tmp_codes"}'::jsonb,
	false,		-- not iscanonic
	tlib.N2id(jinfo->>'iso3166_1_alpha_2', tlib.nsget_nsid('country-code'), false),  -- fk_canonic
	false   -- is_suspect
	,true   -- is_cult
	,'country-codes'::text
)
FROM tlib.tmp_codes;


--- --- --- ---
/*
	-- no dataset, KEELING, malvinas e vaticano são opcionais entre parentesis.. Todavia Congo tem abrev (DRC) ou (RDC)
	-- importante é remover na oficial ... excluir depois menos de 4 letras e palavra republic ou "republic of" sozinhas

	--- A virgula estabelece separador 'do' 'de'  etc. assim como inversão de ordem.
	SELECT *
	FROM tstore.term
	WHERE 	(fk_ns & tlib.basemask('country-code') & (~tlib.nsget_nsid('country-code')))::boolean -- ns mask
		AND NOT(is_suspect)
		AND fk_canonic IS NOT NULL -- equiv. AND NOT((NOT(is_canonic) AND fk_canonic  IS NULL))
		AND char_length(term)>3
	ORDER BY fk_ns, char_length(term) desc, term
;

*/
-------------

--
-- Add more canonic names
--
SELECT tStore.upsert(
	iso_code,
	tlib.nsget_nsid('country-code'),
	NULL::jsonb,
	true,		-- is canonic
	NULL::int,		-- no fk_canonic
	false  		-- is_suspect
	,NULL  -- is cult
	,'iso3166-1-alpha-2'::text
)
FROM tlib.tmp_codes2;


--
-- More non-canonic names (upsert ignore when same)
--
SELECT tStore.upsert(
	regexp_replace(jinfo->>'en', '\s*\([^\)]+\)\s*', ' ', 'g'),
	tlib.nsget_nsid('country-en'),
	NULL::jsonb, false,		-- not iscanonic
	tlib.N2id(iso_code, tlib.nsget_nsid('country-code'), false),  -- fk_canonic
	false  		-- is_suspect
	,true  -- is cult
	,'country-names-multilang'
)
FROM tlib.tmp_codes2;

SELECT tStore.upsert(
	regexp_replace(jinfo->>'fr', '\s*\([^\)]+\)\s*', ' ', 'g'),
	tlib.nsget_nsid('country-fr'),
	NULL::jsonb, false,		-- not iscanonic
	tlib.N2id(iso_code, tlib.nsget_nsid('country-code'), false),  -- fk_canonic
	false  		-- is_suspect
	,true  -- is cult
	,'country-names-multilang'::text
)
FROM tlib.tmp_codes2;

--
-- Add other non-canonic names
--
SELECT tStore.upsert(
	regexp_replace(jinfo->>'af', '\s*\([^\)]+\)\s*', ' ', 'g'),
	tlib.nsget_nsid('country-af'),
	NULL::jsonb, false,		-- not iscanonic
	tlib.N2id(iso_code, tlib.nsget_nsid('country-code'), false),  -- fk_canonic
	false  		-- is_suspect
	,true  -- is cult
	,'country-names-multilang'::text
)
FROM tlib.tmp_codes2;

SELECT tStore.upsert(
	regexp_replace(jinfo->>'es', '\s*\([^\)]+\)\s*', ' ', 'g'),
	tlib.nsget_nsid('country-es'),
	NULL::jsonb, false,		-- not iscanonic
	tlib.N2id(iso_code, tlib.nsget_nsid('country-code'), false),  -- fk_canonic
	false  		-- is_suspect
	,true  -- is cult
	,'country-names-multilang'::text
)
FROM tlib.tmp_codes2;

SELECT tStore.upsert(
	regexp_replace(jinfo->>'de', '\s*\([^\)]+\)\s*', ' ', 'g'),
	tlib.nsget_nsid('country-de'),
	NULL::jsonb, false,		-- not iscanonic
	tlib.N2id(iso_code, tlib.nsget_nsid('country-code'), false),  -- fk_canonic
	false  		-- is_suspect
	,true  -- is cult
	,'country-names-multilang'::text
)
FROM tlib.tmp_codes2;

SELECT tStore.upsert(
	regexp_replace(jinfo->>'it', '\s*\([^\)]+\)\s*', ' ', 'g'),
	tlib.nsget_nsid('country-it'),
	NULL::jsonb, false,		-- not iscanonic
	tlib.N2id(iso_code, tlib.nsget_nsid('country-code'), false),  -- fk_canonic
	false  		-- is_suspect
	,true  -- is cult
	,'country-names-multilang'::text
)
FROM tlib.tmp_codes2;

SELECT tStore.upsert(
	regexp_replace(jinfo->>'pt', '\s*\([^\)]+\)\s*', ' ', 'g'),
	tlib.nsget_nsid('country-pt'),
	NULL::jsonb, false,		-- not iscanonic
	tlib.N2id(iso_code, tlib.nsget_nsid('country-code'), false),  -- fk_canonic
	false  		-- is_suspect
	,true  -- is cult
	,'country-names-multilang'::text
)
FROM tlib.tmp_codes2;

SELECT tStore.upsert(
	regexp_replace(jinfo->>'nl', '\s*\([^\)]+\)\s*', ' ', 'g'),
	tlib.nsget_nsid('country-nl'),
	NULL::jsonb, false,		-- not iscanonic
	tlib.N2id(iso_code, tlib.nsget_nsid('country-code'), false),  -- fk_canonic
	false  		-- is_suspect
	,true  -- is cult
	,'country-names-multilang'::text
)
FROM tlib.tmp_codes2;

--- --- ---
--- --- ---

--
-- Insert inferred English names country-en namespace.
--
SELECT tStore.upsert(
		term,
		tlib.nsget_nsid('country-en'),
		jinfo,
		false,		-- not iscanonic
		tlib.N2id(jinfo->>'iso2', tlib.nsget_nsid('country-code'), false)  -- fk_canonic
		,true
		,false
		,'normalized_country'
)
FROM tlib.tmp_waytacountry
WHERE to_tsvector('simple',term) @@ to_tsquery('simple',
	'republic|of|the|island|islands'
);

--
-- Add all other non-canonic names
--
SELECT tStore.upsert(  -- mix pt and other langs
	term,
	tlib.nsget_nsid('country-pt'),
	'{"quali":"badText"}'::jsonb,
	false,		-- not iscanonic
	tlib.N2id(jinfo->>'iso2', tlib.nsget_nsid('country-code'), false)  -- fk_canonic
	,true  		-- is_suspect
	,false
	,'normalized_country'
)
FROM tlib.tmp_waytacountry
WHERE char_length(tlib.normalizeterm(term))>3; -- no codes

--
-- Minor corrections of suspects
--
UPDATE tstore.term
SET is_cult=true, is_suspect=false
WHERE term IN ('principado de andorra', 'timor leste', 'bósnia-herzegovina', 'camarões', 'república popular da china', 'barcelona', 'são cristóvão e névis', 'coréia do norte', 'coréia do sul', 'macedônia', 'papua nova guiné')
;  -- was valids
DELETE FROM tstore.term WHERE term IN ('bélgica.', 'cánada.' , 'republica de panamá.'); -- like '%.' not used
