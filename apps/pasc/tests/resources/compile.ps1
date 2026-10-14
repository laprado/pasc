# create a single resource file testdata.lrs
# should run every time resource files change
$StartDir = Get-Location
$CurrentDir = Join-Path -Path $StartDir -ChildPath "tests"
$CurrentDir = Join-Path -Path $CurrentDir -ChildPath "resources"
Write-Host $StartDir
Write-Host $CurrentDir
Set-Location $CurrentDir
lazres ..\testdata.lrs .\leak_simple.txt .\leak_none.txt .\leak_incomplete.txt .\get-path-ps1.txt
Set-Location $StartDir