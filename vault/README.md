# ViStay Vault Transit

Local Compose runs Vault in explicit development mode and provisions five
non-exportable Transit keys:

- `vistay-profile-document`: AES-GCM encryption for CCCD;
- `vistay-profile-lookup`: deterministic HMAC-SHA256 lookup;
- `vistay-profile-link-otp`: HMAC-SHA256 challenge evidence;
- `vistay-profile-link-delivery`: encrypted email-delivery secret;
- `vistay-property-access`: AES-GCM encryption for property access codes.

The development root token and fixed service tokens are local-only bootstrap
credentials. Production must use an initialized HA Vault/HCP Vault deployment,
TLS, audit devices and workload identity; it must not use `-dev`, a root token,
or tokens from `.env`.

User Service receives only encrypt/HMAC capabilities. Notification receives
only decrypt capability for the delivery ciphertext. Property Service receives
only encrypt capability for access codes and stores only Vault ciphertext in
its database. No service can read or export Transit key material.
