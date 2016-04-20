<?php
/**
 * Basic webservice  interface.
 */

 include 'packLoad.php';  // must be CONFIGURED for your database
//$db = new pdo($dsn,$PG_USER,$PG_PW);

$basePath = '/var/www/xconv.local/xconv3/_relats';//realpath(__DIR__ .'/../..');
$reini = true;  // re-init all SQL structures of the project (drop and refresh schema)
$sqlMode = '1';
$packs = ['packs'=>[
    'aff2'=>[ 'file'=>"$basePath/data/aff2-2016-01-21.csv", 'sep'=>','] ]
];

$sqlIni   = [
  "::assert_bysql:data/assert1_mode$sqlMode.tsv" // test against assert

];
sql_prepare($sqlIni, "teste de ASSERT", "/home/peter/gits/sql-term");

die("\nOK3232\n");


sql_prepare(
  "
    CREATE TABLE IF NOT EXISTS tmp_aff2 (
    lang text,
    artigo_id int,
    p_aff xml
  );
  "
);

resourceLoad_run(
	$basePath  // nada
	,[ // itens of each resource defined in the datapackage.
		'aff2'=>[
			['prepared_copy', "tmp_aff2"],
		],
	 ]
	, "AFF2 test kit"
  , $packs
);

// carregar asserts automaticamente, incluir "SELEC onde nao começar por SELECT ou WITH "

# see table tstore.assert

/*

CREATE FUNCTION array_last(
	--
	-- Returns the element of array_upper()
	--
	anyarray,
	int DEFAULT 0
) RETURNS anyelement AS $f$
	SELECT $1[array_upper($1,1)-$2];
$f$ LANGUAGE SQL IMMUTABLE;


CREATE or replace FUNCTION aff_parse_last(
	--
	-- Returns the element of array_upper()
	--
	text[]
) RETURNS text AS $f$
DECLARE
  x text;
BEGIN
	x := trim( array_last($1) );
	if char_length(x)<=1  THEN
		x := trim( array_last($1,1) );
	END IF;
	return x;
END
$f$ LANGUAGE PLpgSQL IMMUTABLE;






FALTA
1) packLoad se tornar configurável direto, sem precisar de dataset!
2) pegar aff de amostras já consolidadas pelo SciELO!  ... fazer carga via make...




// // // // // // // // // //
// CONFIGS: (complement to omLib)
	$basePath = realpath(__DIR__ .'/../..');
	$reini = true;  // re-init all SQL structures of the project (drop and refresh schema)
	$sqlMode = '1';



lang,artigo_id,p_aff
en,28553,"<p class=""aff"" data-st=""5""><span class=""orgdiv1"">College of Business and Economics</span>
, <span class=""orgname"">Qatar University</span>, <span class=""city"">Doha</span>, <span class=""countr
y"">Qatar</span></p>"
*/
