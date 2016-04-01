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

	,"SELECT tStore.ns_upsert('country-code', '  ', 'Country names reference-dataset, no-lang.', true, '{\"group_unique\":true}'::jsonb)"
	,"SELECT tStore.ns_upsert('country-pt','pt','Country names reference-dataset, Portuguese.')"
	,"SELECT tStore.ns_upsert('country-fr','fr','Country names reference-dataset, French.')"
	,"SELECT tStore.ns_upsert('country-es','es','Country names reference-dataset, Spanish.')"
	,"SELECT tStore.ns_upsert('country-en','en','Country names reference-dataset, English.')"
	,"UPDATE tStore.ns SET fk_partOf=tlib.nsget_nsid('country-code') WHERE label!='country-code' AND left(label,7)='country'"
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
		'normalized_country'=>[
			['prepare_jsonb', "tlib.tmp_waytacountry"],  //  term,jinfo
		],
		'country-codes'=>[
			['prepare_jsonb', "tlib.tmp_codes"],  //  term,jinfo
		],
	 ]
	, "(MODE$sqlMode)"
);

sql_prepare(
	[ // after load, upsert main table and run final update script
		"SELECT tStore.upsert(term, tlib.nsget_nsid('test')) FROM tlib.tmp_test;"
		 ,"DROP TABLE tlib.tmp_test;"  // used, can drop it.

		 ,"::src/sql_mode$sqlMode/nsCountry_build.sql" 	// UPDATES and data adaptations
		 ,"DROP TABLE tlib.tmp_waytacountry; DROP TABLE tlib.tmp_codes"  // used, can drop it.

// script causou loop!  faltam mais travas ou revisaõ
		//,"::src/sql_mode$sqlMode/nsWayta_build.sql"  	// UPDATES and data adaptations
		//,"DROP TABLE tlib.tmp_waytaff;"  // used, can drop it.

		 // ,"::assert:src/sql_mode$sqlMode/assert1.sql"  // test against assert (need password by terminal)
	]
	,"SQL FINALIZATION"
	,$basePath
);

?>
