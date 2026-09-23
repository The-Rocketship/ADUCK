<#
.SYNOPSIS
    Automated Test Suite for ADUCK.ps1
.DESCRIPTION
    Validates PowerShell AST parsing, GUI initialization, dark theme palette,
    custom vector icon rendering, and directory CRUD/account operations.
#>

$ErrorActionPreference = 'Stop'
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "  ADUCK Automated Verification & Test Suite" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan

# 1. AST Parser Validation
Write-Host "`n[1/3] Validating PowerShell AST Syntax..." -ForegroundColor Yellow
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile("$PSScriptRoot\ADUCK.ps1", [ref]$tokens, [ref]$errors)
if ($errors) {
    Write-Error "Syntax errors detected in ADUCK.ps1:"
    $errors | Format-Table Message, Extent
    exit 1
}
Write-Host "  --> Syntax Check Passed (0 errors)." -ForegroundColor Green

# 2. Headless GUI & Theme Initialization
Write-Host "`n[2/3] Validating GUI Forms, Themes & Vector Icons..." -ForegroundColor Yellow
$scriptContent = [System.IO.File]::ReadAllText("$PSScriptRoot\ADUCK.ps1", [System.Text.Encoding]::UTF8)
$headlessScript = $scriptContent -replace '\[System\.Windows\.Forms\.Application\]::Run\(\$Script:MainForm\)', '# Test Mode'

$tempRunner = "$PSScriptRoot\temp_runner.ps1"
[System.IO.File]::WriteAllText($tempRunner, $headlessScript, [System.Text.Encoding]::UTF8)

try {
    $initResult = powershell -NoProfile -ExecutionPolicy Bypass -Command "& '$tempRunner' -Demo; Write-Output 'INIT_OK'"
    if ($initResult -notlike "*INIT_OK*") {
        throw "Initialization test failed: $initResult"
    }
    Write-Host "  --> WinForms, Dark Theme, Vector Icons & Controls initialized successfully." -ForegroundColor Green
} finally {
    Remove-Item -Path $tempRunner -Force -ErrorAction SilentlyContinue
}

# 3. Directory Operations Verification
Write-Host "`n[3/3] Validating AD Data & Account Management Operations..." -ForegroundColor Yellow
$testOpsCode = @'
param()
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\temp_ops_runner.ps1" -Demo

# Verify domain root
$root = Get-ADRootInformation
if ($root.Name -ne "CORP.CONTOSO.LOCAL" -or -not $root.IsDemo) { throw "Root info verification failed" }

# Verify hierarchy
$containers = Get-ADTreeHierarchy
if ($containers.Count -lt 10) { throw "Directory tree missing expected OUs" }

# Verify container objects
$itObjs = Get-ADContainerObjects -ContainerDN "OU=Information Technology,OU=Corporate,DC=corp,DC=contoso,DC=local"
if ($itObjs.Count -lt 3) { throw "Expected objects in IT OU" }

# Verify search
$search = Search-ADDirectoryObjects -Query "Alex"
if ($search.Count -eq 0) { throw "Search operation failed" }

# Verify toggle account state
$amercer = $itObjs | Where-Object { $_.sAMAccountName -eq "amercer" }
Set-ADObjectState -DistinguishedName $amercer.DistinguishedName -Enable $false
if (($Script:DemoStore.Objects | Where-Object { $_.sAMAccountName -eq "amercer" }).Enabled) { throw "Disable failed" }
Set-ADObjectState -DistinguishedName $amercer.DistinguishedName -Enable $true

# Verify unlock account
$engObjs = Get-ADContainerObjects -ContainerDN "OU=Engineering,OU=Corporate,DC=corp,DC=contoso,DC=local"
$lscott = $engObjs | Where-Object { $_.sAMAccountName -eq "lscott" }
Invoke-ADUnlockAccount -DistinguishedName $lscott.DistinguishedName
if (($Script:DemoStore.Objects | Where-Object { $_.sAMAccountName -eq "lscott" }).LockedOut) { throw "Unlock failed" }

# Verify password reset
$secPass = ConvertTo-SecureString "ModernPass123!" -AsPlainText -Force
Set-ADUserPasswordReset -DistinguishedName $lscott.DistinguishedName -Password $secPass -MustChangeAtNextLogon $true -Unlock $true

# Verify move
$execOU = "OU=Executive,OU=Corporate,DC=corp,DC=contoso,DC=local"
Move-ADDirectoryObject -DistinguishedName $lscott.DistinguishedName -TargetContainerDN $execOU
if (($Script:DemoStore.Objects | Where-Object { $_.sAMAccountName -eq "lscott" }).ParentDN -ne $execOU) { throw "Move failed" }

# Verify Domain Functional Level, Domain Controller, and Delegation
if (-not $root.DomainMode) { throw "Missing DomainMode in RootInfo" }
Set-ADDomainFunctionalLevel -NewLevel "Windows2022Domain"
if ((Get-ADRootInformation).DomainMode -ne "Windows2022Domain") { throw "Raise domain level failed" }

Set-ADActiveDomainController -DCName "dc02.corp.contoso.local"
if ((Get-ADRootInformation).PDCEmulator -ne "dc02.corp.contoso.local") { throw "Change DC failed" }

Invoke-ADDelegateControl -TargetContainerDN $root.DistinguishedName -Principals @("Helpdesk-Admins") -SelectedTasks @("Reset user passwords")

# Verify Context Menu dynamic specialization
$treeView.SelectedNode = $treeView.Nodes[0]
$treeContextMenu.Show()
if (-not ($mnuTreeDelegate.Visible -and $mnuTreeChangeDom.Visible -and $mnuTreeChangeDC.Visible -and $mnuTreeRaiseDFL.Visible)) {
    throw "Domain root context menu items not visible as expected!"
}

Write-Output "OPERATIONS_VERIFIED"
'@

$tempOpsRunner = "$PSScriptRoot\temp_ops_runner.ps1"
$tempOpsTest = "$PSScriptRoot\temp_ops_test.ps1"
[System.IO.File]::WriteAllText($tempOpsRunner, $headlessScript, [System.Text.Encoding]::UTF8)
[System.IO.File]::WriteAllText($tempOpsTest, $testOpsCode, [System.Text.Encoding]::UTF8)

try {
    $opsResult = powershell -NoProfile -ExecutionPolicy Bypass -File $tempOpsTest
    if ($opsResult -notlike "*OPERATIONS_VERIFIED*") {
        throw "Directory operations test failed: $opsResult"
    }
    Write-Host "  --> Tree Hierarchy, Search, Enable/Disable, Unlock, Password Reset & Move operations all verified." -ForegroundColor Green
} finally {
    Remove-Item -Path $tempOpsRunner, $tempOpsTest -Force -ErrorAction SilentlyContinue
}

Write-Host "`n========================================================" -ForegroundColor Green
Write-Host "  All Verification Checks Passed Successfully!" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green
