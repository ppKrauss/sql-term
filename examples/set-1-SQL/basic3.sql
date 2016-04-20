--
-- USE  %psql -h localhost -U postgres postgres < examples/basic3.sql | more
--

\qecho =================================================================
\qecho === Running: basic3 examples ====================================
\qecho =================================================================
\qecho 

-- select now();

\qecho '====== Behaviour of find():   =================='
select tlib.find('{"qs":"embrapa","ns":"wayta-code"}'::jsonb);
select tlib.find('{"qs":"embrapa","ns":"wayta-pt"}'::jsonb);
select tlib.find('{"qs":"embrapa","ns":"wayta-code","otype":"o"}'::jsonb);

\qecho '====== Behaviour of find2c():   ================='
select tlib.find2c('{"qs":"USP","ns":"wayta-code"}'::jsonb);
select tlib.find2c('{"qs":"embripo","ns":"wayta-code"}'::jsonb);
select tlib.find2c('{"qs":"embiripo","ns_basemask":"wayta-pt","lim":null}'::jsonb);

\qecho '====== Comparing  find() and find2c():   ========'
select tlib.find2c('{"qs":"universidade paulo","ns_basemask":"wayta-pt","lim":20,"otype":"a"}'::jsonb) AS "find2c(universidade paulo)";
select tlib.find2c('{"qs":"universidade paulo","ns_basemask":"wayta-pt","lim":20,"otype":"o"}'::jsonb) AS "find2c(universidade paulo)";

select tlib.find('{"qs":"universidade paulo","ns_basemask":"wayta-pt","lim":50,"otype":"o"}'::jsonb) AS "find(universidade paulo)";

select tlib.find('{"qs":"universidade paulo","ns_basemask":"wayta-pt","lim":50,"otype":"o","sc_func":"levdiffperc"}'::jsonb) AS "find(universidade paulo,levdiffperc)";


-- select now();

