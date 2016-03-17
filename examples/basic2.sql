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

\qecho '====== 10 top lexemes (more frequent words by its lexemes) of each namespace:   ==========='
WITH ns AS (SELECT nsid FROM term1.ns WHERE (nsid&term1.basemask('wayta-pt'))::boolean)
  SELECT word as lexeme, count(nsid) as tot_ns, sum(ndoc) as tot_ndoc, sum(nentry) as tot_entry
  FROM (
	  SELECT ns.nsid, t.*
	  FROM ns, 
	       ts_stat('SELECT kx_tsvector FROM term1.term WHERE (fk_ns&'||ns.nsid||')::boolean' ) t
  ) t2
  GROUP BY word
  ORDER BY 3 DESC,1
  LIMIT 10;

\qecho '====== Some namespace parameterization options:   =================='
select term1.nsget_nsopt2int('{"ns_basemask":"wayta-pt","etc":"etc"}'::jsonb);  -- a mask for all related namespaces
select term1.nsget_nsopt2int('{"ns":"wayta-code","etc":"etc"}'::jsonb);	-- the namespace code by its label
select term1.nsget_nsopt2int('{"ns":"waita-pt","etc":"etc"}'::jsonb); 	-- the label not exist

\qecho '====== Behaviour of each search() variation:   =================='
select * from term1.search_tab('{"op":"=","qs":"embrapa","ns":"wayta-code"}'::jsonb); --ok
select * from term1.search_tab('{"op":"=","qs":"embrapa","ns_basemask":"wayta-pt"}'::jsonb); --ok
select * from term1.search_tab('{"op":"=","qs":"embrapa","ns":"wayta-pt"}'::jsonb); --ok, is NULL

select * from term1.search_tab('{"op":"%","qs":"embrapa","ns":"wayta-code","lim":5}'::jsonb); --ok
select count(*) from term1.search_tab('{"op":"%","qs":"embrapa","ns":"wayta-code","lim":null}'::jsonb); --ok, 54
select count(*) from term1.search_tab('{"op":"%","qs":"embrapa","ns_basemask":"wayta-pt","lim":null}'::jsonb); --ok, 456

select count(*) from term1.search_tab('{"op":"p","qs":"embrapa","ns":"wayta-code","lim":null}'::jsonb); --ok, 47
select count(*) from term1.search_tab('{"op":"p","qs":"embrapa","ns_basemask":"wayta-pt","lim":null}'::jsonb); --ok, 364

select count(*) from term1.search_tab('{"op":"&","qs":"embrapa","ns":"wayta-code","lim":null}'::jsonb); --ok, 0, no exact term on wayta-code ns
select count(*) from term1.search_tab('{"op":"&","qs":"embrapa","ns_basemask":"wayta-pt","lim":null}'::jsonb); --ok, 391 on expanded ns mask


-- term_lib.score_pairs

-- SET client_min_messages = error;
-- DROP TABLE IF EXISTS example;
-- RESET client_min_messages;


