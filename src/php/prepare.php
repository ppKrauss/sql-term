<?php
/**
 * Scans and charges CSV data to the SQL database.
 * php src/php/prepare.php
 */

include 'omLib.php';  // must be CONFIGURED for your database
$sqlMode = '1';
$verbose = 1; // 0,1 or 2



// // // // // // // // // //
// CONFIGS: (complement to omLib)
	$projects = [ 'carga'=>__DIR__ .'/../..' ];
	$reini = true;  // re-init all SQL structures of the project (drop and refresh schema)


// // // // //
// SQL PREPARE
$INI   = [ // prepare namespaces
	 "SELECT tStore.ns_upsert('test','pt','Test. Portuguese.')"
	,"SELECT tStore.ns_upsert('wayta-pt','pt','Wayta SciELO reference-dataset, for performance tests. Portuguese.')"
	,"SELECT tStore.ns_upsert('wayta-code','  ','Wayta SciELO reference-dataset, for performance tests. no-lang')"
	,"SELECT tStore.ns_upsert('wayta-en','en','Wayta SciELO reference-dataset, for performance tests. English.')"
	,"SELECT tStore.ns_upsert('wayta-es','es','Wayta SciELO reference-dataset, for performance tests. Spanish.')"
	,"UPDATE tStore.ns SET fk_partOf=tlib.nsget_nsid('wayta-pt') WHERE label!='wayta-pt' AND left(label,5)='wayta'"
];
$items = [
	'carga'=>[
		//array("INSERT INTO tStore.term(fk_ns,term) VALUES (1, :term::text)",
		// USE DIRECT insert 
		array("SELECT tStore.upsert(:term::text, tlib.nsget_nsid('test'))",
			'test.csv::strict'  // 305 itens
		),
		array("SELECT tStore.upsert(:term::text, tlib.nsget_nsid('wayta-pt'), :json_info::jsonb, false, NULL::int)",
			'normalized_aff.csv::strict' 
			// 43050 itens, 41795 normalized, 31589 canonic, mix of portuguese and english.
		),
	],
]; // itens of each project
$sql_delete = " -- prepare to full refresh of om.scheme
	DELETE FROM tStore.term;
";


// // // //
// INITS:

$db = new pdo($dsn,$PG_USER,$PG_PW);

if ($reini) {
	print "... RE-INITING SQL SCHEMAS with MODE$sqlMode ...\n";
	sql_exec($db,  file_get_contents($projects['carga']."/src/sql_mode$sqlMode/step1_libDefs.sql")  );
	sql_exec($db,  file_get_contents($projects['carga']."/src/sql_mode$sqlMode/step2_struct.sql")  );
	sql_exec($db,  file_get_contents($projects['carga']."/src/sql_mode$sqlMode/step3_lib.sql")  );
	print "... each complementar INI, \n";
	foreach($INI as $sql)
		sql_exec($db, $sql, "  .. ");
	print "\n";
}

sql_exec($db,$sql_delete," ...delete\n");

print "BEGIN processing (MODE$sqlMode) ...";

list($n2,$n,$msg) = jsonCsv_to_sql($items,$projects,$db, ',', 0, $verbose); 
// Wayta está injetando entidades XML onde deveriam ser UTF8, corrigir por parser geral o file.csv

if (1) {
	// Acrescenta canônicos (form) não-contemplados pela coluna term
	$nsbase='wayta-pt';
	sql_exec($db,"
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
	", "   ... CANONICOS-1, upsert e is_canonic\n");

	// marca os termos normais com ponteiro para respectivo canônico
	sql_exec($db,"
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
		WHERE NOT(term.is_canonic) AND term.fk_ns=tlib.nsget_nsid('$nsbase') AND t.cterm=tlib.normalizeterm( term.jinfo->>'form' ); --9567 rows
	", "   ... CANONICOS-2, delete e fk_canonic\n");
	sql_exec($db,"
 	  UPDATE tStore.term 
 	  SET fk_ns=tlib.nsget_nsid('wayta-code')
 	  WHERE fk_ns=2 AND char_length(term)<20 AND position(' ' IN term)=0; -- 517

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
		-- or-country enfoce but no big risk of mix like english, adds ~2200
	  );

	", "   ... CANONICOS-3, change namespaces as detected lang\n");
}

/* ASSERTS!  capturar json-assert por
	fazer diff de txt com saídas dos exemplos.
*/

print "$msg\n\nEND(tot $n lines scanned, $n2 lines used)\n";
?>

