<?php
/**
 * Openness-Metrics Library, PHP implementation.
 * @version: lib1.0
 * @author:  ppkrauss
 * @license: MIT
 */

// no demo indicar a versão do grau em uso.
//Falta usar chamada PDO ao SELECT om.family_count_bylicenseids( om.license_ids_bynames() )
//a ser usado como referência nesta LIB. Calculos de escopo não precisam ser SQL.

	// // // //
	// CONFIGS: (by include secure/configs.php)

	$PG_USER = 'postgres';
	$PG_PW   = 'pp@123456';
	$dsn="pgsql:dbname=postgres;host=localhost";
	$degVers =1; //may be overhide by request
	$cmd = ''; // method
	$list = '';
	$callerID = '';
	$is_cmdFam = NULL;
	$is_cmdLic = NULL;

/////////////////
// ERROR HANDLING

function sql_exec(PDO $db,$sql) {
    $affected = $db->exec($sql);
    if ($affected === false) {
        $err = $db->errorInfo();
        if ($err[0] === '00000' || $err[0] === '01000') {
            return true;
        } else
	    die("\n--ERRO AO RODAR SQL: \n---------\n".substr(str_replace("\n","\n\t",$sql),0,300)."\n-----------\n".implode(':',$err)."\n");
    }
    return $affected;
}


/////////////////
// INIT FUNCTIONS

$glo_scope = ['od','oa','rt'];

/**
 * Initialization, get datapackage.json and project descriptions to transform in a SQL+JSON database.
 */
function jsonCsv_to_sql(&$items, &$projects, &$db, $SEP = ',', $nmax = 0, $verbose=2) {
	$OUT_report = '';
	$n=$N=$N2=0;
	foreach($items as $prj=>$r)
	   foreach ($r as $dataset) {
		$folder = $projects[$prj];
		$sql = array_shift($dataset);
		$OUT_report.= "\n\n---- PRJ $prj".(($verbose>=2)? " {{ $sql }}": '');

		$stmt = $db->prepare($sql);
		$jpack = json_decode( file_get_contents("$folder/datapackage.json"), true );

		$ds = array(); // only for "bind" and "strict" checkings.
		foreach($dataset as $i) {
			$i = str_replace('::bind','',$i,$bind);
			$i = str_replace('::strict','',$i,$aux);
			$ds["data/$i"] = $bind+2*$aux;
		}
		$ds_keys = array_keys($ds);
		foreach($jpack['resources'] as $pack)
		  if ( in_array($pack['path'],$ds_keys) ) {
			$useType = ($ds[$pack['path']]>1);
			$OUT_report.= "\n\t-- reding dataset '$pack[path]' ";
			$fields = $pack['schema']['fields'];
			list($sql_fields,$json_fields,$json_types) = fields_to_parts($fields,false,true); //,$useType);
			$has_jfields = count($json_fields);
			if ($has_jfields) $json_fields[] = 'source'; // admin fields
			$n=$n2=0;
			$nsql = count($sql_fields);
			$file = "$folder/$pack[path]";
			$h = fopen($file,'r');
			while( $h && !feof($h) && (!$nmax || $n<$nmax) )
			  if (($lin0=$lin = fgetcsv($h,0,$SEP)) && $n++>0  && isset($lin[0])) {
				$jsons = array_slice($lin,$nsql);
				$types = array_slice($json_types,$nsql);
				for($t_i=0; $t_i<count($types); $t_i++)
					settype($jsons[$t_i], $types[$t_i]); // casting to string or selected type
				$sqls  = array_slice($lin,0,$nsql);
				if ($has_jfields) $jsons[] = $pack['path'];  // admin fields
				$info = json_encode( array_combine($json_fields,$jsons) );
			// AQUI capturar exception para tratar erro de incompatibilidade entre package e CSV.
				//print "\n##-- $info .. OPS no cast!";
				if ($ds[$pack['path']]) {  // or ctype_digit()
					$tmp = $sqls;
					foreach($sql_fields as $i) if ($useType)
						$stmt->bindParam(":$i", array_shift($tmp));
						else $stmt->bindParam(":$i", array_shift($tmp));
					if ($has_jfields && $info) $stmt->bindParam(":json_info", $info);
					$ok = $stmt->execute();
				} else // implicit bind (by array order and no datatype parsing)
					$ok = $stmt->execute( array_merge($sqls,array($info)) );
				if (!$ok) {
					$OUT_report.= "\n ---- ERROR (at csv line-$n (rec. $n2) with error info) ----\n";
					$OUT_report.= var_export($lin0, true);
					$OUT_report.= var_export($stmt->errorInfo(),true);
					return array(-1,0,$OUT_report); //die("\n");
				} else $n2++;
			  } elseif ($nsql>0 && count($sql_fields) && isset($lin) && count($lin) && $lin!=array() && isset($lin[0])) {
				//debug print "\n-pk-$n2...0-$nsql \nlin=".count($lin);print_r($lin);
				$lin_check = fields_to_parts( array_slice($lin,0,$nsql) );
				if ($sql_fields!= $lin_check){
					var_dump($lin_check);
					var_dump($sql_fields);
					die("\n --- ERROR: CSV header-basic not matches SQL/datapackage field names ---\n");
				}
			  } //else print "\n-- !WARNING 2 at omLib.php, jsonCsv_to_sql(), n=$n\n";
			$OUT_report.= " $n lines scanned, $n2 used.";
			$N+=$n; $N2+=$n2;
			unset($ds[$pack['path']]);
		  } // if $pack
		$sampath = "data/samples";
		if (isset($ds[$sampath])) { // a kind of XML dataset
			unset($ds[$sampath]);
			$folder2 = "$folder/$sampath";
			foreach (scandir($folder2) as $ft) if (strlen($ft)>2) // folder-types sci and law
				foreach (scandir("$folder2/$ft") as $rpfolder) if (strlen($rpfolder)>2)
					intoDb_XMLs("$folder2/$ft/$rpfolder",$db,$rpfolder); // scans repository's folder
		}
		foreach ($ds as $k=>$v) $OUT_report.= "\n --WARNING: pack '$k' (bind=$v) not used";
	  } // for $r
	return array($N2,$N,$OUT_report);
}// func


/**
 * Initialization, json_to_sql() function complement.
 */
function fields_to_parts($fields,$only_names=true,$useType=false) {
	$sql_fields = array();
	$json_fields = array();
	$json_types = array();
	// to PDO use PDO::PARAM_INT, PDO::PARAM_BOOL,PDO::PARAM_STR
	$json2phpType = array( // see datapackage jargon, that is flexible...
		'integer'=>'integer', 'int'=>'integer',
		'boolean'=>'boolean', 'number'=>'float', 'string'=>'string'
	);
	if (count($fields)) {
	  foreach($fields as $ff) {
		$name = str_replace('-','_',strtolower($only_names? $ff: $ff['name']));
		if ( !$only_names && isset($ff['role']) ) {   // e outros recursos do prepare
			$sql_fields[]  = $name;
		} else
			$json_fields[] = $name;
		if ( $useType && isset($ff['type']) ) {
			// parse with http://php.net/manual/en/pdo.constants.php
			$t = strtolower($ff['type']);
			$json_types[] = isset($json2phpType[$t])? $json2phpType[$t]: 'string';
		} else
			$json_types[] = 'string';// PDO::PARAM_STR;
	   } // for
	} // else return ...
	return ($only_names?
		  $json_fields:
		  ($useType? [$sql_fields,$json_fields,$json_types]: [$sql_fields,$json_fields])
	);
}

/**
 * Initialization, json_to_sql() function complement, used only in sample-get.
 */
function intoDb_XMLs($pasta,$db,$repo_name,$n_limit=0,$verbose=0) {
	if (!is_dir($pasta))
		return;
	print "\n\n\t --- scanning folder ($pasta) of $repo_name ---\n";
	$rgx_doctype = '/\s*<!DOCTYPE\s([^>]+)>/s';  // needs ^
	$stmt = $db->prepare( "SELECT om.docs_upsert('$repo_name',:dtd::text,:pid::text,:xcontent::xml,NULL::JSON)" );
	$n=0;
	foreach (scandir($pasta) as $file)
	  if (strlen($file)>2  && (!$n_limit || $n<=$n_limit)) {
		$n++;
		if ($verbose) print "\n--$n-- $pasta / $file ";
		$pid = preg_replace('/\.xml/i','',$file);
		$f = "$pasta/$file";
		$cont = file_get_contents($f);
		if (!$cont)
			die("\n-- empty file: $f");
		$doctype = preg_match($rgx_doctype,$cont,$m)? $m[1]: '';
		$doctype = preg_replace('/\s+/s',' ',$doctype);
		if ($doctype)
			$cont = preg_replace($rgx_doctype, '', $cont);
		$stmt->bindParam(':pid',     $pid,PDO::PARAM_STR);
		$stmt->bindParam(':dtd',     $doctype,PDO::PARAM_STR);
		$stmt->bindParam(':xcontent',$cont,PDO::PARAM_STR);
		$re = $stmt->execute();
		if (!$re) {
			print_r($stmt->errorInfo());
			die("\n-- ERROR at $file, not saved\n");
		} //else $n2++;
	  } // scan xml files
	print "\n$n XML docs of '$repo_name' inserted\n\n";
	return;
} // func


///////////////////
// REPORT FUNCTIONS

/**
 * Box-report generator, HTML box + SVG pie + reportCalculations.
 */
function set_OpenMetricsBox(
	$IDSET,
	$percs_in, // PERCENTS
	$gambi,   // VALUES
	$twidth='100%', $no_label=true, $gbox_w=320, $gbox_h=0,$vStd='1.0',$RELAT=''
) {
	global $glo_scope;
	list($id,$lang,$title,$HTML_EXTRA) = ($IDSET===NULL)? ['','pt','','']: $IDSET;
	$onlyPie = ($gambi===NULL)? true: false;
	if ( !(is_array($percs_in) && count($percs_in)) || !$gbox_w)
		return '';
	if (!$gbox_h)
		$gbox_h = 0.875*$gbox_w; // factor 280/320
	$vLabel = [ 	'od'=>['OD','#E0FFD0','Open Definition'], 'oa'=>['OA','#F0F090', 'Open Access'],
			'rt'=>['RT','#F59090', 'ResTricted Access']
	]; // falta incluir a ordem e corrir a ordem!

	$msgs = [
		'pt'=>[ "Convenções v$vStd da métrica do grau de abertura de um conjunto de documentos",
			"Média ponderada dos graus de abertura",
			"média ponderada", "dos itens apresentam licenças", "entre eles o grau de abertura médio é",
			"relatório, clique aqui para abrir/esconder",
			"METODOLOGIA: este relatório faz uso das", "Através de procedimentos em banco de dados as licenças dos itens são associadas a famílias de licença (nas quais o grau de abertura tem valor consensual), e então as famílias agrupadas em",
			"escopos", "A cada escopo é calculado o grau de abertura médio das famílias, podenderando-se pela quantidade de itens de cada família. Por fim é calculada a", //9
			"entre os escopos", "grau de abertura", // 11
		],
		'en'=>["Conventions v$vStd of the openness degree metric of a set of documents", //0
			"weighted average of the openness degrees", //1
			"weighted average",  "of the items offer licenses", "among them the average degree of openness is", //4
			"report, click here to hide/show it", //5
			"METHODOLOGY: this report makes use of", "Through procedures in database licenses of the items are associated with license families (in which the degree of openness has agreed amount), and then the families grouped into", //7
			"scopes", "With each scope is calculated the average degree of openness of the families, weighting by the amount of items in each family. Finally is calculated the", //9
			"between scopes", "openness degree", // 11
		],
	];
	$is_explode=false;
	$is_float  =false;
	$vals = [];
	$avg = $avg_tot = 0.0;
	foreach($glo_scope as $k) if (isset($percs_in[$k])) { // loops in the correct scope order
		$v = $percs_in[$k];
		if (!$onlyPie) {
			$avg     += (float) $v * (float) $gambi[$k];
			$avg_tot += (float) $v;
		}
		$v = round($v,1);
		if ($v!=round($v)) $is_float=true;
		if ($v<5)          $is_explode=true;
		$vals[$k] = $v;
	}
	$n_vals = count($vals);
	$avg = round($avg/$avg_tot,1);

	$stderr = 0.0; // standard deviation about weighted mean,  https://en.wikipedia.org/wiki/Weighted_arithmetic_mean
	foreach($vals as $k=>$v){
		$stderr += (float) $v*pow((float) $gambi[$k] - (float) $avg,2);
	}
	$stderr = round( sqrt($stderr/((float) $avg_tot)), 0 );

	$GG = set_graph_3slices($vals, $vLabel, $is_float, $is_explode, $no_label, $gbox_w, $gbox_h);

	if ($onlyPie)
		return $GG;
	else {
		$lmsg = $msgs[$lang];
		$TR = [];
		$TR[] = "<tr>"
			."<td rowspan='4'>"
				."<img title=\"$lmsg[5]\" width='20' src='../assets/box-maximize.png'
					onclick=\"boxToggle('om-t$id')\"/>"
				.$GG
			.'</td>'
			."\n<td colspan='$n_vals' align='center'>"
			   ."<b>$title</b>, <i>$lmsg[11]</i>"
			   ."" // old
			   .'</td>'
			.'</tr>';
		$TR[] = "<tr><td colspan='$n_vals' title=\"$lmsg[1]: $avg\" class='ometrics-avg'>"
			."$lmsg[2] <b>$avg</b>"
			.'</td></tr>';
		$wpart = round(100.0/$n_vals);
		$TD = '';
		foreach($vals as $k=>$v)
			$TD.= "\n<td width='$wpart%' class='ometrics-$k'  valign='middle'"
					.' title="'
					  ."$v% $lmsg[3] {$vLabel[$k][2]}, "
					  ."$lmsg[4] {$gambi[$k]}"
					."\">&#160;<img width='34' align='absmiddle' src='../assets/licenseGroup-$k.png'/>"
					."&#160; <b>$gambi[$k]</b>&#160;"
				.'</td>';
		$TR[] = "<tr>".$TD.'</tr>';
		$tid='';
		if ($id) {
			$escopos = [];
			foreach (array_keys($vals) as $k) // correct order
				$escopos[] ="{$vLabel[$k][0]} = {$vLabel[$k][2]}";
			$escopos = join(", ",$escopos);
			$stdReport = "$lmsg[6] <a target='_blanck' href='https://github.com/ppKrauss/openness-metrics#v1'>$lmsg[0]</a>."
				." $lmsg[7]  $n_vals $lmsg[8] ($escopos). $lmsg[9] <i>$lmsg[1]</i> $lmsg[10].";

			$HTML_EXTRA = str_replace('#STDREPORT#',"<p>$stdReport</p>",$HTML_EXTRA,$aux);
			if (!$aux) $HTML_EXTRA .= "<p>$stdReport</p>";
			$HTML_EXTRA = str_replace('#RELAT#',$RELAT,$HTML_EXTRA,$aux2);
			$avg2 = round($avg);
			$HTML_EXTRA = str_replace('#stdDev#',"{$avg2}±$stderr",$HTML_EXTRA,$aux3);

			$tid = " id='om-t$id'";
			$TR[] = '<tr><td>&#160;</td></tr>';
			$TR[] = "<tr class='ometrics-report' style='display:none'>"
				."<td colspan='".($n_vals+1)."'>$HTML_EXTRA</td></tr>";
		} else
			$TR[] = '<tr><td>&#160;</td></tr>';
		return  "<table$tid class='ometrics' width='$twidth'>". join("\n",$TR) .'</table>';
	} // if onlypie
} // func


/**
 * Box-report generator complement, alias to get only SVG pie.
 */
function set_OpenMetricsPie($percs_in, $no_label=true, $gbox_w=320, $gbox_h=0) {
	return set_OpenMetricsBox(NULL,$percs_in, NULL, '', $no_label, $gbox_w, $gbox_h);
}

/**
 * Box-report generator complement, encapsulate SVGGraph handlings.
 */
function set_graph_3slices($vals, $vLabel, $is_float, $is_explode, $no_label=true, $gbox_w=320, $gbox_h=0) {
	$graph_3slices = new SVGGraph($gbox_w, $gbox_h, [
	  'label_font' => 'Georgia', 'label_font_size' => '18',
	  'label_colour' => '#000',   'back_colour' => 'white',
	  'stroke_colour'=>'rgb(180,140,140)',
	  'explode_amount'=>16, 'explode' => 'all',   'sort' => false,
	   // see http://www.goat1000.com/svggraph-settings.php
	   // how to remove frame-rectangle?
	]);
	$vals_out = [];
	$colours  = [];
	foreach($vals as $k=>$v) {
		$label = $no_label? '': "{$vLabel[$k][0]} ";
		$vals_out[ sprintf($is_float? "$label%.1f%%": "$label%s%%",$v) ]=$v;
		$colours[]  = $vLabel[$k][1];
	}
	$graph_3slices->Values($vals_out);
	$graph_3slices->colours = $colours; // sort=false to preserve colour-value matching.
	if ($is_explode)
		$GG = $graph_3slices->Fetch('ExplodedPieGraph', false);
	else
		$GG = $graph_3slices->Fetch('PieGraph', false);
	$GG = preg_replace('#<rect .+?/>#','',$GG);
	return $GG;
}


// // // // // // // // //
// // input/output CONTROL

/**
 * POST/GET checker
 */
function checkrequest(&$x,$name,&$bool=NULL) {
	if (isset($_REQUEST[$name])) {
		$x = $_REQUEST[$name];
		unset($_REQUEST[$name]);
		$bool=true;
		//if ($bool!==NULL) $bool=true;
	}
}

/**
 * Like array_combine(list,$pair) but pair is optional and
 * value is the sum of values (default 1), or number of occurences.
 */
function array_combine_sum($list,$pair=NULL) {
	$ret = [];
	foreach($list as $idx=>$x) {
		$v = ($pair!==NULL)? $pair[$idx]: 1;
		$x = trim($x);
		if ($x>'') {if (isset($ret[$x])) $ret[$x] += $v; else $ret[$x]=$v;}
	}
	return $ret;
}


/**
 * Submit request (cmd with params) to the database. As webservice.
 * @param $cmd string command
 * @param $params array, params of the command.
 * @param $degVers int openness degree version.
 * @param $notRetJson int 0=JSON, 1=PHP ARRAY, 2=PHP OBJECTS.
 */
function request_ws($cmd,$params,$degVers=2,$notRetJson=0) {
	global $dsn;
	global $PG_USER;
	global $PG_PW;
	$err_cod=0;
	try {
		$jinfo = json_encode($params);
		switch ($cmd) {
			case 'licqts_calc':
				$sql = "SELECT om.licqts_calc(:j_info::json,$degVers)";
				break;

			case 'famqts_calc':
				$sql = "SELECT om.famqts_calc(:j_info::json,$degVers)";
				break;
			default:
				throw new Exception("Comando '$cmd' desconhecido", 5);
		}
		$db = new pdo($dsn,$PG_USER,$PG_PW);
		$stmt = $db->prepare($sql);
		if ( $stmt->bindParam(":j_info", $jinfo) )
			$ok = $stmt->execute();
		else
			throw new Exception("Falha no bindParam", 8);
		if ($ok) {
			$json = $stmt->fetchColumn();
			return $notRetJson? json_decode($json,($notRetJson==2)? false: true): $json;
		} else
			throw new Exception("Falha ao executar SQL, \n'''$sql'''\n", 20);
		return null; //never here
	} catch (Exception $e) {
		$r = array( 'error'=>array('code'=>$e->getCode(),'message'=>$e->getMessage()) );
	}
	return $notRetJson? $r: json_encode($r,true);
} // func


/**
 *  Same as set_OpenMetricsBox() but using request_ws() data.
 */
function set_OpenMetricsBox_byFamList($params, $famList, $degVers=2, $gbox_h=0) {
	$jresult = request_ws('famqts_calc',$famList,$degVers,1); // list, version, retType
	$relatMsg = $OUT = '';
	foreach($jresult as $k=>$v) {
		if (!is_array($v))
			$relatMsg.= " $k=$v";
	}
	$percs = [];
	$avgs = [];
	foreach($jresult['scopes'] as $idx=>$sc) {
		$scope = $sc['scope'];
		$percs[$scope] = round($sc['perc'],1);
		$avgs[$scope]  = round($sc['avg_scope'],1);
	}
	foreach($jresult['list'] as $idx=>$info) {
		$perc = round($info['perc'],1);
		$relatMsg .= "<br/> &#160; <i>$info[name]</i> (<i>$info[scope]</i> <b>$info[deg]</b>) com $info[qt] jous ($perc%)";
	}
	$OUT = set_OpenMetricsBox(
		$params,
		$percs,
		$avgs, '480', true, 200, $gbox_h,$degVers,$relatMsg
	);
	return $OUT;
}

?>
