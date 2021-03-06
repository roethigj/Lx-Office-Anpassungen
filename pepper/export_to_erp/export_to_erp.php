<?
/***************************************************************
*Author: Holger Lindemann
*Copyright: (c) 2004 Lx-System
*License: non free
*eMail: info@lx-system.de
*Version: 1.0.1
*Shop: PHPeppershop 1.5
*ERP: Lx-Office ERP
***************************************************************/
// -----------------------------------------------------------------------
// Damit jedes andere Modul ueberpruefen kann ob dieses hier schon "included" ist
// wird folgende Vairable auf true gesetzt (Name = Ext. Modulname + Dateiname ohne .php)
$erp_export_erp_export = true;

?>
<html>
	<head><title>Lx-ERP Export der Shopartikel</title>
	<link type="text/css" REL="stylesheet" HREF="css/main.css"></link>
	<script language="JavaScript">
	<!--
		function pepper() {
		}
	//-->
	</script>
<body>

<?php
$inip=get_cfg_var("include_path");
ini_set("include_path",$inip.":/usr/share/pear/:.");

require_once "DB.php";
require_once "conf.php";

$db=DB::connect($SHOPdns);
if (!$db) dbFehler("",$db->getDebugInfo());
if (DB::isError($db)) {
	dbFehler("",$db->getDebugInfo());
	die ($db->getDebugInfo());
};
$db2=DB::connect($ERPdns);
if (!$db2) dbFehler("",$db2->getDebugInfo());
if (DB::isError($db2)) {
	dbFehler("",$db2->getDebugInfo());
	die ($db2->getDebugInfo());
};
/****************************************************
* dbFehler
* in: sql,err = string
* out:
* Fehlermeldungen ausgeben
*****************************************************/
function dbFehler($sql,$err) {
global $showErr;
	if ($showErr)
		echo "</td></tr></table><font color='red'>$sql : $err</font><br>";
}
function checkBestellung($status) {
global $db;
	if ($status=="B") { $where="";}  // B = alle Bestellungeb, N = neue, Y = alte
	else { $where="where Bestellung_bezahlt = '$status'";}
	$sql="select * from bestellung $where order by Datum";
	$rs=$db->getAll($sql,DB_FETCHMODE_ASSOC);
	return (count($rs)>0)?count($rs):false;
}
function getBestellKunde($BID) {
global $db;
	$sql="select * from kunde left join bestellung_kunde on Kunden_ID=FK_Kunden_ID where  FK_Bestellungs_ID=$BID";
	$rs=$db->getAll($sql,DB_FETCHMODE_ASSOC);
	return $rs[0]["Kunden_Nr"];
}
function sonderkosten($transID,$data,$id,$f) {
global $db2,$versand,$nachn,$minder,$treuh,$paypal;
	$sql="insert into orderitems (trans_id, parts_id, description, qty, sellprice, unit, ship, discount) values (";
	$sql.=$transID.",".${$id}["ID"].",'".${$id}["TXT"]."',1,".$data.",'mal',0,0)";
	fputs($f,"$transID,".${$id}["ID"].",'".${$id}["TXT"]."',1,$data\n");
	if (!$db2->query($sql)) { return false; }
	else { return true; };
}
function insBestArtikel($zeile,$transID) {
global $db,$db2,$div07,$div16,$f,
	$versandID,$nachnID,$minderID,$treuhID,$paypalID;
	$BID=$zeile["Bestellungs_ID"];
	$sql ="select * from artikel left join artikel_bestellung on Artikel_ID=FK_Artikel_ID ";
	$sql.="left join bestellung on Bestellungs_ID=FK_Bestellungs_ID where Bestellungs_ID=$BID";
	$rs=$db->getAll($sql,DB_FETCHMODE_ASSOC);
	$ok=true;
	foreach ($rs as $zeile) {
		$sql="select * from parts where partnumber='".$zeile["Artikel_Nr"]."'";
		$rs2=$db2->getAll($sql,DB_FETCHMODE_ASSOC);
		if ( $rs2[0]["id"]) {$artID=$rs2[0]["id"]; }
		else { $artID=($zeile["MwSt_Satz"]=="7")?$div07["ID"]:$div16["ID"]; };
		//$preis=round($zeile["Preis"]/($zeile["MwSt_Satz"]+100)*100,2);
		$preis=$zeile["Preis"];
		$notes=$zeile["Artikelname"];
		$vari=split(chr(254),$zeile["Variation"]);
		if ($vari) { for($cnt=0; $cnt<count($vari); $cnt++) {
				$notes.="\n".$vari[$cnt];
				$cnt++;
				$preis+=trim($vari[$cnt]) * $zeile["Anzahl"];
			}
		};
		$opts=split(chr(254),$zeile["Optionen"]);
		if ($opts) { for($cnt=0; $cnt<count($opts); $cnt++) {
				$notes.="\n".$opts[$cnt];
				$cnt++;
				$preis+=trim($opts[$cnt]) * $zeile["Anzahl"];
			}
		}		
		$sql="insert into orderitems (trans_id, parts_id, description, qty, sellprice, unit, ship, discount) values (";
		$sql.=$transID.",".$artID.",'".$notes."',".$zeile["Anzahl"].",".$preis.",'Stck',0,0)";
		if (!$db2->query($sql)) { $ok=false; break; };
		fputs($f,$transID.",".$artID.",'".$zeile["Artikelname"]."',".$zeile["Anzahl"].",".$preis."\n");
		echo "-".$artID." ".$zeile["Anzahl"]." x ".$preis." ".$zeile["Artikelname"]."<br>";
	}
	if ($zeile["Versandkosten"]) {
		$rc=sonderkosten($transID,$zeile["Versandkosten"],"versand",$f);
	}
	if ($zeile["Nachnamebetrag"]) {
		$rc=sonderkosten($transID,$zeile["Nachnamebetrag"],"nachn",$f);
	}	
	if ($zeile["Mindermengenzuschlag"]) {
		$rc=sonderkosten($transID,$zeile["Mindermengenzuschlag"],"minder",$f);
	}	
	if ($zeile["Treuhandkosten"]) {
		$rc=sonderkosten($transID,$zeile["Treuhandkosten"],"treuh",$f);
	}	
	if ($zeile["Paypalkosten"]) {
		$rc=sonderkosten($transID,$zeile["Paypalkosten"],"paypal",$f);
	}	
	if ($ok) {
		$sql="update bestellung set Bestellung_bezahlt='Y' WHERE Bestellungs_ID =$BID";
		$rc=$db->query($sql);
		fputs($f,"ok\n");
		return true;
	} else {
		$sql="delete from orderitems where trans_id=$transID";
		$rc=$db->query($sql);
		$sql="delete from oe where id=$transID";
		$rc=$db->query($sql);
		fputs($f,"Fehler (insBestArtikel)!!!!\n");
		return false;
	}
}
function getBestellung_() {
global $db,$db2,$ERPusr,$f;
	$sql="select * from bestellung where Bestellung_bezahlt='N' order by Bestellungs_ID";
	$rs=$db->getAll($sql,DB_FETCHMODE_ASSOC);
	$ok=true;
	foreach ($rs as $zeile) {
		$kdnr=getBestellKunde($zeile["Bestellungs_ID"]);
		$newID=uniqid (rand());
		$sql="insert into oe (notes) values ('$newID')";
		$rc=$db2->query($sql);
		$sql="select * from oe where notes = '$newID'";
		$rs2=$db2->getAll($sql,DB_FETCHMODE_ASSOC);
		$Bezahlung=$zeile["Bezahlungsart"];
		if ($Bezahlung=="Lastschrift") {
			$sql="select * from kunde where Kunden_Nr=$kdnr";
			$kd=$db->getAll($sql,DB_FETCHMODE_ASSOC);
			$Bezahlung.="\nKontoinhaber: ".$kd[0]["kontoinhaber"]."\n";
			$Bezahlung.="Bankname: ".$kd[0]["bankname"]."\n";
			$Bezahlung.="Blz: ".$kd[0]["blz"]."\n";
			$Bezahlung.="KontoNr: ".$kd[0]["kontonummer"];
		}
		$sql ="update oe set ordnumber=".$zeile["Bestellungs_ID"].", transdate='".$zeile["Datum"]."', intnotes='".$zeile["Anmerkung"];
		$sql.="', customer_id=$kdnr, amount=".($zeile["Rechnungsbetrag"]+$zeile["MwSt"]).", netamount=".$zeile["Rechnungsbetrag"];
		$sql.=", reqdate='".$zeile["Datum"]."', notes='$Bezahlung', taxincluded='f', curr='EUR',employee_id=".$ERPusr["ID"].", vendor_id=0 ";
		$sql.="where id=".$rs2[0]["id"];
		$rc=$db2->query($sql);
		fputs($f,"ordnumber=".$zeile["Bestellungs_ID"].", transdate='".$zeile["Datum"]."', customer_id=$kdnr, amount=".($zeile["Rechnungsbetrag"]+$zeile["MwSt"]).", notes=".$zeile["Bezahlungsart"]."\n");
		echo $rs2[0]["id"]."<br>";
		if (!insBestArtikel($zeile,$rs2[0]["id"])) { $ok=false; break; };
	}
	return $ok;
}
function chkKdData($data) {
global $db2;
	$sql="select * from customer where id = ".$data["Kunden_Nr"];
	$rs=$db2->getAll($sql,DB_FETCHMODE_ASSOC);
	if ($rs[0]["zipcode"]<>$data["Plz"]) $set.="zipcode='".$data["Plz"]."',";
	if ($rs[0]["city"]<>$data["Ort"]) $set.="city='".$data["Ort"]."',";
	if ($rs[0]["land"]<>$data["Land"]) $set.="land='".$data["Land"]."',";
	if ($rs[0]["phone"]<>$data["Tel"])$set.="phone='".$data["Tel"]."',";
	if ($rs[0]["fax"]<>$data["Fax"])  $set.="fax='".$data["Fax"]."',";
	if ($rs[0]["email"]<>$data["Email"])$set.="email='".$data["Email"]."',";
	if ($rs[0]["notes"]<>$data["Beschreibung"])$set.="notes='".$data["Beschreibung"]."',";
	if ($data["Firma"]) {
		if ($rs[0]["name"]<>$data["Firma"]) $set.="set name='".$data["Firma"]."',";
		if ($rs[0]["name2"]<>$data["Anrede"]." ".$data["Vorname"]." ".$data["Nachname"]) $set.="name2='".$data["Anrede"]." ".$data["Vorname"]." ".$data["Nachname"]."',";
	} else {
		if ($rs[0]["name"]<>$data["Nachname"].", ".$data["Vorname"]) $set.="set name='".$data["Nachname"].", ".$data["Vorname"]."',";
	}
	if ($data["Strasse"]) {
		if ($rs[0]["street"]<>$data["Strasse"]) $set.="street='".$data["Strasse"]."',";
	} else if ($data["Postfach"]) {
		if ($rs[0]["street"]<>$data["Postfach"]) $set.="street='".$data["Postfach"]."',";
	};
	if ($set) {
		$sql="update customer set ".substr($set,0,-1)." where id=".$rs[0]["id"];
		$rc=$db2->query($sql);
	}
}
function insKdData($data) {
global $db2;
	$newID=$data["Kunden_ID"];
	$sql="insert into customer (name) values ('$newID')";
	$rc=$db2->query($sql);
	$sql="select * from customer where name = '$newID'";
	$rs=$db2->getAll($sql,DB_FETCHMODE_ASSOC);
	if ($data["Firma"]) { $set.="set name='".$data["Firma"]."',name2='".$data["Anrede"]." ".$data["Vorname"]." ".$data["Nachname"]."',"; }
	else { $set.="set name='".$data["Nachname"].", ".$data["Vorname"]."',"; }
	if ($data["Strasse"]) { $set.="street='".$data["Strasse"]."',"; }
	else if ($data["Postfach"]) { $set.="street='".$data["Postfach"]."',"; };
	$set.="zipcode='".$data["Plz"]."',";
	$set.="city='".$data["Ort"]."',";
	$set.="land='".$data["Land"]."',";
	$set.="phone='".$data["Tel"]."',";
	$set.="fax='".$data["Fax"]."',";
	$set.="email='".$data["Email"]."',";
	$set.="notes='".$data["Beschreibung"]."',";
	$set.="taxincluded='f' ";
	$sql="update customer ".$set;
	$sql.="where id=".$rs[0]["id"];
	$rc=$db2->query($sql);
	return $rs[0]["id"];
}
function checkKunde() {
global $db,$f;
	$sql="select * from kunde left join bestellung_kunde on FK_Kunden_ID=Kunden_ID left join bestellung on Bestellungs_ID=FK_Bestellungs_ID where Bestellung_bezahlt='N'";
	$rs=$db->getAll($sql,DB_FETCHMODE_ASSOC);
	$ok=true;
	$anzahl=count($rs);
	$neu=0; $old=0;
	foreach ($rs as $zeile) {
		if ($zeile["Kunden_Nr"]>0) {
			chkKdData($zeile);
			$old++;
		} else {
			$zeile["Kunden_Nr"]=insKdData($zeile);
			if ($zeile["Kunden_Nr"]>0) {
				$sql="update kunde set Kunden_Nr='".$zeile["Kunden_Nr"]."' where k_ID=".$zeile["k_ID"];
				$rc=$db->query($sql);
			} else {
				$ok=false; break;
			}
			$neu++;
		}
		fputs($f,$zeile["Nachname"]." ".$zeile["Firma"]."\n");
		fputs($f,"\n----------------------------------------\n\n");
	}
	return ($ok)?array($anzahl,$neu,$old):false;
}

function savedata($str) {
global $f;
	foreach ($str as $val) {
		$str.=$val.",";
	}
	fputs($f,substr($str,0,-1)."\n");
}

$f=fopen("./module/export_to_erp/tmp/".date("y-m-dH:i").".shop","w");
$ok=checkBestellung("N");
if ($ok) {
	echo "Es liegen $ok Bestellungen vor. <br>";
	fputs($f,"Es liegen $ok Bestellungen vor. \n");
	$ok=checkKunde();
	if ($ok) {
		echo $ok[0]." Kunden, davon ".$ok[1]." neue(r) Kunde(n).<br>";
		fputs($f,$ok[0]." Kunden, davon ".$ok[1]." neue(r) Kunde(n).\n");
		$ok=getBestellung_();
		if ($ok) { echo "Daten transferiert!";  fputs($f,"Daten transferiert!\n");}
		else { echo "Fehler (Bestellungen)! ! ! ";   fputs($f,"Fehler (Bestellungen)! ! !\n");};
	} else {
		 echo "Fehler (Kunden)! ! ! ";   fputs($f,"Fehler (Kunden)! ! !\n");
	}
} else { echo "Keine Bestellungen!<br>";  fputs($f,"keine Bestellungen\n");};

fclose($f);

if ($backlink == 6) {
    echo "<button type='button' onClick='self.location.href=\"./module_admin_aufruf.php?darstellen=6\"'>Zur&uuml;ck zur Moduladministration</button>";
}
else {
    echo "<button type='button' onClick='self.location.href=\"./module_admin_aufruf.php?darstellen=1&".urlencode($window_source)."=".urlencode($previous_selected_module)."\"'>Zur&uuml;ck zur Modulverwaltung</button>";
}

?>
</body>
</html>
