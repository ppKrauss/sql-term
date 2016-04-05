<?php
/**
 * Extracts all country names from Unicode's CLDR files.
 * Adapted from ietf-lanGen.php of https://github.com/datasets/language-codes
 * @see https://github.com/unicode-cldr/cldr-core
 * @version 2016-04-04
 * @usage php src/php/cldr2langsCsv.php > data/country-names-multilang.csv
 */


//CONFIGS:
	$fout_file = 'php://output';
	$LANGS = ['af','en','es','de','fr','it','nl','pt'];  // check prepare.php and datapackage.json!
	$dir= realpath(__DIR__.'/../../data/common/main'); // obtained from:
	// wget -c http://www.unicode.org/Public/cldr/latest/core.zip
	// unzip core.zip
	// REMOVE all after this CSV generation. rm -r common

$fout = fopen($fout_file, 'w');
$dom = new DOMDocument;
$LIN = [];  // 'country'=>['lang1'=>'name1', 'lang2'=>'name2', ...
foreach(scandir($dir) as $file) if (  preg_match('/^(.+)\.xml$/',$file,$m)  && in_array(($lang=$m[1]),$LANGS) ) {
    $dom->load("$dir/$file");
    $lang = strtr($lang,'_','-');
    $xp = new DOMXpath($dom);
    foreach ( $xp->query('//territories/territory') as $tnode) {
			$c = strtolower($tnode->getAttribute('type'));
			if ($c!='001') {
				if ((int) $c > 1) $c = "i$c";
				$LIN[$c][$lang] = $tnode->nodeValue;
			}
		}
}

$countries = array_keys($LIN);
sort ($countries);

$TMP = $LANGS;
array_unshift($TMP,'iso_code');
fputcsv($fout,$TMP);

foreach($countries as $c) {
	$out = [$c];
	foreach($LANGS as $lang)
		$out[] = isset($LIN[$c][$lang])? $LIN[$c][$lang]: '';
	fputcsv($fout,$out);
}
fclose($fout);
?>
