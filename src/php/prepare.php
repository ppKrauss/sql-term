<?php
/**
 * Load CSV data (defined in datapackage.jsob) to the SQL database.
 * php src/php/prepare.php
 */

include 'packLoad.php';  // must be CONFIGURED for your database

// // // // // // // // // //
// CONFIGS: (complement to omLib)
	$basePath = realpath(__DIR__ .'/../..');
	$reini = true;  // re-init all SQL structures of the project (drop and refresh schema)
	$sqlMode = '1';
	$nsbase='wayta-pt';


// // // // //
// SQL PREPARE
$sqlIni   = [ // prepare namespaces
	 "::src/sql_mode$sqlMode/step1_libDefs.sql"
	,"::src/sql_mode$sqlMode/step2_struct.sql"
	,"::src/sql_mode$sqlMode/step3_lib.sql"

	,"SELECT tStore.ns_upsert('test','pt','Test. Portuguese.')"
	,"SELECT tStore.ns_upsert('wayta-pt','pt','Wayta SciELO reference-dataset, Portuguese.')"
	,"SELECT tStore.ns_upsert('wayta-code','  ','Wayta SciELO reference-dataset, no-lang')"
	,"SELECT tStore.ns_upsert('wayta-en','en','Wayta SciELO reference-dataset, English.')"
	,"SELECT tStore.ns_upsert('wayta-es','es','Wayta SciELO reference-dataset, Spanish.')"

	,"UPDATE tStore.ns SET fk_partOf=tlib.nsget_nsid('wayta-pt') WHERE label!='wayta-pt' AND left(label,5)='wayta'"
];

$sqlFinal   = [ // load target tables and update contents
	"SELECT tStore.upsert(term, tlib.nsget_nsid('test')) FROM tlib.tmp_test;"
 ,"SELECT tStore.upsert(term, tlib.nsget_nsid('wayta-pt'), jinfo, false, NULL::int) FROM tlib.tmp_waytaff"
	 // 43050 itens, 41795 normalized, 31589 canonic, mix of portuguese and english.
 ,"DROP TABLE tlib.tmp_test; DROP TABLE tlib.tmp_waytaff;"

 // UPDATES and data adaptations:  use external script and wayta-pt as constant
 ,"
	 WITH uforms AS (
		 SELECT DISTINCT  jinfo->>'form' AS form
		 FROM tStore.term
		 WHERE  fk_ns=tlib.nsget_nsid('$nsbase') AND jinfo->>'form' IS NOT NULL
	 ) SELECT  -- faz apenas insert condicional, o null força não-uso de update
		 tstore.upsert( form , tlib.nsget_nsid('$nsbase'), NULL, true, NULL::int)  as  id
		 FROM uforms
		 WHERE form>''; -- 314xx rows

	 UPDATE tStore.term
	 SET    is_canonic=true
	 FROM (
		 SELECT DISTINCT  tlib.normalizeterm( jinfo->>'form' ) AS nform
		 FROM tStore.term
		 WHERE fk_ns=tlib.nsget_nsid('$nsbase') AND jinfo->>'form' IS NOT NULL
	 ) t
	 WHERE term.fk_ns=tlib.nsget_nsid('$nsbase') AND t.nform=term.term; --31589 rows
 " //... CANONICOS-1, upsert e is_canonic
 ,"
	 -- GAMBI
	 DELETE from tStore.term where term like '% , , %'; -- bug sem traumas, para arrumar no futuro.
	 -- DO UPDATE pointing fk_canonic for each non-canonic. Pode dar erro de duplicação.
	 UPDATE tStore.term
	 SET    fk_canonic=t.cid
	 FROM (
		 SELECT id as cid, term as cterm
		 FROM tStore.term
		 WHERE fk_ns=tlib.nsget_nsid('$nsbase') AND is_canonic
	 ) t
	 WHERE NOT(term.is_canonic) AND term.fk_ns=tlib.nsget_nsid('$nsbase') AND t.cterm=tlib.normalizeterm( term.jinfo->>'form' );
 "  // --9567 rows, marcou os termos normais com ponteiro para respectivo canônico; delete e fk_canonic
 ,"
	 UPDATE tStore.term
	 SET fk_ns=tlib.nsget_nsid('wayta-code')
	 WHERE fk_ns=2 AND char_length(term)<20 AND position(' ' IN term)=0; -- 517

	 UPDATE tStore.term
	 SET fk_ns=tlib.nsget_nsid('wayta-en')
	 WHERE (fk_ns=2) AND to_tsvector('simple',term) @@ to_tsquery('simple',
	 'university|of|the|school|institute|technology|american|community|college|center|summit|system|health|sciences'
	 );
 " // -- ~9000
 ,"
	 UPDATE tStore.term
	 SET fk_ns=tlib.nsget_nsid('wayta-es')
	 WHERE (fk_ns=2) AND (
	 to_tsvector('simple',term) @@ to_tsquery('simple', 'universidad|del') -- 3088
	 OR lower(jinfo->>'country') IN ('spain','mexico', 'cuba', 'colombia', 'venezuela', 'uruguay', 'peru')
	 -- or-country enfoce but no big risk of mix like english, adds ~2200
	 );
 "
];


// // // // //
// MAKING DATA:

sql_prepare($sqlIni, "SQL SCHEMAS with MODE$sqlMode", $basePath, $reini);
if (!$reini)
	sql_prepare("DELETE FROM tstore.term; DELETE FROM tstore.ns;", "DELETING MAIN TABLES");

resourceLoad_run(
	$basePath
	,[ // itens of each resource defined in the datapackage.
		'test'=>[
				['prepare_auto', "tlib.tmp_test"],
			],
	  'normalized_aff'=>[
			['prepare_jsonb', "tlib.tmp_waytaff"],  //  term,jinfo
	  ],
	 ]
	, "(MODE$sqlMode)"
);

sql_prepare($sqlFinal, "SQL FINALIZATION");

//print "\nEND\n";
?>
