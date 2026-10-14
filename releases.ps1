#****************************************************************
# help functions 
#****************************************************************
function Exit-Script {
    Exit
  }
  
  function Test-CommandExists
  {
    param ($command)
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = "stop"
    try {
      if (Get-Command $command) {
        RETURN $true
      }
    } catch {
      RETURN $false
    } finally {
      $ErrorActionPreference=$oldPreference
    }
  }

  function Build-TargetPath {
    Write-Host "[INFO ] Check if target path exists..."
    if (Test-Path -Path "releases") {
      Write-Host "[INFO ] path 'releases' already exists."
    } else {
      Write-Host "[INFO ] creating path 'releases' ..."
      New-Item -Path "releases" -ItemType Directory
    }
    Write-Host "[INFO ] Done."
  }

  function Build-Project {
    param (
        [Parameter()]
        [string]$ProjectName,
     
        [Parameter()]
        [string]$TargetOS,

        [Parameter()]
        [string]$TargetCPU
    )

    if (Test-CommandExists "lazbuild") {
        Write-Host "[INFO ] lazbuild found."
      } else {
        Write-Host "[ERROR] lazbuild not found."
        Exit-Script
    }

    Write-Host "[INFO ] env:path => $env:path"
    if ($null -eq $env:path)
    {
      Write-Host "[INFO ] Adjusting path variable"
      $env:path = $env:PATH
    }

    $ArgList = "--os=" + $TargetOS + " --cpu=" + $TargetCPU + " " + $ProjectName
    if ($TargetOS -eq "darwin") {
        $ArgList = $ArgList + " --ws=cocoa"
    }
    $ArgList = $ArgList + " --build-mode=release"

    Write-Host "[INFO ] $ArgList" 

    $LazBuild = "lazbuid"
    if ($TargetOS -eq "darwin") {
        $LazBuild = "/Applications/Lazarus/lazbuild"
    }
    
    Start-Process -FilePath $LazBuild -ArgumentList $ArgList -Wait

    $CurrentPath = Get-Location
    $ReleasePath = Join-Path -Path $CurrentPath -ChildPath "releases"
    
    $Executable = Join-Path -Path $CurrentPath -ChildPath "apps/pasc/pasc"
    if ($TargetOS -eq "win64") {
        $Executable = Join-Path -Path $CurrentPath -ChildPath "apps/pasc/pasc.exe"
    } 
    $ZipFile = "pasc-" + $TargetCPU + "-" + $TargetOS + ".zip"
    $Archive = Join-Path -Path $ReleasePath -ChildPath $ZipFile
    Compress-Archive -Path $Executable -CompressionLevel Fastest -DestinationPath $Archive -Force
  }

  Build-TargetPath

  Build-Project -ProjectName "apps/pasc/pasc.lpi" -TargetOS "win64" -TargetCPU "x86_64"
  Build-Project -ProjectName "apps/pasc/pasc.lpi" -TargetOS "linux" -TargetCPU "x86_64"
  Build-Project -ProjectName "apps/pasc/pasc.lpi" -TargetOS "darwin" -TargetCPU "x86_64"
  Build-Project -ProjectName "apps/pasc/pasc.lpi" -TargetOS "linux" -TargetCPU "aarch64"
  Build-Project -ProjectName "apps/pasc/pasc.lpi" -TargetOS "darwin" -TargetCPU "aarch64"