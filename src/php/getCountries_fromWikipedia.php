<?php
/**
 * Get countries from Wikipedia and the country-codes dataset.
 * USE:  php _relats/getCountries_fromWikipedia.php >  _relats/data/tmp_refresh_paises.sql
 *       depois de revisar, psql -h localhost -U postgres xconvbase < tmp_refresh_paises.sql
 * PARA CONFERIR POR SQL,
	WITH cidades AS (
	  select upper(rotulo) as isocode2, nome 
	  from xconv.cidades where length(rotulo)=2
	) SELECT p.*, c.nome 
	  FROM cidades c LEFT JOIN xconv.paises p ON p.isocode2=c.isocode2
	  where p.wikidata_id is null;
 *
 * PARA MANUTENCAO
	UPDATE xconv.cidades SET nome=p.nome_lang[1] 
	FROM xconv.paises p 
	WHERE length(cidades.rotulo)=2 AND p.isocode2=upper(cidades.rotulo) 
 *
 * FALTA esquema de try/Exception seguido de segunda tentativa sem a virgula, por ex. Macedonia e Venezuela
 *      "Venezuela, Bolivarian Republic of". 
	Conferir também causas do sumisso "Zambia", "Islas Vírgenes de los Estados Unidos"
		"Sahara Occidental", "Islas Wallis y Futuna", "Islas Vírgenes Británicas"
		"Yemen", "Zimbabwe", "Viet Nam", "Vanuatu"
 */

// CONFIGS:
	$LANGS = ['pt','en','af','es','fr']; // pt, en, resto ordenado.
	$lcodes = file_csv('https://raw.githubusercontent.com/datasets/country-codes/master/data/country-codes.csv', ['assoc'=>1]);
	// $lcodes = file_csv(__DIR__.'/../data/country-codes.csv', ['assoc'=>1]);
	$getCapitals = false;

// INICIALIZACOES
$context = stream_context_create(array(
  'http' => array( 'method' => 'GET', 'header' => "Content-Type: type=application/json\r\n") 
) );   // ver https://github.com/maxlath/wikidata-sdk
$convencao = join(',',$LANGS);



print "
DROP TABLE IF EXISTS xconv.paises;
CREATE TABLE xconv.paises (
  isocode2 char(2) NOT NULL PRIMARY KEY,
  wikidata_id varchar(32),
  nome_lang    text[],  -- convenção pt, en, resto ordenado [$convencao]
  -- capital_lang text[],
  UNIQUE(wikidata_id)
);
COMMENT ON  COLUMN xconv.paises.nome_lang IS '$convencao';

INSERT INTO xconv.paises (isocode2, wikidata_id, nome_lang) VALUES 
";

foreach( $lcodes as $k=>$rr ) {
	$nome = str_replace([' ',"'"],['_','%27'],trim($rr['name']));
	$ISOCODE = $rr['ISO3166-1-Alpha-2'];
	$url_pais = "https://en.wikipedia.org/wiki/$nome"; // redireciona nome correto
	if ( preg_match('/"wgWikibaseItemId":"(Q\d+)/s', substr(file_get_contents($url_pais),0,15000), $m) ){
		$wdID  = $m[1];
 		$js = file_get_contents("https://www.wikidata.org/wiki/Special:EntityData/$wdID.json", false, $context);
		$d = json_decode($js, true);
		//print "\n-- $nome=$wdID";
		if (isset($d['entities'][$wdID]['sitelinks'])) {
			/* OPTIONAL (more langurages!) BY WIKIPEDIA NAMES:
				// exemplo "af=Bosnië en Herzegowina" e label "af=Bosnië-Herzegowina"
				$nameLang = [];
				foreach($d['entities'][$wdID]['sitelinks'] as $k=>$r)
					$nameLang[str_replace('wiki','',$k)] = $r['title'];
				$nameList = [];
				foreach($LANGS as $lang) 
					$nameList[] = $nameLang[$lang];
			*/
			$nameList = [];
			$d0 = $d['entities'][$wdID];
			foreach($LANGS as $lang)
				$nameList[] = isset($d0['labels'][$lang])? str_replace("'","''",$d0['labels'][$lang]['value']): ''; 
				//str_replace() as PDO::quote()
			$dIsoCode = isset($d0['claims']['P297'][0]['mainsnak']['datavalue']['value'])? 
				$d0['claims']['P297'][0]['mainsnak']['datavalue']['value']: '';

			if ($getCapitals && isset($d['entities']['Q155']['labels'])) { // only works at Q155 (Bazil)
				$capList = [];
				$d0 = $d['entities']['Q155']['labels'];
				foreach($LANGS as $lang)
					$capList[] = isset($d0[$lang])? $d0[$lang]['value']: '';
			} else
				$capList = array_fill(0,count($LANGS),'');

			if ($ISOCODE!=$dIsoCode) print "\n-- !! ERRROR ON ISO CODES BELOW, (wiki) $dIsoCode!= (dataset) $ISOCODE\n";
			print " ('$ISOCODE','$wdID',array['".join("','",$nameList)."']),\n"; // ,array['".join("','",$capList)
		} else
			print "\n-- ERRO em $nome, SEM sitelinks";
	} else 
		print "\n-- ERRO em $nome";
}

// // // LIB 


/**
 * Reads entire CSV file into an array (or associative array or pair of header-content arrays).
 * Like build-in file() function, but to CSV handling. 
 * @param $opt not-null (can be empty) associative array of options (sep,head,assoc,limit,enclosure,escape)
 * @param $length same as in fgetcsv(). 
 * @param $context same as in fopen(). 
 * @return array (as head and assoc options).
 */
function file_csv($file, $opt=[], $length=0, resource $context=NULL) {
	$opt = array_merge(['sep'=>',', 'enclosure'=>'"', 'escape'=>"\\", 'head'=>false, 'assoc'=>false, 'limit'=>0], $opt);
	$header = NULL;
	$n=0; $nmax=(int)$opt['limit'];
	$lines = [];
	$h = $context? fopen($file,'r',false,$context):  fopen($file,'r');
	while( $h && !feof($h) && (!$nmax || $n<$nmax) ) 
		if ( ($r=fgetcsv($h,$length,$opt['sep'],$opt['enclosure'],$opt['escape'])) && $n++>0 )
			$lines[] = $opt['assoc']? array_combine($header,$r): $r;
		elseif ($n==1)
			$header = $r;
	return $opt['head']? array($header,$lines): $lines;
}


/* LEMBRETES
queries spark para claim e talvez outros
	// https://wdq.wmflabs.org/api?q=claim[138:24871]
	// https://wdq.wmflabs.org/api?q=claim[31:24871]
	// https://www.wikidata.org/wiki/Wikidata:Glossary

$searchString = urlencode($_POST['q']); //Encode your Searchstring for url
$resultJSONString = file_get_contents("https://www.wikidata.org/w/api.php?action=wbsearchentities&search=".$searchString."&format=json&language=en"); //Get your Data from wiki
$resultArrayWithHeader = json_decode($resultJSONString, true); //Make an associative Array from respondet JSON
$resultArrayClean = $resultArrayWithHeader["search"]; //Get the search Array and ignore the header part

// etc. https://www.wikidata.org/w/api.php?action=wbsearchentities&search=Google&format=json&language=en

**/


