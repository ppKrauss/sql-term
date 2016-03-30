
---  ---  ---  ---  ---
---  ---  ---  ---  ---
--- TSTORE FINAL UPDATES (after basic prepare)
---  ---  ---  ---  ---

WITH uforms AS (
	SELECT DISTINCT  jinfo->>'form' AS form
	FROM tStore.term
	WHERE  fk_ns=tlib.nsget_nsid('wayta-pt') AND jinfo->>'form' IS NOT NULL
) SELECT  -- faz apenas insert condicional, o null força não-uso de update
	tstore.upsert( form , tlib.nsget_nsid('wayta-pt'), NULL, true, NULL::int)  as  id
	FROM uforms
	WHERE form>''; -- 314xx rows

UPDATE tStore.term
SET    is_canonic=true
FROM (
	SELECT DISTINCT  tlib.normalizeterm( jinfo->>'form' ) AS nform
	FROM tStore.term
	WHERE fk_ns=tlib.nsget_nsid('wayta-pt') AND jinfo->>'form' IS NOT NULL
) t
WHERE term.fk_ns=tlib.nsget_nsid('wayta-pt') AND t.nform=term.term; --31589 rows

DELETE from tStore.term where term like '% , , %'; -- correcting little bug

UPDATE tStore.term
SET    fk_canonic=t.cid
FROM (
	SELECT id as cid, term as cterm
	FROM tStore.term
	WHERE fk_ns=tlib.nsget_nsid('wayta-pt') AND is_canonic
) t
WHERE NOT(term.is_canonic) AND term.fk_ns=tlib.nsget_nsid('wayta-pt')
      AND t.cterm=tlib.normalizeterm( term.jinfo->>'form' )
; --9567 rows, marcou os termos normais com ponteiro para respectivo canônico; delete e fk_canonic

UPDATE tStore.term
SET fk_ns=tlib.nsget_nsid('wayta-code')
WHERE fk_ns=2 AND char_length(term)<20 AND position(' ' IN term)=0; -- ~520

UPDATE tStore.term
SET fk_ns=tlib.nsget_nsid('wayta-en')
WHERE (fk_ns=2) AND to_tsvector('simple',term) @@ to_tsquery('simple',
	'university|of|the|school|institute|technology|american|community|college|center|summit|system|health|sciences'
); -- ~9000

UPDATE tStore.term
SET fk_ns=tlib.nsget_nsid('wayta-es')
WHERE (fk_ns=2) AND (
	to_tsvector('simple',term) @@ to_tsquery('simple', 'universidad|del') -- 3088
	OR lower(jinfo->>'country') IN ('spain','mexico', 'cuba', 'colombia', 'venezuela', 'uruguay', 'peru')
	)
;


---  ---  ---  ---  ---
---  ---  ---  ---  ---
--- COUNTRY CODES


WITH t AS (SELECT DISTINCT  jinfo->>'iso3166_1_alpha_2' as term FROM tlib.tmp_codes ORDER BY 1)
SELECT tStore.upsert(term, tlib.nsget_nsid('country-code'),NULL::jsonb,true) FROM t;
-- define local canonics

SELECT tStore.upsert(
	jinfo->>'iso3166_1_alpha_3',
	tlib.nsget_nsid('country-code'),
	jinfo,
	false,
	tlib.N2id(jinfo->>'iso3166_1_alpha_2', tlib.nsget_nsid('country-code'), false)
)
FROM tlib.tmp_codes;  -- define iso3 non-canonics

SELECT tStore.upsert(
	jinfo->>'name',
	tlib.nsget_nsid('country-en'),
	jinfo,
	false,
	tlib.N2id(jinfo->>'iso3166_1_alpha_2', tlib.nsget_nsid('country-code'), false)
)
FROM tlib.tmp_codes;  -- define en

SELECT tStore.upsert(
	jinfo->>'name_fr',
	tlib.nsget_nsid('country-fr'),
	jinfo,
	false,
	tlib.N2id(jinfo->>'iso3166_1_alpha_2', tlib.nsget_nsid('country-code'), false)
)
FROM tlib.tmp_codes;  -- define fr

WITH t AS (SELECT DISTINCT  jinfo->>'iso2' as term FROM tlib.tmp_waytacountry ORDER BY 1)
SELECT tStore.upsert(term, tlib.nsget_nsid('country-code'),NULL::jsonb,true) FROM t;
-- define other local canonic, if exists (waytas)

SELECT tStore.upsert(  -- mix pt and other langs
	term,
	tlib.nsget_nsid('country-pt'),
	jinfo,
	false,
	tlib.N2id(jinfo->>'iso2', tlib.nsget_nsid('country-code'), false)
)
FROM tlib.tmp_waytacountry;
