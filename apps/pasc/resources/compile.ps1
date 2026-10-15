# create a single resource file pasc.lrs
# should run every time resource files change
$StartDir = Get-Location
$CurrentDir = Join-Path -Path $StartDir -ChildPath "resources"
Write-Host $StartDir
Write-Host $CurrentDir
Set-Location $CurrentDir
lazres `
  ..\src\utils\pasc.lrs `
  .\gitignore.txt `
  .\launchjson.txt `
  .\tasksjson.txt `
  .\projectlpi.txt `
  .\projectlpr.txt `
  .\tests\fpcunitprojectlpi.txt `
  .\tests\fpcunitprojectlpr.txt `
  .\tests\testcase1pas.txt `
  .\docs\introduction.txt `
  .\docs\quickstart.txt `
  .\workspace\pascjson.txt `
  .\workspace\packagelpk.txt `
  .\workspace\packageunitpas.txt `
  .\templates\cli\clicommandcount.txt `
  .\templates\cli\clicommandgreet.txt `
  .\templates\cli\clilpi.txt `
  .\templates\cli\clilpr.txt `
  .\templates\cli\clitestcommandcount.txt `
  .\templates\cli\clitestcommandgreet.txt `
  .\templates\cli\clitestlpi.txt `
  .\templates\cli\clitestlpr.txt `
  .\templates\cli\clitestoutput.txt `
  .\templates\web\webbuild.txt `
  .\templates\web\webcustomerspayloads.txt `
  .\templates\web\webcustomersroutes.txt `
  .\templates\web\webcustomersservice.txt `
  .\templates\web\webhealthroutes.txt `
  .\templates\web\weblpi.txt `
  .\templates\web\weblpr.txt `
  .\templates\web\webrepoconfig.txt `
  .\templates\web\webrepocustomers.txt `
  .\templates\web\webrepomodels.txt `
  .\templates\web\webshutdown.txt `
  .\templates\web\webtestcustomerspayloads.txt `
  .\templates\web\webtestcustomersservice.txt `
  .\templates\web\webtestfakerepository.txt `
  .\templates\web\webtestlpi.txt `
  .\templates\web\webtestlpr.txt `
  ..\..\..\LICENSE `
  ..\..\..\THIRD-PARTY-NOTICES.md
Set-Location $StartDir