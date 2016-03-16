<?php
/**
 * Scans and charges CSV data to the SQL database.
 * See also scripts at "ini.sql" (run it first with psql<ini.sql).
 * php openness-metrics/src/php/ini.php
 */

include 'omLib.php';  // must be CONFIGURED for your database
$modeVers = '1';
$verbose = 1; // 0,1 or 2



// // // // // // // // // //
// CONFIGS: (complement to omLib)
	$projects = [ 'carga'=>__DIR__ .'/..' ];
	$reini = true;  // re-init all SQL structures of the project (drop and refresh schema)


// // // // //
// SQL PREPARE
$INI   = [ // prepare namespaces
	"SELECT term1.ns_upsert('test','pt','Test. Portuguese.')"
	,"SELECT term1.ns_upsert('wayta-pt','pt','Wayta SciELO reference-dataset, for performance tests. Portuguese.')"
	,"SELECT term1.ns_upsert('wayta-code','  ','Wayta SciELO reference-dataset, for performance tests. no-lang')"
	,"SELECT term1.ns_upsert('wayta-en','en','Wayta SciELO reference-dataset, for performance tests. English.')"
	,"SELECT term1.ns_upsert('wayta-es','es','Wayta SciELO reference-dataset, for performance tests. Spanish.')"
	,"UPDATE term1.ns SET fk_partOf=term1.nsget_nsid('wayta-pt') WHERE label!='wayta-pt' AND left(label,5)='wayta'"
];
$items = [
	'carga'=>[
		//array("INSERT INTO term$modeVers.term(fk_ns,term) VALUES (1, :term::text)",
		// USE DIRECT insert 
		array("SELECT term$modeVers.upsert(:term::text, term1.nsget_nsid('test'))",
			'test.csv::strict'  // 305 itens
		),
		array("SELECT term$modeVers.upsert(:term::text, term1.nsget_nsid('wayta-pt'), :json_info::jsonb, false, NULL::int)",
			'normalized_aff.csv::strict' 
			// 43050 itens, 41795 normalized, 31589 canonic, mix of portuguese and english.
		),
	],
]; // itens of each project
$sql_delete = " -- prepare to full refresh of om.scheme
	DELETE FROM term$modeVers.term;
";


// // // //
// INITS:

$db = new pdo($dsn,$PG_USER,$PG_PW);

if ($reini) {
	print "... RE-INITING SQL SCHEMA TERM$modeVers...\n";
	sql_exec($db,  file_get_contents($projects['carga']."/src/ini$modeVers.sql")  );
	print "... each complementar INI, \n";
	foreach($INI as $sql)
		sql_exec($db, $sql, "  .. ");
	print "\n";
}

sql_exec($db,$sql_delete," ...delete\n");

print "BEGIN processing (TERM$modeVers) ...";

list($n2,$n,$msg) = jsonCsv_to_sql($items,$projects,$db, ',', 0, $verbose); 
// Wayta está injetando entidades XML onde deveriam ser UTF8, corrigir por parser geral o file.csv

if (1) {
	// Acrescenta canônicos (form) não-contemplados pela coluna term
	$nsbase='wayta-pt';
	sql_exec($db,"
		WITH uforms AS (
			SELECT DISTINCT  jinfo->>'form' AS form
			FROM term1.term 
			WHERE  fk_ns=term1.nsget_nsid('$nsbase') AND jinfo->>'form' IS NOT NULL 
		) SELECT  -- faz apenas insert condicional, o null força não-uso de update
			term1.upsert( form , term1.nsget_nsid('$nsbase'), NULL, true, NULL::int)  as  id
		  FROM uforms
		  WHERE form>''; -- 314xx rows

		UPDATE term1.term
		SET    is_canonic=true  
		FROM (
			SELECT DISTINCT  term_lib.normalizeterm( jinfo->>'form' ) AS nform
			FROM term1.term 
			WHERE fk_ns=term1.nsget_nsid('$nsbase') AND jinfo->>'form' IS NOT NULL
		) t
		WHERE term.fk_ns=term1.nsget_nsid('$nsbase') AND t.nform=term.term; --31589 rows
	", "   ... CANONICOS-1, upsert e is_canonic\n");

	// marca os termos normais com ponteiro para respectivo canônico
	sql_exec($db,"
		-- GAMBI
		DELETE from term1.term where term like '% , , %'; -- bug sem traumas, para arrumar no futuro.
		-- DO UPDATE pointing fk_canonic for each non-canonic. Pode dar erro de duplicação.
		UPDATE term1.term
		SET    fk_canonic=t.cid  
		FROM (
			SELECT id as cid, term as cterm
			FROM term1.term 
			WHERE fk_ns=term1.nsget_nsid('$nsbase') AND is_canonic
		) t
		WHERE NOT(term.is_canonic) AND term.fk_ns=term1.nsget_nsid('$nsbase') AND t.cterm=term_lib.normalizeterm( term.jinfo->>'form' ); --9567 rows
	", "   ... CANONICOS-2, delete e fk_canonic\n");
	sql_exec($db,"
 	  UPDATE term1.term 
 	  SET fk_ns=term1.nsget_nsid('wayta-code')
 	  WHERE fk_ns=2 AND char_length(term)<20 AND position(' ' IN term)=0; -- 517

 	  UPDATE term1.term 
 	  SET fk_ns=term1.nsget_nsid('wayta-en')
	  WHERE (fk_ns=2) AND to_tsvector('simple',term) @@ to_tsquery('simple', 'university|of|the|school'); -- 6038
 	  	    
 	  UPDATE term1.term 
 	  SET fk_ns=term1.nsget_nsid('wayta-es')
	  WHERE (fk_ns=2) AND to_tsvector('simple',term) @@ to_tsquery('simple', 'universidad|del'); -- 3088
	", "   ... CANONICOS-3, change namespaces as detected lang\n");
}

/* ASSERTS!  capturar json-assert por
	fazer diff de txt com saídas dos exemplos.
*/

print "$msg\n\nEND(tot $n lines scanned, $n2 lines used)\n";
?>


