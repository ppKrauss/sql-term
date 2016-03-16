--
-- USE  %psql -h localhost -U postgres postgres < examples/basic2.sql | more
--

\qecho =================================================================
\qecho === Running: basic2 examples ====================================
\qecho =================================================================
\qecho 

\qecho '====== Terms, some samples and info retrieval:   ========================'
SELECT * FROM term1.term WHERE id>14036 LIMIT 3;
SELECT id, term, label, is_base FROM term1.term_ns WHERE id>14036 LIMIT 3;

SELECT id,term as canonic_term FROM term1.term_canonic WHERE id>14036 LIMIT 3;
SELECT id,term as synonym_term FROM term1.term_synonym WHERE id>14036 LIMIT 3;
SELECT id,term as synonym_term, term_canonic FROM term1.term_synonym_full WHERE id>14036 LIMIT 3;

\qecho '====== 10 more frequent words (lexemes):   ========================'
SELECT * 
FROM
  ts_stat('SELECT kx_tsvector FROM term1.term where fk_ns>1') -- 
ORDER BY ndoc DESC
LIMIT 10;


-- term_lib.score_pairs

-- SET client_min_messages = error;
-- DROP TABLE IF EXISTS example;
-- RESET client_min_messages;


