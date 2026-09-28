# Private authentication UI tests

This suite is for a disposable Atmosphere in a Box PDS and PLC. Account creation,
OAuth authorization, refresh, and keychain restoration use OME's normal paths.
The first slice covers authentication only; it does not validate publication,
AppView ingestion, or editing.

## Acceptance story

`Scripts/auth-e2e/run.py` coordinates both devices in one run:

1. Each platform creates its own account through OME and the provider's browser UI.
2. Each logs out locally, signs in, and restarts its process without clearing data.
3. Opening Accounts must display a verified session and issue a successful real
   `com.atproto.server.getSession` request.
4. Both processes stop for 70 seconds. The test image issues 60-second access
   tokens. On relaunch, each must produce an ordered 401, successful OAuth refresh,
   and successful getSession retry. A screen that merely looks signed in cannot pass.
5. Both restart again to check storage of the refreshed session.
6. iOS signs into the Android-created identity; Android stays authenticated after
   iOS logs out. Android then signs into the iOS-created identity.

No token or session is injected. No account is created by the sandbox seed command.
The app's observer forwards the request to its real transport and emits only the
operation and HTTP status. The coordinator saves per-platform Maestro artifacts
and a `report.json` under `.build/auth-e2e/runs/`. Maestro artifacts can contain
the disposable test password; keep this ignored directory private.

## Start the private services

Requirements: Python 3.12+, Deno, Docker Desktop, Docker Compose 2.33.1+.

```sh
python3 Scripts/auth-e2e/sandbox.py prepare
python3 Scripts/auth-e2e/sandbox.py up
python3 Scripts/auth-e2e/sandbox.py access-start
python3 Scripts/auth-e2e/host-routing.py print
sudo python3 Scripts/auth-e2e/host-routing.py install
python3 Scripts/auth-e2e/preflight.py
```

The archive revision and checksum are pinned in `sandbox.py`. The PDS base is
pinned by image digest. The derived image sets `tokenMaxAge` to 60 seconds; upstream
refresh-token and session lifetimes are unchanged. It also permits exactly
`https://metadata.ome-auth.test/oauth-client-metadata.json` through the provider's
local-hostname client-ID check. Other local clients remain rejected. Both patches
fail if the pinned source changes, and the image build tests the client exception. The app's OAuth metadata grants only `atproto` for this slice.

The host relay binds **127.0.0.1:443**. On Docker Desktop its external network has
higher priority than the internal Atmosphere network; without that priority, host
connections reset even though container-to-container TLS succeeds.

`down` preserves accounts. `reset` explicitly destroys only the `ome-auth-e2e`
project's disposable state, then prepares a new unseeded sandbox. The upstream
tool preserves the CA; verify its fingerprint before reusing device trust.
After reset, run `up` and `access-start` again and use freshly reset dedicated
devices. The first signup deliberately fails if its fixed test handle already exists.

## Dedicated devices and trust

The coordinator rejects simulators whose name does not begin `OME Auth E2E` and
AVDs whose name does not begin `OME_Auth_E2E`. It never chooses the first booted
device and never erases app data. Create/reset these dedicated devices explicitly;
uninstalling an iOS app does not guarantee an empty keychain.

For iOS, create an iPhone Air on the installed iOS 26.4 runtime, boot it, then:

```sh
xcrun simctl keychain IOS_UDID add-root-cert \
  .build/auth-e2e/atmosphereinabox-26cf1f60f81b491b065dfc830efd27aba8b89a54/state/ca/root.crt
```

For Android, use the rootable `system-images;android-36;google_apis;arm64-v8a`
image, not a Play Store image. Private hostnames must resolve to **10.0.2.2** in
that AVD. The provider browser and native Swift networking must each trust the
sandbox CA; a successful Chrome request alone does not establish native trust.
Run `python3 Scripts/auth-e2e/configure-android.py --device ANDROID_SERIAL`
before launching either app or browser. This name-checked root-only operation
installs the public CA as a user trust anchor for Chrome and mounts it alongside
standard CAs for native networking. It also mounts the private hosts block.
Repeat after emulator reboot; the bind mounts are temporary. No TLS verification
is disabled. Browser HTTPS has been verified; native app TLS remains a runtime gate.

## Build and run

Builds use `OME_UI_AUTOMATION_PROFILE=authentication`. The legacy attendee flag
still selects `.attendee`, which alone imports Testival and freezes the clock.
Release startup ignores test profiles. Auth mode uses the local catalog, disables
public typeahead, and rejects raw HTTP requests outside the private HTTPS domain.

```sh
~/.codex/skills/woodys-swift-workflow/scripts/swift-compiler-lane.sh \
  --wait --priority normal exec Scripts/fastlane-local.sh auth_build \
  ios_device:IOS_UDID android_device:ANDROID_SERIAL

Scripts/fastlane-local.sh auth_e2e \
  ios_device:IOS_UDID android_device:ANDROID_SERIAL
```

The existing attendee/image lanes remain separate. The auth lane does not record
or replace image baselines. Auth screenshots are evidence, not visual baselines.

## Verification at initial implementation

- Four original fixture tests passed before changes.
- 43 focused Swift tests passed afterward (`AuthenticationAutomationTests`,
  `UIAutomationFixtureTests`, and `AccountTests`).
- Four Python harness tests passed; Fastfile Ruby syntax and five Maestro YAML
  files parsed successfully. YAML parsing does not prove browser selectors work.
- Private PDS discovery and client metadata returned 200 over verified HTTPS
  inside Docker. The host relay returned PDS health over verified HTTPS with
  `curl --resolve` and the private CA.
- iOS app build passed after landing the existing HeroImageList Android-only
  dependency condition into that companion package. The installed iOS auth app
  launches with bundle ID `app.openmusicevent`.
- Android app build passed after replacing the unsupported
  `RelativeDateTimeFormatter` subtitle call with `Date.RelativeFormatStyle`.
  APK installed on the dedicated emulator. Its first cold start triggered an ANR
  while loading native libraries, then completed and rendered Browse after Wait.
  This manual recovery is not an automated startup pass.
- Android Chrome displayed a secure connection and the real PDS health JSON
  after dedicated-device provisioning. Native app TLS is not yet proven.
- The paired runner was attempted and stopped at macOS DNS preflight. No signup
  or token-refresh E2E phase passed.
- Browse and Search now expose the existing AccountPicker and account sheet.
  iOS UI automation passed opening Sign In, switching to Sign Up, finding the
  private PDS, and closing the sheet. Both platform builds passed.
- Android account UI had been excluded from Skip bridge generation by its
  `canImport(SwiftUI)` guard. Explicit Android inclusion restores those bridges;
  four authorization form state properties and their request type are internal
  so the generated bridge can access them.
- The initial Android account-sheet run exposed overlapping sections. The
  generated custom view bridge treated all sections as one list row. Account
  and signup-provider sections now use shared `@ViewBuilder` functions directly
  inside the form, avoiding those two custom view bridges. Both platform builds
  pass. The focused `.maestro/auth/account-form.yaml` flow passes on iOS, covering
  Sign In, Sign Up, the private PDS, returning to Sign In, and closing the sheet.
- Android installed the rebuilt APK, but three launch attempts returned to the
  launcher before Browse appeared; the captured log confirms a startup ANR on
  the second attempt. The form flow failed at its initial account-menu assertion.
  The Android section workaround therefore remains runtime-unverified. Run the
  focused flow against an already launched app; it deliberately does not mask
  startup failures with retries or data resets.
- Android automated cold starts also intermittently ANR; a separately launched
  app was used to isolate the toolbar check. No full E2E pass is claimed.
- The OME source workspace remains isolated; its default workspace is unchanged.

Stop services with `sandbox.py down`. Remove just the host block with
`sudo python3 Scripts/auth-e2e/host-routing.py remove`. Device/CA removal is a
separate explicit cleanup operation; everyday simulator and emulator state is
outside this harness's scope.
