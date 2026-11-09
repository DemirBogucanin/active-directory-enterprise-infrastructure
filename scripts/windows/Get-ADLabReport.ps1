#requires -Version 5.1
<#
.SYNOPSIS
    Read-only inventory of the Active Directory lab.

.DESCRIPTION
    Collects domain, OU, user, group, GPO, drive-mapping, DHCP, DNS and network
    data and writes a single Markdown report. The script makes NO changes to the
    system.

.PARAMETER OutFile
    Where to write the Markdown report. Defaults to the current user's Desktop.

.PARAMETER CsvPath
    Optional path to a CSV file whose header and first rows should be included.

.EXAMPLE
    .\Get-ADLabReport.ps1 -CsvPath ..\..\data\korisnici.csv
#>
[CmdletBinding()]
param(
    [string]$OutFile = (Join-Path ([Environment]::GetFolderPath('Desktop')) 'ad-lab-report.md'),
    [string]$CsvPath
)

$ErrorActionPreference = 'Continue'
$script:sb = New-Object System.Text.StringBuilder

function Add-Line {
    param([string]$Text = '')
    [void]$script:sb.AppendLine($Text)
}

function Add-Section {
    param([string]$Title)
    Add-Line ''
    Add-Line "## $Title"
    Add-Line ''
}

function Try-Run {
    param([string]$Label, [scriptblock]$Block)
    try {
        & $Block
    }
    catch {
        Add-Line "> _N/A - $Label : $($_.Exception.Message)_"
        Add-Line ''
    }
}

Add-Line '# AD Lab Inventory'
Add-Line ''
Add-Line "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') on $env:COMPUTERNAME"

Add-Section '0. Environment'
Add-Line '| Key | Value |'
Add-Line '|---|---|'
Add-Line "| Hostname | $env:COMPUTERNAME |"
Add-Line "| User | $env:USERNAME |"
Add-Line "| OS | $((Get-CimInstance Win32_OperatingSystem).Caption) |"
Add-Line "| PowerShell | $($PSVersionTable.PSVersion) |"
Add-Line "| Domain (env) | $env:USERDNSDOMAIN |"

$adModule = Get-Module -ListAvailable -Name ActiveDirectory | Select-Object -First 1
$domain = $null

if (-not $adModule) {
    Add-Line ''
    Add-Line '> **ActiveDirectory module not found.**'
    Add-Line '> Run this inside the Windows Server VM as Administrator, or install RSAT:'
    Add-Line '> `Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0`'
}
else {
    Import-Module ActiveDirectory -ErrorAction SilentlyContinue

    Add-Section '1. Domain'
    Try-Run 'Get-ADDomain' {
        $domain = Get-ADDomain
        $forest = Get-ADForest
        Add-Line '| Key | Value |'
        Add-Line '|---|---|'
        Add-Line "| NetBIOS name | $($domain.NetBIOSName) |"
        Add-Line "| DNS root | $($domain.DNSRoot) |"
        Add-Line "| Distinguished name | $($domain.DistinguishedName) |"
        Add-Line "| Domain mode | $($domain.DomainMode) |"
        Add-Line "| Forest mode | $($forest.ForestMode) |"
        Add-Line "| PDC emulator | $($domain.PDCEmulator) |"
        Add-Line "| Domain controllers | $($domain.ReplicaDirectoryServers -join ', ') |"
    }

    Add-Section '2. OU structure'
    Try-Run 'OUs' {
        Add-Line '```text'
        Get-ADOrganizationalUnit -Filter * |
            Sort-Object DistinguishedName |
            ForEach-Object { Add-Line $_.DistinguishedName }
        Add-Line '```'
    }

    Add-Section '3. Users (first 50)'
    Try-Run 'Users' {
        $users = Get-ADUser -Filter * -Properties Enabled, Department |
            Sort-Object SamAccountName
        Add-Line "Total users: $($users.Count)"
        Add-Line ''
        Add-Line '| SamAccountName | Name | Enabled | Department | OU |'
        Add-Line '|---|---|---|---|---|'
        $users | Select-Object -First 50 | ForEach-Object {
            $ou = ($_.DistinguishedName -replace '^CN=[^,]+,', '')
            Add-Line "| $($_.SamAccountName) | $($_.Name) | $($_.Enabled) | $($_.Department) | $ou |"
        }
    }

    Add-Section '4. Groups'
    Try-Run 'Groups' {
        Add-Line '| Group | Scope | Category | OU |'
        Add-Line '|---|---|---|---|'
        Get-ADGroup -Filter * -Properties GroupScope, GroupCategory |
            Sort-Object Name |
            ForEach-Object {
                $ou = ($_.DistinguishedName -replace '^CN=[^,]+,', '')
                Add-Line "| $($_.Name) | $($_.GroupScope) | $($_.GroupCategory) | $ou |"
            }
    }

    Add-Section '5. Group Policy Objects'
    Try-Run 'GPO' {
        Add-Line '| GPO | Status | Modified |'
        Add-Line '|---|---|---|'
        Get-GPO -All | Sort-Object DisplayName | ForEach-Object {
            Add-Line "| $($_.DisplayName) | $($_.GpoStatus) | $($_.ModificationTime) |"
        }
    }

    Add-Section '6. Drive mappings (GPO Preferences)'
    Try-Run 'Drives.xml' {
        $sysvol = "\\$($domain.DNSRoot)\SYSVOL\$($domain.DNSRoot)\Policies"
        $found = Get-ChildItem -Path $sysvol -Recurse -Filter 'Drives.xml' -ErrorAction SilentlyContinue
        if (-not $found) {
            Add-Line '_No Drives.xml found in SYSVOL - the drive may be mapped by a logon script._'
        }
        else {
            foreach ($f in $found) {
                Add-Line "File: $($f.FullName)"
                Add-Line ''
                [xml]$x = Get-Content -LiteralPath $f.FullName
                $x.Drives.Drive | ForEach-Object {
                    Add-Line '| Property | Value |'
                    Add-Line '|---|---|'
                    Add-Line "| Drive letter | $($_.Properties.Letter) |"
                    Add-Line "| Path | $($_.Properties.Path) |"
                    Add-Line "| Label | $($_.Properties.Label) |"
                    Add-Line "| Action | $($_.Properties.Action) |"
                    Add-Line ''
                }
            }
        }
    }

    Add-Section '7. DHCP'
    Try-Run 'DHCP' {
        if (-not (Get-Module -ListAvailable -Name DhcpServer)) {
            Add-Line '_DhcpServer module not available - role not installed on this machine._'
        }
        else {
            Import-Module DhcpServer
            Add-Line 'Authorization in AD:'
            Add-Line ''
            Get-DhcpServerInDC | ForEach-Object { Add-Line "- $($_.DnsName) / $($_.IPAddress)" }
            Add-Line ''
            Add-Line 'Scopes:'
            Add-Line ''
            Add-Line '| ScopeId | Name | SubnetMask | StartRange | EndRange | State |'
            Add-Line '|---|---|---|---|---|---|'
            Get-DhcpServerv4Scope | ForEach-Object {
                Add-Line "| $($_.ScopeId) | $($_.Name) | $($_.SubnetMask) | $($_.StartRange) | $($_.EndRange) | $($_.State) |"
            }
            Add-Line ''
            Add-Line 'Scope options:'
            Get-DhcpServerv4Scope | ForEach-Object {
                $id = $_.ScopeId
                Get-DhcpServerv4OptionValue -ScopeId $id -ErrorAction SilentlyContinue |
                    ForEach-Object {
                        Add-Line "- Scope $id - OptionId $($_.OptionId): $($_.Value -join ', ')"
                    }
            }
        }
    }

    Add-Section '8. DNS'
    Try-Run 'DNS' {
        Add-Line 'Zones:'
        Get-DnsServerZone | ForEach-Object {
            Add-Line "- $($_.ZoneName) ($($_.ZoneType), DS-integrated: $($_.IsDsIntegrated))"
        }
        Add-Line ''
        if ($domain) {
            Add-Line "A / CNAME records in $($domain.DNSRoot):"
            Add-Line ''
            Add-Line '| Name | Type | Value |'
            Add-Line '|---|---|---|'
            Get-DnsServerResourceRecord -ZoneName $domain.DNSRoot -ErrorAction SilentlyContinue |
                Where-Object { $_.RecordType -in 'A', 'AAAA', 'CNAME' } |
                ForEach-Object {
                    $val = if ($_.RecordType -eq 'A') { $_.RecordData.IPv4Address }
                           elseif ($_.RecordType -eq 'AAAA') { $_.RecordData.IPv6Address }
                           else { $_.RecordData.HostNameAlias }
                    Add-Line "| $($_.HostName) | $($_.RecordType) | $val |"
                }
        }
    }
}

Add-Section '9. Network'
Try-Run 'Network' {
    Add-Line '| Interface | IP | Prefix | Gateway | DNS |'
    Add-Line '|---|---|---|---|---|'
    Get-NetIPConfiguration | Where-Object { $_.IPv4Address } | ForEach-Object {
        Add-Line "| $($_.InterfaceAlias) | $($_.IPv4Address.IPAddress) | $($_.IPv4Address.PrefixLength) | $($_.IPv4DefaultGateway.NextHop) | $($_.DNSServer.ServerAddresses -join ', ') |"
    }
}

Add-Section '10. CSV file'
if (-not $CsvPath) {
    Add-Line '_No -CsvPath given._'
}
elseif (-not (Test-Path -LiteralPath $CsvPath)) {
    Add-Line "File not found: $CsvPath"
}
else {
    $firstLine = Get-Content -LiteralPath $CsvPath -TotalCount 1
    $delim = if ($firstLine -match ';') { ';' } else { ',' }
    $rows = Import-Csv -LiteralPath $CsvPath -Delimiter $delim
    Add-Line "Path: $CsvPath"
    Add-Line ''
    Add-Line "Delimiter: $delim"
    Add-Line "Rows: $($rows.Count)"
    Add-Line ''
    Add-Line "Columns: $(($rows[0].PSObject.Properties.Name) -join ', ')"
    Add-Line ''
    Add-Line 'First 5 rows:'
    Add-Line ''
    Add-Line '```csv'
    $rows | Select-Object -First 5 | ConvertTo-Csv -NoTypeInformation | ForEach-Object { Add-Line $_ }
    Add-Line '```'
}

$report = $script:sb.ToString()
$report | Out-File -LiteralPath $OutFile -Encoding UTF8

Write-Host ''
Write-Host "Report saved to: $OutFile" -ForegroundColor Green
if (Get-Command Set-Clipboard -ErrorAction SilentlyContinue) {
    $report | Set-Clipboard
    Write-Host 'Report copied to the clipboard.' -ForegroundColor Green
}
Write-Host ''
Write-Host $report
