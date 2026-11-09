#requires -Version 5.1
<#
.SYNOPSIS
    Creates the Prodaja file share on a domain server.

.DESCRIPTION
    Creates the folder, publishes it as an SMB share, sets NTFS permissions and
    writes a small sample file. The script is idempotent - running it again
    changes nothing.

    Run this on the domain controller (or on the file server) as Administrator.

.PARAMETER Path
    Local folder that will be shared. Default: C:\Shares\ProdajaShare

.PARAMETER ShareName
    SMB share name. Default: ProdajaShare

.PARAMETER ReadGroup
    Group that gets read access. Default: <domain>\Domain Users

.PARAMETER FullGroup
    Group that gets full access. Default: <domain>\Domain Admins

.EXAMPLE
    .\Setup-ProdajaShare.ps1

.EXAMPLE
    .\Setup-ProdajaShare.ps1 -Path D:\Shares\ProdajaShare -ShareName ProdajaShare
#>
[CmdletBinding()]
param(
    [string]$Path = 'C:\Shares\ProdajaShare',
    [string]$ShareName = 'ProdajaShare',
    [string]$ReadGroup = "$env:USERDOMAIN\Domain Users",
    [string]$FullGroup = "$env:USERDOMAIN\Domain Admins"
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    Write-Host "Created folder: $Path"
}
else {
    Write-Host "Folder exists:  $Path"
}

$sample = Join-Path $Path 'README.txt'
if (-not (Test-Path -LiteralPath $sample)) {
    @(
        'Prodaja share - demo.lab'
        "UNC path: \\$env:COMPUTERNAME\$ShareName"
        'Mapped to P: by GPO_Drive_Mapping_Prodaja.'
    ) | Set-Content -LiteralPath $sample -Encoding UTF8
    Write-Host "Created sample: $sample"
}

if (Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue) {
    Write-Host "Share exists:   \\$env:COMPUTERNAME\$ShareName"
}
else {
    New-SmbShare -Name $ShareName -Path $Path -FullAccess $FullGroup -ReadAccess $ReadGroup | Out-Null
    Write-Host "Created share:  \\$env:COMPUTERNAME\$ShareName"
}

# NTFS permissions (share permissions are set above)
icacls $Path /grant "${ReadGroup}:(OI)(CI)(RX)" /T /C | Out-Null
icacls $Path /grant "${FullGroup}:(OI)(CI)(F)" /T /C | Out-Null

Write-Host ''
Get-SmbShare -Name $ShareName | Format-List Name,Path,Description
Get-SmbShareAccess -Name $ShareName | Format-Table -AutoSize

Write-Host ''
Write-Host "Use this UNC path in GPO_Drive_Mapping_Prodaja: \\$env:COMPUTERNAME\$ShareName"
