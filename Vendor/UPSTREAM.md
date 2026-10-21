# m1ddc provenance
Source: https://github.com/waydabber/m1ddc
Commit: 04d949794102eb8df01ad3681afff6464a3eede2
License: MIT, Copyright (c) 2021 waydabber; see m1ddc/LICENSE.
Vendored source only; no downloaded executable. Build does not use network.

Local changes:
- ioregistry.m: exclude built-in displays; zero-initialize DisplayInfos to avoid uninitialized optional attributes; reject non-positive display indices.
- i2c.m: replace sizeof(2) with sizeof(uint16_t) in two NSData reads (4-byte copy into 2-byte variable on arm64).
Private CoreDisplay/IOAVService APIs remain upstream dependencies. No App Store/sandbox claim.

- Pixovolt metadata extension: `display list json` emits schemaVersion 1 with UUID, manufacturer, vendor/product IDs, serial and EDID identity/data when available. Existing CLI commands/output are preserved.
- Optional EDID data read from CoreDisplay/IORegistry; vendor metadata is retained when raw EDID is unavailable.
- Display enumeration capacity increased to 64 and the online-query error checked.
