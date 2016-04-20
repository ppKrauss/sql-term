--
-- USE  %psql -h localhost -U postgres postgres < examples/basic2.sql | more
--

\qecho =================================================================
\qecho === Running: basic2 examples ====================================
\qecho =================================================================
\qecho

\qecho '====== Terms, some samples and info retrieval:   ========================'
SELECT * FROM tstore.term WHERE term>'m' LIMIT 3;
SELECT id, term, label, is_base FROM tstore.term_ns WHERE term>'m' LIMIT 3;

SELECT id,term as canonic_term FROM tstore.term_canonic WHERE term>'m' LIMIT 3;
SELECT id,term as synonym_term FROM tstore.term_synonym WHERE term>'m' LIMIT 3;
SELECT id,term as synonym_term, term_canonic FROM tstore.term_synonym_full WHERE term>'m' LIMIT 3;

\qecho '====== 10 top lexemes (more frequent words by its lexemes) of each namespace (of wayta-*):   ==========='
WITH xns AS (SELECT nsid FROM tstore.ns WHERE (nsid&tlib.basemask('wayta-pt'))::boolean)
  SELECT word as lexeme, count(nsid) as tot_ns, sum(ndoc) as tot_ndoc, sum(nentry) as tot_entry
  FROM (
	  SELECT xns.nsid, t.*
	  FROM xns,
	       ts_stat('SELECT kx_tsvector FROM tstore.term WHERE fk_ns='||xns.nsid ) t  -- ou (fk_ns&'||xns.nsid||')::boolean
  ) t2
  GROUP BY word
  ORDER BY 3 DESC,1
  LIMIT 10;


\qecho '====== Some namespace parameterization options:   ==============='
select tlib.nsget_nsopt2int('{"ns_basemask":"wayta-pt","etc":"etc"}'::jsonb);  -- a mask for all related namespaces
select tlib.nsget_nsopt2int('{"ns":"wayta-code","etc":"etc"}'::jsonb);	-- the namespace code by its label
select tlib.nsget_nsopt2int('{"ns":"waita-pt","etc":"etc"}'::jsonb); 	-- the label not exist

\qecho '====== Behaviour of each search_tab() variation:   =================='
select * from tlib.search_tab('{"op":"=","qs":"embrapa","ns":"wayta-code"}'::jsonb); --ok
select * from tlib.search_tab('{"op":"=","qs":"embrapa","ns_basemask":"wayta-pt"}'::jsonb); --ok
select * from tlib.search_tab('{"op":"=","qs":"embrapa","ns":"wayta-pt"}'::jsonb); --ok, is NULL

select * from tlib.search_tab('{"op":"%","qs":"embrapa","ns":"wayta-code","lim":5}'::jsonb); --ok
select count(*) from tlib.search_tab('{"op":"%","qs":"embrapa","ns":"wayta-code","lim":null}'::jsonb); --ok, 54
select count(*) from tlib.search_tab('{"op":"%","qs":"embrapa","ns_basemask":"wayta-pt","lim":null}'::jsonb); --ok, 456

select count(*) from tlib.search_tab('{"op":"p","qs":"embrapa","ns":"wayta-code","lim":null}'::jsonb); --ok, 47
select count(*) from tlib.search_tab('{"op":"p","qs":"embrapa","ns_basemask":"wayta-pt","lim":null}'::jsonb); --ok, 364

select count(*) from tlib.search_tab('{"op":"&","qs":"embrapa","ns":"wayta-code","lim":null}'::jsonb); --ok, 0, no exact term on wayta-code ns
select count(*) from tlib.search_tab('{"op":"&","qs":"embrapa","ns_basemask":"wayta-pt","lim":null}'::jsonb); --ok, 391 on expanded ns mask

\qecho '====== Behaviour of each search_tab() on Metaphone variations:   ===='
select * from tlib.search_tab('{"op":"=","qs":"embripo","ns":"wayta-code","metaphone":true}'::jsonb) as "with Metaphone"; --ok
select * from tlib.search_tab('{"op":"=","qs":"embripo","ns":"wayta-code","metaphone":false}'::jsonb) as "without Metaphone"; --ok

select * from tlib.search_tab('{"op":"=","qs":"embiripo","ns_basemask":"wayta-pt","metaphone":true}'::jsonb);

select * from tlib.search_tab('{"op":"%","qs":"embiripo","ns":"wayta-code","lim":5,"metaphone":true}'::jsonb);
select count(*) from tlib.search_tab('{"op":"%","qs":"embiripo","ns":"wayta-code","lim":null,"metaphone":true}'::jsonb);
select count(*) from tlib.search_tab('{"op":"%","qs":"embiripo","ns_basemask":"wayta-pt","lim":null,"metaphone":true}'::jsonb);

select count(*) from tlib.search_tab('{"op":"p","qs":"embiripo","ns":"wayta-code","lim":null,"metaphone":true}'::jsonb);
select count(*) from tlib.search_tab('{"op":"p","qs":"embiripo","ns_basemask":"wayta-pt","lim":null,"metaphone":true}'::jsonb);

select count(*) from tlib.search_tab('{"op":"&","qs":"embiripo","ns":"wayta-code","lim":null,"metaphone":true}'::jsonb);
select count(*) from tlib.search_tab('{"op":"&","qs":"embiripo","ns_basemask":"wayta-pt","lim":null,"metaphone":true}'::jsonb);

\qecho '====== Behaviour of each search2c_tab(), search-to-canonic variations:   =='
select * from tlib.search_tab('{"op":"=","qs":"usp","ns":"wayta-code","metaphone":true}'::jsonb); -- "with Metaphone"
select * from tlib.search2c_tab('{"op":"=","qs":"usp","ns":"wayta-code","metaphone":true}'::jsonb); -- "Metaphones to canonic";

select * from tlib.search2c_tab('{"op":"=","qs":"embiripo","ns_basemask":"wayta-pt","metaphone":true}'::jsonb);

select * from tlib.search2c_tab('{"op":"%","qs":"embiripo","ns":"wayta-code","lim":5,"metaphone":true}'::jsonb);
select count(*) from tlib.search2c_tab('{"op":"%","qs":"embiripo","ns":"wayta-code","lim":null,"metaphone":true}'::jsonb);
select count(*) from tlib.search2c_tab('{"op":"%","qs":"embiripo","ns_basemask":"wayta-pt","lim":null,"metaphone":true}'::jsonb);

select count(*) from tlib.search2c_tab('{"op":"p","qs":"embiripo","ns":"wayta-code","lim":null,"metaphone":true}'::jsonb);

select count(*) from tlib.search2c_tab('{"op":"&","qs":"embiripo","ns":"wayta-code","lim":null,"metaphone":true}'::jsonb);


\qecho '====== Using search() and to search2c() illustrate complete JSON i/o   ===='
select tlib.search('{"id":123,"op":"=","qs":"embrapa","ns":"wayta-code","lim":1,"otype":"l"}'::jsonb);
select tlib.search('{"id":123,"op":"p","qs":"embrapa","ns":"wayta-code","lim":2,"otype":"o"}'::jsonb);
select tlib.search('{"id":123,"op":"&","qs":"embrapa","ns":"wayta-code","lim":2,"otype":"o"}'::jsonb);

select tlib.search2c('{"id":123,"op":"%","qs":"usspi","ns":"wayta-code","lim":5,"metaphone":true,"otype":"o"}'::jsonb);
select tlib.search2c('{"id":123,"op":"%","qs":"usspi","ns":"wayta-code","lim":5,"metaphone":false,"otype":"o"}'::jsonb);

-- term_lib.score_pairs

-- SET client_min_messages = error;
-- DROP TABLE IF EXISTS example;
-- RESET client_min_messages;

\qecho '====== The source/namespace distribution   ===='
select tlib.nsid2label(fk_ns) as namespace, array_distinct(array_agg(s.name)) as sources, count(*) as n
from tstore.term  t INNER JOIN tstore.source s ON fk_source @> ARRAY[s.id]
group by 1,fk_source
order by 1,3;
-- check stable terms by ex. SELECT term FROM tstore.term WHERE fk_source='{2,3,4}'::int[];
