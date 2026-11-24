# Grafana business dashboard

Start the full local platform, including Prometheus, Grafana, and the Nginx
exporter:

```powershell
docker compose -f compose.yaml -f compose.full.yaml --env-file .env --profile full up -d --build --wait
```

Grafana is provisioned automatically at `http://localhost:3000` or, for the
current LAN setup, `http://172.17.161.131:3000`. Credentials come from the
ignored `.env` file; change `GRAFANA_ADMIN_PASSWORD` before using a shared
environment.

The provisioned **ViStay — Vận hành & Kinh doanh** dashboard covers:

- service availability, HTTP request rate, errors, latency, and Nginx traffic;
- active customer, host, and administrator profiles plus linked identities;
- booking lifecycle, arrivals/departures, guests in house, commands, and
  confirmed VND booking value;
- city/building/unit inventory and JVM CPU/memory pressure.

The separate **ViStay — System Health & API Performance** dashboard is the
operator/SRE view. It includes service availability, request/error throughput,
real HTTP P50/P95/P99 latency, CPU, heap pressure, JVM threads and GC, HikariCP
connection pools, Nginx traffic, scrape health, and per-service filtering.

Prometheus is intentionally bound to loopback at `http://127.0.0.1:9090`.
Only Grafana is exposed on port 3000. Business gauges use aggregate labels
only: no email, phone number, document number, profile ID, or booking ID is
exported.

When Windows classifies the Wi-Fi as a Public network, allow Grafana only from
the trusted LAN subnet in an elevated PowerShell window:

~~~powershell
./scripts/Enable-GrafanaLanFirewall.ps1 -RemoteAddress 172.17.160.0/22
~~~

Prometheus remains loopback-only and must not be opened through this rule.
