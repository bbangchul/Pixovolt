# Display connection API references

DisplayConnection.swift is an independent UUID-based implementation using runtime-resolved SkyLight display APIs and CoreDisplay identification. It does not vendor another application or depend on a downloaded executable.

API signatures and operational limitations were checked against:
- https://github.com/jakehilborn/displayplacer/blob/master/src/DisplayPlacer.c
- https://github.com/jjongkwann/MacDisplay/blob/main/core.swift
- https://github.com/jjongkwann/MacDisplay/blob/main/README.md

Differences: target only external displays; require an active internal display to disconnect; reject mirroring; identify by UUID rather than cached numeric display ID; retain nonzero vendor/model/serial for an unambiguous recovery fallback; session-only configuration; persist pending recovery before mutation; no automatic disable on wake. These APIs are private and may change with macOS updates.
