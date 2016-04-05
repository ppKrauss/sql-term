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
	'{"source":"tmp_codes"}'::jsonb,
	true,			-- yes, is_canonic
	NULL::int,		-- no fk_canonic
	false,   -- is_suspect
	NULL   -- is_cult (codes are non-words... but are standards)
) FROM t;

--
-- Insert iso3 non-canonics
--
SELECT tStore.upsert(
	jinfo->>'iso3166_1_alpha_3',     -- iso3
	tlib.nsget_nsid('country-code'), -- into country-code namespace
	'{"source":"tmp_codes"}'::jsonb,
	false,		-- not iscanonic
	tlib.N2id(jinfo->>'iso3166_1_alpha_2', tlib.nsget_nsid('country-code'), false),  -- fk_canonic
	false,   -- is_suspect
	NULL   -- is_cult
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
	false,   -- is_suspect
	true   -- is_cult
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
	false,   -- is_suspect
	true   -- is_cult
)
FROM tlib.tmp_codes;


--- --- ---

--
-- Add more canonic names
--
SELECT tStore.upsert(
	iso_code,
	tlib.nsget_nsid('country-code'),
	'{"source":"tmp_codes2"}'::jsonb,
	true,		-- is canonic
	NULL::int,		-- no fk_canonic
	false  		-- is_suspect
	,NULL  -- is cult
)
FROM tlib.tmp_codes2;

--
-- Add other non-canonic names
--
SELECT tStore.upsert(
	jinfo->>'af', tlib.nsget_nsid('country-af'),
	'{"source":"tmp_codes2"}'::jsonb, false,		-- not iscanonic
	tlib.N2id(iso_code, tlib.nsget_nsid('country-code'), false),  -- fk_canonic
	false  		-- is_suspect
	,true  -- is cult
)
FROM tlib.tmp_codes2;

SELECT tStore.upsert(
	jinfo->>'es', tlib.nsget_nsid('country-es'),
	'{"source":"tmp_codes2"}'::jsonb, false,		-- not iscanonic
	tlib.N2id(iso_code, tlib.nsget_nsid('country-code'), false),  -- fk_canonic
	false  		-- is_suspect
	,true  -- is cult
)
FROM tlib.tmp_codes2;

SELECT tStore.upsert(
	jinfo->>'de', tlib.nsget_nsid('country-de'),
	'{"source":"tmp_codes2"}'::jsonb, false,		-- not iscanonic
	tlib.N2id(iso_code, tlib.nsget_nsid('country-code'), false),  -- fk_canonic
	false  		-- is_suspect
	,true  -- is cult
)
FROM tlib.tmp_codes2;

SELECT tStore.upsert(
	jinfo->>'it', tlib.nsget_nsid('country-it'),
	'{"source":"tmp_codes2"}'::jsonb, false,		-- not iscanonic
	tlib.N2id(iso_code, tlib.nsget_nsid('country-code'), false),  -- fk_canonic
	false  		-- is_suspect
	,true  -- is cult
)
FROM tlib.tmp_codes2;

SELECT tStore.upsert(
	jinfo->>'pt', tlib.nsget_nsid('country-pt'),
	'{"source":"tmp_codes2-ptBR"}'::jsonb, false,		-- not iscanonic
	tlib.N2id(iso_code, tlib.nsget_nsid('country-code'), false),  -- fk_canonic
	false  		-- is_suspect
	,true  -- is cult
)
FROM tlib.tmp_codes2;

SELECT tStore.upsert(
	jinfo->>'nl', tlib.nsget_nsid('country-nl'),
	'{"source":"tmp_codes2"}'::jsonb, false,		-- not iscanonic
	tlib.N2id(iso_code, tlib.nsget_nsid('country-code'), false),  -- fk_canonic
	false  		-- is_suspect
	,true  -- is cult
)
FROM tlib.tmp_codes2;


--- --- ---
----

--
-- Insert inferred English names country-en namespace.
--
SELECT tStore.upsert(term, tlib.nsget_nsid('country-en'), jinfo, false)
FROM tlib.tmp_waytacountry
WHERE to_tsvector('simple',term) @@ to_tsquery('simple',
	'republic|of|the|island|islands'
); -- ~..

--
-- Add all other non-canonic names
--
SELECT tStore.upsert(  -- mix pt and other langs
	term,
	tlib.nsget_nsid('country-pt'),
	'{"source":"waytacountry-badText"}'::jsonb,
	false,		-- not iscanonic
	tlib.N2id(jinfo->>'iso2', tlib.nsget_nsid('country-code'), false),  -- fk_canonic
	true  		-- is_suspect
)
FROM tlib.tmp_waytacountry
WHERE char_length(tlib.normalizeterm(term))>3; -- no codes
