<?php
/**
 * Extracts all "sub-organization names" expressed in the Diário Oficial do Município de São Paulo, of 2015 and 2016.
 * @version v0.1 2016-04-04
 * @usage php src/php/pubnetHtml2csv.php > lix.csv
 */


//CONFIGS:
	$fout_file = 'php://output';
	$fin_file  = realpath(__DIR__.'/../../_docs/PUBNET-retrancas_Dicio_2-Alef/secretaria-div.html'); 

$dom = new DOMDocument;
$dom->loadHTMLfile($fin_file);
$xp = new DOMXpath($dom);

$fout = fopen($fout_file, 'w');
foreach ( $xp->query('//tr') as $tr) {
	$line = [];
	$showClass = 1;
	foreach ( $xp->query('.//th|.//td',$tr) as $cel ) if (!ctype_digit($cel->nodeValue)){
		if ($showClass) 
			array_push($line, $cel->getAttribute('class'));
		array_push($line, $cel->nodeValue);
		$showClass=0;
	}
	fputcsv($fout,$line);
}
fclose($fout);

?>

