<?php
/**
 * Scans and charges CSV data to the SQL database.
 * See also scripts at "ini.sql" (run it first with psql<ini.sql).
 * php openness-metrics/src/php/ini.php
 */

include 'omLib.php';
$verbose = 1; // 0,1 or 2

// // // // // // // // // //
// CONFIGS: (complement to omLib)
	$projects = [
		'carga'=>		__DIR__ .'/..',
	];
	$reini = true;  // re-init all SQL structures of the project (drop and refresh schema)

// // // // //
// SQL PREPARE
$items = [
	'carga'=>[
		array('INSERT INTO term0.term(fk_ns,term) VALUES (1,:term::text)',
			'cargaTest1.csv::strict'
		),
		// array(..., 'scopes.csv')
	],
];

$sql_delete = " -- prepare to full refresh of om.scheme
	DELETE FROM term0.term
";

// // //
// INITS:

//FALTA informar do erro de um exec.

$db = new pdo($dsn,$PG_USER,$PG_PW);

if ($reini) {
	print "... RE-INITING SQL SCHEMA...\n";
	sql_exec($db,  file_get_contents($projects['carga'].'/src/ini.sql')  );
} sql_exec($db,$sql_delete);

print "BEGIN processing ...";

list($n2,$n,$msg) = jsonCsv_to_sql($items,$projects,$db, ',', 0, $verbose);

print "$msg\n\nEND(tot $n lines scanned, $n2 lines used)\n";
?>


