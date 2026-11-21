# Installs show-me on Windows with one command:
#   irm https://raw.githubusercontent.com/SmitMachhi/show-me/master/install.ps1 | iex
# Downloads the program, puts it on the PATH, writes the agent skill and installs
# Graphviz when it is missing. Set SHOW_ME_INSTALL_DIR to pick the folder.
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue" # the progress bar makes the download slow
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$dir = if ($env:SHOW_ME_INSTALL_DIR) { $env:SHOW_ME_INSTALL_DIR } else { Join-Path $env:USERPROFILE ".local\bin" }
$exe = Join-Path $dir "show-me.exe"
New-Item -ItemType Directory -Force $dir | Out-Null

# Windows cannot replace one program that runs, so stop the old daemon first.
if (Test-Path $exe) { & $exe stop | Out-Null }
Write-Host "Downloading show-me to $dir"
Invoke-WebRequest -UseBasicParsing -OutFile $exe "https://github.com/SmitMachhi/show-me/releases/latest/download/show-me-windows-x86_64.exe"
& $exe setup

# Graphviz draws the diagrams. A failure here leaves show-me installed and says what to run.
$dot = (Get-Command dot -ErrorAction SilentlyContinue) -or (Test-Path "C:\Program Files\Graphviz\bin\dot.exe")
if (-not $dot) {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "Installing Graphviz"
        winget install --id Graphviz.Graphviz --exact --silent --accept-source-agreements --accept-package-agreements
    }
    if (-not (Test-Path "C:\Program Files\Graphviz\bin\dot.exe")) {
        Write-Warning "Graphviz was not installed. Diagrams need it: run 'winget install Graphviz.Graphviz'."
    }
}

# A new terminal finds show-me only if its folder is on the PATH.
$userPath = "" + [Environment]::GetEnvironmentVariable("Path", "User")
if (($userPath -split ";") -notcontains $dir) {
    [Environment]::SetEnvironmentVariable("Path", ($userPath.TrimEnd(";") + ";" + $dir), "User")
    $env:Path += ";" + $dir
    Write-Host "Added $dir to the PATH. Open one new terminal to use it."
}

Write-Host "show-me $(& $exe --version) is installed."
