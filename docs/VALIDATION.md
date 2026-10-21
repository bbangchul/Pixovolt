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
