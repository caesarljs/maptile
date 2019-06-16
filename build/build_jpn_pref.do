*! 20mar2019  Chigusa Okamoto, okamoto.chigusa.econ@gmail.com

* imports 2018 Administrative Zones shapefile into Stata format


/*******************************

** INPUT FILES ** 
- N03-180101_GML.zip
	Provided by the National Land Numerical Information download service,
	Administrative Zones Data.
	
	In Japanese: http://nlftp.mlit.go.jp/ksj/gml/datalist/KsjTmplt-N03-v2_3.html
	In English: http://nlftp.mlit.go.jp/ksj-e/gml/datalist/KsjTmplt-N03-v2_3.html
	Main webpage, in English: http://nlftp.mlit.go.jp/ksj-e/gml/gml_datalist.html
		
- N03-180101_GML-simple.zip
	A transformed version of the National Land Numerical Information shapefile,
	with its detail simplified and file size reduced.
	Made from N03-180101_GML.zip by using "$raw/simplify_jpn_pref.sh".	
	
- pref_code.dta
	Contains a mapping between JIS X0401 code for prefecture and prefecture name.
	(reference) http://nlftp.mlit.go.jp/ksj/gml/codelist/PrefCd.html
	(reference) http://nlftp.mlit.go.jp/ksj-e/gml/codelist/PrefCd.html

This map is based on the Digital Map (Basic Geospatial Informaion) published
by Geospatial Information Authority of Japan with its approval under 
the article 30 of The Survey Act.
(Approval Number JYOU-SHI No.1575 2018)　	
	
*******************************/


*** Step 0: Initialize

* Check if run using -project-
return clear
capture project, doinfo
if (_rc==0 & !mi(r(pname))) global root `r(pdir)'  // run using -project-
else {  // running directly

	global root "/Users/michael/Documents/git_repos/maptile_geo_templates/build"

	* Disable project (since running do-files directly)
	cap program drop project
	program define project
		di "Project is disabled, skipping project command. (To re-enable, run -{stata program drop project}-)"
	end
	
}

* Specify subdirectories
global raw "$root/raw_data/jpn_pref"
global out "$root/geo_templates/jpn_pref"
global test "$root/tests/jpn_pref"

* Add utility programs to path
adopath ++ "$root/util"
mata: mata mlib index

* Tell -project- that we use -save12-
project, original("$root/util/save12.ado")

* Tell -project- that we use -mergepoly- 
project, original("$root/util/mergepoly.ado")
project, original("$root/util/mergepoly.hlp")

* Tell -project- that we use -shp2dta-
project, original("$root/util/shp2dta.ado")

* Tell -project- that we use -fieldarea- 
project, original("$root/util/fieldarea.ado")
project, original("$root/util/fieldarea.hlp")
project, original("$root/util/lfieldarea.mlib")

*** Step 1: Unzip & convert shape file to dta
project, relies_on("$raw/N03-180101_GML.zip")  // original shapefile
project, relies_on("$raw/simplify_jpn_pref.sh")  // shapefile simplification code
project, original("$raw/N03-180101_GML-simple.zip")  // simplified shapefile

cd "$raw"
unzipfile "$raw/N03-180101_GML-simple.zip", replace

shp2dta using "$raw/jpn_mun2018", database("$out/jpn_mun2018_database") ///
	coordinates("$out/jpn_mun2018_coords") replace


*** Step 2: Clean database	
* Encoding dta Shift-JIS to Unicode
clear
cd "$out"
unicode encoding set "Shift_JIS"
unicode retranslate "jpn_mun2018_database.dta", replace
unicode erasebackups, badidea

* Attach prefecture code 
use "$out/jpn_mun2018_database.dta", clear
keep N03_001 N03_007 _ID
rename (N03_001 N03_007) (prefname_jpn mun)
project, original("$raw/pref_code.dta") preserve
merge m:1 prefname_jpn using "$raw/pref_code", assert(3) nogen
destring mun, replace

* Remove category name from prefname/prefname_jpn (ex. Tokyo-to -> Tokyo)
replace prefname_jpn = substr(prefname_jpn, 1, strlen(prefname_jpn)-3) if pref != 1
replace prefname = regexr(prefname, "-[a-z]+","") if pref != 1

* Remove _ID without _X & _Y
merge 1:m _ID using "$out/jpn_mun2018_coords.dta", keepusing(_ID) assert(1 3) keep(3) nogen
duplicates drop

* Drop the Northern Territories and Ogasawara Village
drop if mun == 13421
drop if inrange(mun, 1695, 1700)
save "$out/jpn_mun2018_database.dta", replace


*** Step 3: Clean coordinates
use "$out/jpn_mun2018_coords.dta", clear
merge m:1 _ID using "$out/jpn_mun2018_database.dta", assert(1 3) keep(3) nogen
save "$out/jpn_mun2018_coords.dta", replace



*** Step 4: Merge municipality-level polygons into prefecture-level polygons
use "$out/jpn_mun2018_database.dta", clear
mergepoly _ID using "$out/jpn_mun2018_coords.dta", ///
	coordinates("$out/jpn_pref_coords.dta") ///
	by(pref) replace

order _ID
compress
save12 "$out/jpn_pref_database.dta", replace
project, creates("$out/jpn_pref_database.dta")

* Resave coords in Stata 12 format
use "$out/jpn_pref_coords.dta", clear
compress
save12 "$out/jpn_pref_coords.dta", replace
project, creates("$out/jpn_pref_coords.dta")


*** Step 5: Create shapefiles for options

** Option 1. Shapfile for option "simple": remove small islands
* Generate island_id for each land
use "$out/jpn_pref_coords.dta", clear
gen island_id = 1 if _X == . & _Y == .
replace island_id = sum(island_id)

* Calculate each island's area (squared km)
preserve
fieldarea _X _Y, generate(area) id(island_id) unit(sqkm)
tempfile area
save `area'
restore 

* drop small islands 
merge m:1 island_id using `area', assert(3) nogen
keep if area > 500
drop island_id area
sort _ID, stable
save12 "$out/jpn_pref_coords_simple.dta", replace
project, creates("$out/jpn_pref_coords_simple.dta")


** Option 2. Shapefile for option "compressed": move Okinawa prefecture to topleft
use "$out/jpn_pref_coords.dta", clear
merge m:1 _ID using "$out/jpn_pref_database.dta", assert(3) nogen
replace _X = _X + 6 if prefname == "Okinawa"
replace _Y = _Y + 16 if prefname == "Okinawa"
sort _ID, stable
keep _ID _X _Y
save12 "$out/jpn_pref_coords_compressed.dta", replace
project, creates("$out/jpn_pref_coords_compressed.dta")


** Option 3. Shapefile for options "simple" & "compressed"
use "$out/jpn_pref_coords_simple.dta", clear
merge m:1 _ID using "$out/jpn_pref_database.dta", assert(3) nogen
replace _X = _X + 6 if prefname == "Okinawa"
replace _Y = _Y + 16 if prefname == "Okinawa"
sort _ID, stable
keep _ID _X _Y
save12 "$out/jpn_pref_coords_simple_compressed.dta", replace
project, creates("$out/jpn_pref_coords_simple_compressed.dta")



*** Step 6: Clean up extra files
erase "$out/jpn_mun2018_database.dta"
erase "$out/jpn_mun2018_coords.dta"


*** Step 7: Reference other files using -project-
project, relies_on("$root/readme.txt")
project, relies_on("$out/jpn_pref_maptile.ado")
project, relies_on("$out/jpn_pref_maptile.smcl")



*** Step 8: Test geo-specific options
use "$out/jpn_pref_database.dta", clear 
rename _ID test


maptile test, geo(jpn_pref) geofolder($out) ///
	savegraph("$test/jpn_pref_noopt.png") resolution(0.25) replace
project, creates("$test/jpn_pref_noopt.png") preserve


maptile test, geo(jpn_pref) geofolder($out) simple ///
	savegraph("$test/jpn_pref_simple.png") resolution(0.25) replace
project, creates("$test/jpn_pref_simple.png") preserve


maptile test, geo(jpn_pref) geofolder($out) compressed ///
	savegraph("$test/jpn_pref_compressed.png") resolution(0.25) replace
project, creates("$test/jpn_pref_compressed.png") preserve


maptile test, geo(jpn_pref) geofolder($out) simple compressed ///
	savegraph("$test/jpn_pref_simple_compressed.png") resolution(0.25) replace
project, creates("$test/jpn_pref_simple_compressed.png") preserve

* Test different geoids
foreach geoid in pref prefname prefname_jpn {

	maptile test, geo(jpn_pref) geofolder($out) geoid(`geoid') ///
		savegraph("$test/jpn_pref_geoid_`geoid'.png") resolution(0.25) replace
	project, creates("$test/jpn_pref_geoid_`geoid'.png") preserve

}
