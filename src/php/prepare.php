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

	,"SELECT tStore.ns_upsert('wayta-pt','pt','Wayta SciELO reference-dataset, Portuguese.',true, '{\"group_unique\":false}'::jsonb)"
	,"SELECT tStore.ns_upsert('wayta-code','  ','Wayta SciELO reference-dataset, no-lang')"
	,"SELECT tStore.ns_upsert('wayta-en','en','Wayta SciELO reference-dataset, English.')"
	,"SELECT tStore.ns_upsert('wayta-es','es','Wayta SciELO reference-dataset, Spanish.')"
	,"UPDATE tStore.ns SET fk_partOf=tlib.nsget_nsid('wayta-pt') WHERE label!='wayta-pt' AND left(label,5)='wayta'"

	,"SELECT tStore.ns_upsert('country-code', '  ', 'Country names reference-dataset, no-lang.', true, '{\"group_unique\":false}'::jsonb)"
	,"SELECT tStore.ns_upsert('country-pt','pt','Country names reference-dataset, Portuguese.')"
	,"SELECT tStore.ns_upsert('country-fr','fr','Country names reference-dataset, French.')"
	,"SELECT tStore.ns_upsert('country-es','es','Country names reference-dataset, Spanish.')"
	,"SELECT tStore.ns_upsert('country-en','en','Country names reference-dataset, English.')"
	,"SELECT tStore.ns_upsert('country-de','de','Country names reference-dataset, Deutsch.')"
	,"SELECT tStore.ns_upsert('country-it','it','Country names reference-dataset, Italian.')"
	,"SELECT tStore.ns_upsert('country-nl','nl','Country names reference-dataset, Dutch.')"
	,"UPDATE tStore.ns SET fk_partOf=tlib.nsget_nsid('country-code') WHERE label!='country-code' AND left(label,7)='country'"

	// may be use datapack info
	,"INSERT INTO tstore.source (name,jinfo) VALUES
		('normalized_aff',      tstore.source_add1('Scielo','Wayta institution','https://github.com/scieloorg/wayta/blob/master/processing/normalized_aff.csv') )
		,('normalized_country', tstore.source_add1('Scielo','Wayta country','https://github.com/scieloorg/wayta/blob/master/processing/normalized_country.csv') )
		,('country-names-multilang', tstore.source_add1('Unicode','UNICODE CLDR, core, territory','http://www.unicode.org/Public/cldr') )
		,('country-codes',      tstore.source_add1('OKFN','Data Packaged Core Datasets, ISO and other Country Codes','https://raw.github.com/datasets/country-codes/master/data/country-codes.csv') )
		,('iso3166-1-alpha-2',      tstore.source_add1('ISO','ISO-3166-1, Country Codes, Alpha-2','') )
		,('iso3166-1-alpha-3',      tstore.source_add1('ISO','ISO-3166-1, Country Codes, Alpha-3','') )
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
		'normalized_country'=>[
			['prepare_jsonb', "tlib.tmp_waytacountry"],  //  term,jinfo
		],
		'country-codes'=>[
			['prepare_jsonb', "tlib.tmp_codes"],  //  term,jinfo
		],
		'country-names-multilang'=>[
			['prepare_jsonb', "tlib.tmp_codes2"],  //  term,jinfo
		],
	 ]
	, "(MODE$sqlMode)"
);

sql_prepare(
	[ // after load, upsert main table and run final update script
		"SELECT tStore.upsert(term, tlib.nsget_nsid('test')) FROM tlib.tmp_test;"
		,"DROP TABLE tlib.tmp_test;"  // used, can drop it.

		,"::src/sql_mode$sqlMode/nsCountry_build.sql" 	// UPDATES and data adaptations
		,"DROP TABLE tlib.tmp_waytacountry; DROP TABLE tlib.tmp_codes; DROP TABLE tlib.tmp_codes2;"  // used, can drop it.

		/*
		,"DROP TABLE IF EXISTS tmp_xx; CREATE TABLE tmp_xx AS
			SELECT  c.term as canonic,  t.term, tlib.nsid2label(t.fk_ns) as nslabel, t.is_cult
			FROM tstore.term t INNER JOIN tstore.term_canonic c ON c.id=t.fk_canonic
			WHERE t.is_suspect AND t.fk_ns>32 and t.kx_metaphone IN (
				SELECT kx_metaphone
				from tstore.term
				where fk_ns>32
				GROUP BY kx_metaphone
				HAVING sum(COALESCE(is_suspect,true)::int)>0  AND count(*)>1
				order by 1
			) ORDER BY c.term, t.term;
		"
		,"COPY tmp_xx TO '$basePath/data/tmp_country-humanCheck.csv' DELIMITER ',' CSV HEADER;"
		*/

		,"::src/sql_mode$sqlMode/nsWayta_build.sql"  	// UPDATES and data adaptations
		,"DROP TABLE tlib.tmp_waytaff;"  // used, can drop it.

		//,"::assert:data/assert1_mode$sqlMode.tsv" // test against assert
		,"::assert_bysql:data/assert1_mode$sqlMode.tsv" // test against assert
	]
	,"SQL FINALIZATION"
	,$basePath
);

?>
