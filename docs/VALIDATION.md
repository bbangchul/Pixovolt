# Pixovolt validation / 검증 기록

## 확인한 항목 / Verified

- Release arm64 build: Xcode 26.2, Swift 6.2.3, Swift 5 language mode, macOS 13 minimum deployment target.
- App + bundled m1ddc: ad-hoc signature verification; DMG checksum validation.
- Read-only hardware discovery: one LG HDR 4K; DDC brightness and power queries respond.
- Native control window: disconnect confirmation appears; cancelling leaves the control window open.
- Automated tests: display parsing, input values, UUID arguments, helper success/failure/timeout, power readback classification, internal-display protection, last-screen protection, ambiguous identity rejection, fresh-ID recovery policy.
- The original user reported successful use after reinstalling the latest control-window build. This is single-environment feedback, not a per-feature compatibility matrix.

## 제한 / Limits

- DDC power modes 2/3/4/5 did not turn off the user's LG monitor. They remain advanced compatibility controls, not the recommended screen-off action.
- Software disconnect is different from physical power-off. Physical disconnect/reconnect and power operations were not automatically exercised during development.
- Global keyboard conflicts, login relaunch, sleep/wake and other Mac/monitor combinations require manual validation.
- No Developer ID signing or Apple notarization. No Intel or App Store compatibility claim.
- Korean application UI; README provided in Korean and English.

## 1.1.5 menu-bar popover / 메뉴바 팝업

- Standalone control window replaced with an NSStatusItem-anchored NSPopover.
- Disconnect/DDC power confirmation is inline; no separate alert or confirmation dialog.
- Application state retains operation results across popover dismissal.
- Release arm64 build, app signature and DMG checksum validation passed.
- User confirmed the installed menu-bar popover opens correctly on 2026-10-21.
- Physical disconnect/power operations were not triggered as part of this UI update.

## 1.1.6 identity / profile preparation

- New tests pass for EDID header/checksum, manufacturer/product/serial/name parsing, invalid EDID, fallback naming, stable duplicate labels, structured JSON version/UUID validation, profile precedence and per-UUID persistence.
- Installed 1.1.5 and new helper both reported no external monitor. The user confirmed no monitor was connected; detailed live-device verification is pending connection.
- JSON discovery with no connected monitor is represented as a successful empty display list. Legacy CLI text output is preserved.
- New profile editing remains preparation-only: existing input/power/disconnect execution paths are not wired to it.
- No automatic input, power or connection mutations were issued.

## 1.1.7 profile-based input switching

- Input buttons and shortcuts share the selected monitor's resolved profile, captured with the UUID before sending.
- Standard and LG custom values, exact target arguments, saved-profile reload/isolation, invalid values, and strict command output are tested with fake helpers.
- Method changes and retry persist per UUID; changing methods resets custom values, and automatic/reset clears legacy manual preference.
- No automatic input or power changes are run. Real-monitor input switching remains pending verification; no external monitor was connected at the previous check.
