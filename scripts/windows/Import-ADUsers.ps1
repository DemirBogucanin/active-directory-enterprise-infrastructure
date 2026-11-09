#requires -Version 5.1
<#
.SYNOPSIS
    Creates Active Directory users from a CSV file.

.DESCRIPTION
    Reads Firstname, Lastname, Username, OU and Department from the CSV and
    creates a user in OU=<OU>,<DomainDN>. Existing users and missing OUs are
    skipped and reported. The script never stores credentials.

.PARAMETER CsvPath
    Path to the CSV file. Save it as UTF-8 (with or without BOM) or ASCII.

.PARAMETER DomainDN
    Distinguished name of the domain, for example DC=demo,DC=lab.

.PARAMETER InitialPassword
    Optional initial password. When omitted, accounts are created disabled and
    an administrator must enable them later.

.EXAMPLE
    .\Import-ADUsers.ps1 -CsvPath ..\..\data\korisnici.csv -DomainDN "DC=demo,DC=lab" -WhatIf

.EXAMPLE
    .\Import-ADUsers.ps1 -CsvPath ..\..\data\korisnici.csv -DomainDN "DC=demo,DC=lab"
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$CsvPath,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^DC=')]
    [string]$DomainDN,

    [string]$InitialPassword
)

Import-Module ActiveDirectory -ErrorAction Stop

$domain = Get-ADDomain
$dnsRoot = $domain.DNSRoot

$rows = Import-Csv -LiteralPath $CsvPath -Encoding UTF8
if (-not $rows) {
    throw "CSV file '$CsvPath' contains no data rows."
}

$results = foreach ($row in $rows) {
    $sam = "$($row.Username)".Trim()
    $ou = "$($row.OU)".Trim()
    $given = "$($row.Firstname)".Trim()
    $surname = "$($row.Lastname)".Trim()
    $display = "$given $surname"
    $upn = "$sam@$dnsRoot"
    $ouDn = "OU=$ou,$DomainDN"

    if (-not $sam -or -not $ou) {
        [pscustomobject]@{ Username = $sam; Status = 'Skipped'; Detail = 'Missing Username or OU' }
        continue
    }

    if (-not (Get-ADOrganizationalUnit -Identity $ouDn -ErrorAction SilentlyContinue)) {
        [pscustomobject]@{ Username = $sam; Status = 'Skipped'; Detail = "OU not found: $ouDn" }
        continue
    }

    if (Get-ADUser -Filter "sAMAccountName -eq '$sam'" -ErrorAction SilentlyContinue) {
        [pscustomobject]@{ Username = $sam; Status = 'Skipped'; Detail = 'User already exists' }
        continue
    }

    $newUser = @{
        Name              = $display
        GivenName         = $given
        Surname           = $surname
        DisplayName       = $display
        SamAccountName    = $sam
        UserPrincipalName = $upn
        Path              = $ouDn
        Enabled           = $false
    }

    if ("$($row.Department)".Trim()) {
        $newUser.Department = "$($row.Department)".Trim()
    }

    if ($InitialPassword) {
        $newUser.AccountPassword = ConvertTo-SecureString -String $InitialPassword -AsPlainText -Force
        $newUser.Enabled = $true
        $newUser.ChangePasswordAtLogon = $true
    }

    if ($PSCmdlet.ShouldProcess($upn, "Create AD user in $ouDn")) {
        New-ADUser @newUser
        [pscustomobject]@{ Username = $sam; Status = 'Created'; Detail = $ouDn }
    }
    else {
        [pscustomobject]@{ Username = $sam; Status = 'WhatIf'; Detail = $ouDn }
    }
}

$results | Format-Table -AutoSize

$created = @($results | Where-Object Status -eq 'Created').Count
$skipped = @($results | Where-Object Status -eq 'Skipped').Count
Write-Host ("Created: {0}  Skipped: {1}" -f $created, $skipped)
