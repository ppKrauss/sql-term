--
-- USE  psql -h localhost -U postgres postgres < examples/basic1.sql | more
--      psql -h localhost -U postgres postgres < examples/basic1.sql >  test.txt
--      diff test.txt examples/basic1.dump.txt
--

\qecho =================================================================
\qecho === Running: basic1 examples ====================================
\qecho =================================================================
\qecho 

\qecho '=== Namespaces: ================'
SELECT nscount, nsid,  label,  lang, is_base, fk_partof, kx_regconf 
FROM term1.ns ORDER BY 1;


\qecho '=== Testing mask performance and counting namespace of group: ==='
SELECT label, is_base, count(*) as n
FROM term1.term_ns -- view with Term and Namespace data
WHERE (fk_ns & term1.basemask('wayta-pt'))::boolean
GROUP BY 1,2 
ORDER BY 2 DESC,1;

\qecho '=== Only base-namespaces: ======================================='
SELECT label, is_base, count(*) as n
FROM term1.term_ns 
WHERE is_base
GROUP BY 1,2 
ORDER BY 2 DESC,1;


\qecho '=== Compare score functions: ===================================='
WITH word AS (
	SELECT 'foo bras'::text as x, cmp, greatest(8,char_length(cmp)) as len
	FROM unnest(array['foo bris','foo bri2','bar bras','bar bras 123','foo bras', 'foo']) t(cmp)
) SELECT x,cmp, term_lib.score(x,cmp,f), f, len
  FROM 	word w, unnest(array['std','levdiffperc','lev500']) f(f)
  ORDER BY f,3 DESC,1,2;

SELECT term_lib.ws_score('{"id":123,"params":{"a":"foo","b":"fox","sc_maxd":1}}'::jsonb);


\qecho '=== Scoring string comparisons: ================================='
\qecho '====== cuting by minimal score (30% of similarity), frist 2 from 3 comparisons:'
SELECT * FROM term_lib.score_pairs_tab('mamãe papai', array['mamãe papai','mama pai','mumye papy'],30,2);
SELECT * FROM term_lib.score_pairs_tab('foo', array['foo','bar','foos','fo','x'] );

\qecho '====== ... little more complex and exotic parameter variations:'
SELECT * FROM  term_lib.score_pairs_tab('foo', array['foo','foos bar 123','fo','x'],10,NULL,'levdiffperc',9,true);
SELECT * FROM  term_lib.score_pairs_tab('fox', array['foo','foos bar 123','fo','x'],10,NULL,'levdiffperc',9,true);
SELECT * FROM  term_lib.score_pairs_tab('fox', array['foo','foos bar 123','fo','x'],10,NULL,'levdiffperc',4,true);


\qecho '====== ... same in JSON and returning JSON:'
SELECT * FROM  term_lib.score_pairs(
  'fox', array['foo','foos bar 123','fo','x'],
  '{"id":3333,"cut":10,"lim":null,"sc_func":"levdiffperc","sc_maxd":4,"osort":false,"otype":"o"}'::jsonb
);  -- qs text, list text[], json 

SELECT * FROM  term_lib.score_pairs(
  '{"id":3333,"params":{"qs":"fox","list":["foo","foos bar 123","fo","x"],"cut":10,"lim":null,"sc_func":"levdiffperc","sc_maxd":4,"osort":false,"otype":"o"}}'::jsonb
);  -- json

\qecho '====== basic canonic name resolution:   ================================='
SELECT * FROM term1.N2C_tab('usp', 'wayta-pt'); 
SELECT term1.N2C_tab('usp', term1.nsget_nsid('wayta-pt') ) as qs_in_other_ns; 
SELECT term1.N2C_tab( 'usp', term1.nsget_nsid('wayta-code') );
SELECT term1.N2C_tab( 'ufscar', term1.nsget_nsid('wayta-code') ) as qs_not_valid_name;
SELECT term1.N2C_tab(' - USP - ',4,false) as a, term1.N2C_tab('puc-mg',term1.nsget_nsid('wayta-code'),true) as b;

\qecho '====== list synonyms:   ================================='
SELECT * FROM term1.N2Ns_tab('fucape', 4, true);  -- normalized input and knowed ns

SELECT * 
FROM term1.N2Ns_tab(' - puc-mg - ', 'wayta-code', false)  -- non-normalized input and ns by its label
WHERE nsid!=2;

\qecho '====== Using JSON in name resolution and list of synonyms:   =========='
SELECT term1.N2C('{"qs":"puc-mg","nsmask":30,"qs_is_normalized":true}'::jsonb);
SELECT term1.N2Ns('{"qs":"fucape","nsmask":4,"qs_is_normalized":true}'::jsonb);
SELECT term1.N2Ns('{"qs":"fucape","basemask":"wayta-pt","qs_is_normalized":true}'::jsonb);

\qecho '====== END ==========='

