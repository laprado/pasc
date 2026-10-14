# create a single resource file testdata.lrs
# should run every time resource files change
StartDir=$PWD
CurrentDir=$StartDir"/tests/resources"
echo $StartDir
echo $CurrentDir
cd $CurrentDir
lazres ../testdata.lrs ./leak_simple.txt ./leak_none.txt ./leak_incomplete.txt ./get-path-ps1.txt
cd $StartDir