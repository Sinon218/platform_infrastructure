[CmdletBinding()]
param(
    [string]$RemoteAddress = 'LocalSubnet',
    [int]$Port = 3000
)

$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script from an elevated PowerShell window (Run as administrator).'
}

$name = 'ViStay Grafana LAN'
Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue | Remove-NetFirewallRule
New-NetFirewallRule -DisplayName $name -Description 'Allow trusted LAN clients to reach the local ViStay Grafana dashboard.' -Direction Inbound -Action Allow -Protocol TCP -LocalPort $Port -RemoteAddress $RemoteAddress -Profile Public,Private | Out-Null

Write-Host "Grafana LAN firewall rule is enabled for TCP $Port from $RemoteAddress."
