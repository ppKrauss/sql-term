---  ---  ---  ---  ---
---  ---  ---  ---  ---
--- TSTORE FINAL UPDATES
--- NAMESPACE "WAYTA*", preparing and building from sources.
---  ---  ---  ---  ---


--
-- Insert inferred acronyms (one-word short length terms) into wayta-code namespace.
-- 
SELECT tStore.upsert(term, tlib.nsget_nsid('wayta-code'), jinfo, false) 
FROM tlib.tmp_waytaff
WHERE char_length(term)<15 AND position(' ' IN term)=0
; -- ~520 rows


--
-- Insert inferred English terms into wayta-en namespace.
-- 
SELECT tStore.upsert(term, tlib.nsget_nsid('wayta-en'), jinfo, false) 
FROM tlib.tmp_waytaff
WHERE to_tsvector('simple',term) @@ to_tsquery('simple',
	'university|of|the|school|institute|technology|american|community|college|center|summit|system|health|sciences'
); -- ~9000 rows

--
-- Insert inferred Spanish terms into wayta-es namespace.
-- 
SELECT tStore.upsert(term, tlib.nsget_nsid('wayta-es'), jinfo, false) 
FROM tlib.tmp_waytaff
WHERE to_tsvector('simple',term) @@ to_tsquery('simple', 'universidad|del') -- ~3100
      OR lower(jinfo->>'country') IN ('spain','mexico', 'cuba', 'colombia', 'venezuela', 'uruguay', 'peru')  -- ~4000
;

--
-- Set as canonic all that was a form.
-- 
WITH uforms AS (
	SELECT DISTINCT  tlib.normalizeterm(jinfo->>'form') AS form
	FROM  tlib.tmp_waytaff
) UPDATE tstore.term 
  SET    is_canonic = true
  FROM uforms 
  WHERE (fk_ns&tlib.basemask('wayta-pt'))::boolean AND uforms.form=term.term
; -- ~11300 rows


--
-- Insert (with no extra info) as canonic portuguese all other forms.
-- 
WITH uforms AS (
	SELECT DISTINCT  tlib.normalizeterm(jinfo->>'form') AS form
	FROM  tlib.tmp_waytaff
	WHERE  tlib.normalizeterm(jinfo->>'form')!=tlib.normalizeterm(term)
) SELECT tStore.upsert(form, tlib.nsget_nsid('wayta-pt'), NULL, true) 
  FROM uforms
  WHERE form NOT IN (SELECT term FROM tstore.term WHERE (fk_ns&tlib.basemask('wayta-pt'))::boolean)
; -- ~1100 rows

--
-- Insert (with JSON) as canonic portuguese all other forms.
-- 
WITH uforms AS (
	SELECT  tlib.normalizeterm(jinfo->>'form') AS form, jinfo
	FROM  tlib.tmp_waytaff

) SELECT tStore.upsert(form, tlib.nsget_nsid('wayta-pt'), jinfo, true) 
  FROM uforms
  WHERE form NOT IN (SELECT term FROM tstore.term WHERE (fk_ns&tlib.basemask('wayta-pt'))::boolean)
; -- ~19000 rows

DELETE from tStore.term where term like '% , , %'; -- correcting little bug

--
-- Link normal terms to its canonics.
-- 
UPDATE tstore.term 
SET fk_canonic = c.id 
FROM tstore.term_canonic as c
WHERE (term.fk_ns&tlib.basemask('wayta-pt'))::boolean
      AND NOT(term.is_canonic) AND term.fk_canonic IS NULL AND c.id!=term.id 
      AND tlib.normalizeterm(term.jinfo->>'form')=c.term
;  -- ~4000 rows


