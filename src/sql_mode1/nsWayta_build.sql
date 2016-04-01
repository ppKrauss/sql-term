---  ---  ---  ---  ---
---  ---  ---  ---  ---
--- TSTORE FINAL UPDATES
--- NAMESPACE "WAYTA*", preparing and building from sources.
---  ---  ---  ---  ---

-- FALTA simplificar para ir inserindo direto, sem tantos updates

--
-- Insert all terms as non-canonic.
-- 
SELECT tStore.upsert(term, tlib.nsget_nsid('wayta-pt'), jinfo, false) 
FROM tlib.tmp_waytaff
; -- 43050 itens, 41795 normalized, 31589 canonic, mix of portuguese and english.

DELETE from tStore.term where term like '% , , %'; -- correcting little bug

--
-- Adds residual canonic terms, that occurs only as Wayta's form.
-- 
WITH uforms AS (
	SELECT DISTINCT  jinfo->>'form' AS form
	FROM tStore.term
	WHERE  fk_ns=tlib.nsget_nsid('wayta-pt') AND jinfo->>'form' IS NOT NULL
) SELECT  -- faz apenas insert condicional, o null força não-uso de update
	tstore.upsert( form , tlib.nsget_nsid('wayta-pt'), NULL, true, NULL::int)  as  id
	FROM uforms
	WHERE form>''
; -- ~31400 rows

--
-- Set canonic terms.
-- 
UPDATE tStore.term
SET    is_canonic=true
FROM (
	SELECT DISTINCT  tlib.normalizeterm( jinfo->>'form' ) AS nform
	FROM tStore.term
	WHERE fk_ns=tlib.nsget_nsid('wayta-pt') AND jinfo->>'form' IS NOT NULL
) t
WHERE term.fk_ns=tlib.nsget_nsid('wayta-pt') AND t.nform=term.term
; --31589 rows

--
-- Set link-to-its-canonic in normal terms.
-- 
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

--
-- Change namespace (to wayta-code) of one-word short length terms. (inferred acronyms)
-- 
UPDATE tStore.term
SET fk_ns=tlib.nsget_nsid('wayta-code')
WHERE fk_ns=tlib.nsget_nsid('wayta-pt') AND char_length(term)<20 AND position(' ' IN term)=0
; -- ~520 rows

--
-- Change namespace (to wayta-en) of inferred English terms.
-- 
UPDATE tStore.term
SET fk_ns=tlib.nsget_nsid('wayta-en')
WHERE (fk_ns=tlib.nsget_nsid('wayta-pt')) AND to_tsvector('simple',term) @@ to_tsquery('simple',
	'university|of|the|school|institute|technology|american|community|college|center|summit|system|health|sciences'
); -- ~9000

--
-- Change namespace (to wayta-es) of inferred Spanish terms.
-- 
UPDATE tStore.term
SET fk_ns=tlib.nsget_nsid('wayta-es')
WHERE (fk_ns=tlib.nsget_nsid('wayta-pt')) AND (
	to_tsvector('simple',term) @@ to_tsquery('simple', 'universidad|del') -- 3088
	OR lower(jinfo->>'country') IN ('spain','mexico', 'cuba', 'colombia', 'venezuela', 'uruguay', 'peru')  -- more ~4000
);

