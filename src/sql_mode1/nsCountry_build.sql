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
	NULL::jsonb,		-- no extra info
	true,			-- yes, is_canonic
	NULL::int		-- no fk_canonic
) FROM t;

--
-- Insert iso3 non-canonics
--
SELECT tStore.upsert(
	jinfo->>'iso3166_1_alpha_3',     -- iso3
	tlib.nsget_nsid('country-code'), -- into country-code namespace
	jinfo,
	false,		-- not iscanonic
	tlib.N2id(jinfo->>'iso3166_1_alpha_2', tlib.nsget_nsid('country-code'), false)  -- fk_canonic
)
FROM tlib.tmp_codes;

--
-- Insert English names as non-canonics
--
SELECT tStore.upsert(
	jinfo->>'name',			-- english name of country 
	tlib.nsget_nsid('country-en'),	-- into country-en namespace
	jinfo,
	false,		-- not iscanonic
	tlib.N2id(jinfo->>'iso3166_1_alpha_2', tlib.nsget_nsid('country-code'), false)  -- fk_canonic
)
FROM tlib.tmp_codes;

--
-- Insert Franch names as non-canonics
--
SELECT tStore.upsert(
	jinfo->>'name_fr',		-- franch name of country 
	tlib.nsget_nsid('country-fr'),	-- into country-fr namespace
	jinfo,
	false,		-- not iscanonic
	tlib.N2id(jinfo->>'iso3166_1_alpha_2', tlib.nsget_nsid('country-code'), false)  -- fk_canonic
)
FROM tlib.tmp_codes;


--
-- Add other canonic, if exists (waytas)
-- 
WITH t AS (SELECT DISTINCT  jinfo->>'iso2' as term FROM tlib.tmp_waytacountry ORDER BY 1)
SELECT tStore.upsert(term, tlib.nsget_nsid('country-code'),NULL::jsonb,true) 
FROM t WHERE term NOT IN (SELECT term FROM tStore.term_canonic);


--
-- Add all other non-canonic names
-- 
SELECT tStore.upsert(  -- mix pt and other langs
	term,
	tlib.nsget_nsid('country-pt'),
	jinfo,
	false,		-- not iscanonic
	tlib.N2id(jinfo->>'iso2', tlib.nsget_nsid('country-code'), false)  -- fk_canonic
)
FROM tlib.tmp_waytacountry;



