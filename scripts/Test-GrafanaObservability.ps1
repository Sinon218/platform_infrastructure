param(
    [string]$EnvFile = '.env',
    [switch]$StaticOnly
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$envPath = Join-Path $root $EnvFile
$compose = @(
    'compose',
    '-f', (Join-Path $root 'compose.yaml'),
    '-f', (Join-Path $root 'compose.full.yaml'),
    '--env-file', $envPath,
    '--profile', 'full'
)

$dashboardPath = Join-Path $root 'observability/grafana/dashboards/vistay-platform-overview.json'
$dashboard = Get-Content -Raw -LiteralPath $dashboardPath | ConvertFrom-Json
if ($dashboard.uid -ne 'vistay-platform-overview' -or $dashboard.panels.Count -lt 20) {
    throw 'The ViStay Grafana dashboard is missing required panels.'
}

& docker @compose config -q
if ($LASTEXITCODE -ne 0) { throw 'Grafana observability compose configuration is invalid.' }
if ($StaticOnly) {
    Write-Host 'Grafana observability static contract passed.'
    exit 0
}

function Wait-ForHttp([string]$Url) {
    foreach ($attempt in 1..30) {
        try {
            $response = Invoke-WebRequest -UseBasicParsing -Uri $Url -TimeoutSec 5
            if ($response.StatusCode -eq 200) { return }
        } catch {}
        Start-Sleep -Seconds 2
    }
    throw "$Url did not become ready."
}

$prometheusPort = if ($env:PROMETHEUS_PORT) { $env:PROMETHEUS_PORT } else { '9090' }
$grafanaPort = if ($env:GRAFANA_PORT) { $env:GRAFANA_PORT } else { '3000' }
Wait-ForHttp "http://127.0.0.1:$prometheusPort/-/ready"
Wait-ForHttp "http://127.0.0.1:$grafanaPort/api/health"

$targets = Invoke-RestMethod -Uri "http://127.0.0.1:$prometheusPort/api/v1/targets" -TimeoutSec 10
if ($targets.status -ne 'success') { throw 'Prometheus target API is unavailable.' }
$requiredInstances = @(
    'authentication:8080',
    'user:8080',
    'notification:8080',
    'property:8080',
    'booking:8080',
    'nginx-exporter:9113'
)
$activeTargets = @($targets.data.activeTargets)
foreach ($instance in $requiredInstances) {
    $target = $activeTargets | Where-Object { $_.labels.instance -eq $instance } | Select-Object -First 1
    if (-not $target -or $target.health -ne 'up') {
        throw "Prometheus target $instance is not UP."
    }
}

$grafanaUserLine = Get-Content -LiteralPath $envPath | Where-Object { $_ -like 'GRAFANA_ADMIN_USER=*' } | Select-Object -First 1
$grafanaPasswordLine = Get-Content -LiteralPath $envPath | Where-Object { $_ -like 'GRAFANA_ADMIN_PASSWORD=*' } | Select-Object -First 1
if (-not $grafanaUserLine -or -not $grafanaPasswordLine) {
    throw 'GRAFANA_ADMIN_USER and GRAFANA_ADMIN_PASSWORD are required for dashboard verification.'
}
$grafanaUser = ($grafanaUserLine -split '=', 2)[1]
$grafanaPassword = ($grafanaPasswordLine -split '=', 2)[1]
$basicValue = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($grafanaUser + ':' + $grafanaPassword))
$dashboardResponse = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$grafanaPort/api/dashboards/uid/vistay-platform-overview" -Headers @{ Authorization = "Basic $basicValue" } -TimeoutSec 10
if ($dashboardResponse.StatusCode -ne 200) { throw 'Provisioned Grafana dashboard is unavailable.' }

Write-Host 'Grafana observability runtime contract passed.'
