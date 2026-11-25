# Seed Skylake through the real GraphQL API

The seed runner creates the complete Hanoi / Skylake hierarchy through the
backoffice GraphQL API:

- one operating branch, city `01`, area `SKYLAKE`, and buildings S1-S3;
- every configured floor and 76 property units;
- three account-independent Host profiles and ten account-independent Customer
  profiles;
- one owner contract per property and 20 non-overlapping bookings;
- one Vault-protected access code per property.

The runner is query-before-create or idempotency-key based. It verifies the
portfolio, contracts, booking timeline, and booking replay before reporting
success.

## Required deployment

Deploy Property Service and the composed backoffice router schema containing:

- `createOperatingBranch`;
- `propertyAccessCredential`;
- `setPropertyAccessCredential`.

Production Vault must provision the non-exportable Transit key
`vistay-property-access` and a Property Service workload identity/token with
only `update` capability on `transit/encrypt/vistay-property-access`.
Configure Property Service with `VAULT_ADDR`, `VAULT_TOKEN` (prefer a mounted
token file in production), `VAULT_TRANSIT_MOUNT`, and
`VAULT_PROPERTY_ACCESS_KEY`.

## Secret input

Raw property access codes must never be committed. The local input is stored at
`D:\Vistay\.secrets\skylake-access-codes.json`, outside every repository. The
runner sends each code over HTTPS to Property Service; Property Service sends a
property-bound canonical value to Vault Transit and stores only ciphertext.
Neither the GraphQL response nor the seed report returns a raw code or
ciphertext.

## Authentication and execution

Use the mobile public client's Authorization Code + PKCE flow to obtain a
short-lived ADMIN access token. The actor needs these permissions:

`property:create`, `property:update`, `property:read`, `contract:create`,
`contract:read`, `customer-profile:create`, `host-profile:create`,
`user:read`, `booking:create`, and `booking:read`.

Then run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\Seed-RealServerSkylake.ps1 `
  -AccessToken '<short-lived-access-token>'
```

If one downstream protection dependency is temporarily unavailable, the runner
can safely resume independent work without duplicating records:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\Seed-RealServerSkylake.ps1 `
  -AccessToken '<short-lived-access-token>' `
  -SkipAccessCredentials -SkipCustomerProfiles -SkipBookings
```

These switches are recovery controls, not a successful full seed. Run the
command again without them after Vault is healthy; query-before-create and
idempotency keys resume the missing credentials, profiles, and bookings.

For a USB-connected test phone, the local helper under `.work` launches PKCE
in Chrome and captures only the one-time callback code through ADB. Do not log
or persist the resulting access token.
