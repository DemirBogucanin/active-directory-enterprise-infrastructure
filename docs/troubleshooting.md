# Troubleshooting

Problemi na koje smo naisli tokom izgradnje AD laba i kako su reseni.

## Windows / AD / DNS / DHCP

| Simptom | Uzrok | Resenje |
|---|---|---|
| Server nema internet, VM ima adresu van mreze | NAT mreza `192.168.72.x`, a gost staticki `192.168.31.x` | prebaciti adapter na **Bridged** (ili gosta u `192.168.72.x`) |
| Gateway ne odgovara | upisan `192.168.31.2`, a ruter je `192.168.31.1` | ispraviti default rutu |
| Nema interneta, a ping do gateway-a radi | DNS ne prosleduje upite | forwarder na DC: `Set-DnsServerForwarder` |
| `nslookup demo.lab` ne vraca DC | DNS klijent pokazuje na ruter, ne na DC | postaviti DNS na `192.168.31.10` |
| `realm`/`nltest` ne nalazi domen | nema SRV zapisa / DNS nije DC | proveriti `_msdcs.demo.lab` zonu |
| DHCP klijent ne dobija adresu | scope nije autorizovan u AD | `Get-DhcpServerInDC`, pa `Add-DhcpServerInDC` |
| GPO se ne primenjuje | GPO nije linkovan na OU ili nije pokrenut `gpupdate` | `gpupdate /force`, `gpresult /r` |
| Mapiran drajv se ne pojavljuje | GPO Preferences nije primenjen / korisnik nije u pravoj OU | proveriti link GPO-a i `gpresult /r` |
| „We can't sign you in... domain isn't available“ | klijent je na NAT mrezi, a DC na bridged | prebaciti adapter na **Bridged** i `ipconfig /renew` |
| `P:` drajv ne radi posle prelaska na bridged | GPO pokazuje na staru NAT adresu `192.168.72.128` | share na DC + GPO Location `\\WIN-2J1EV0B70HA\ProdajaShare` |
| „Clock skew too great“ | satovi nisu uskladeni | `w32tm /resync`, `timedatectl` na klijentu |
| Domain join ne prolazi | pogresan DNS ili vreme | DNS = DC, vreme u toleranciji od 5 minuta |

## Dijagnostika

```powershell
Get-ADDomain
Get-ADOrganizationalUnit -Filter *
Get-ADUser -Filter * -Properties Department
Get-ADGroup -Filter *
Get-GPO -All
Get-GPOReport -All -ReportType Html -Path C:\Temp\gpo-report.html

Get-DnsServerZone
Get-DnsServerResourceRecord -ZoneName demo.lab -RRType A
Resolve-DnsName demo.lab

Get-DhcpServerInDC
Get-DhcpServerv4Scope
Get-DhcpServerv4OptionValue -ScopeId 192.168.31.0

gpupdate /force
gpresult /r
w32tm /query /status
```

## Korisne provere

```powershell
# read-only inventar celog okruzenja
.\scripts\windows\Get-ADLabReport.ps1 -CsvPath .\data\korisnici.csv
```
