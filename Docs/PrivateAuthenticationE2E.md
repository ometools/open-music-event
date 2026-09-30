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
the disposable test password; keep this ignored directory private. Each run also
saves its password in a mode-0600 `credentials.json`, so a failed run can be
diagnosed using the accounts it actually created without resetting the PDS.

## Start the private services

Requirements: Python 3.12+, Deno, Docker Desktop, Docker Compose 2.33.1+.

The runner also requires Android platform-tools (adb), Xcode command-line tools,
Maestro, and an installed app on each dedicated device. Building AppView requires
a GitHub token with access to the private TCA dependency, supplied through
`GITHUB_TOKEN` or `gh auth token`; Docker receives it only as a temporary build
secret. Neither the AppView builder nor the device runner requires a Codex
installation. `Scripts/auth-e2e/android-device.py` owns only dedicated-emulator
name inspection, timestamped logs, and stopping the selected test app.

On a workstation using a compiler coordinator, set `OME_COMPILER_LANE` to that
executable before `sandbox.py up`. CI can leave it unset and schedule the Docker
build through its own job runner. Historical diagnostic commands below include
the coordinator used during investigation; those paths are not prerequisites.

The currently passing mobile build still depends on unpublished companion
changes. See [the portability audit](AuthSlicePortability.md) before attempting
a clean-machine build.

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

The one-time `host-routing.py install` command installs
`/etc/resolver/ome-auth.test` pointing to `127.0.0.1:1053` and removes only the
previous OME block from `/etc/hosts`. A separate host-facing CoreDNS service answers
all names under `ome-auth.test` with `127.0.0.1`; it binds UDP and TCP only on
localhost and does not forward unrelated domains. Internal Docker DNS continues
to return the gateway's internal address. The host DNS service starts with
`sandbox.py up` or `prepare-run.py`; subsequent test runs need no Mac sudo.

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
  ios_device:IOS_UDID android_device:ANDROID_SERIAL prepare:true

# Use the run directory printed above. Provision exact account hostnames before UI work.
python3 Scripts/auth-e2e/prepare-run.py .build/auth-e2e/runs/RUN_ID \
  --android-device ANDROID_SERIAL

Scripts/fastlane-local.sh auth_e2e \
  ios_device:IOS_UDID android_device:ANDROID_SERIAL \
  resume:.build/auth-e2e/runs/RUN_ID
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

Stop services with `sandbox.py down`. Remove just the macOS domain resolver with
`sudo python3 Scripts/auth-e2e/host-routing.py remove`. Device/CA removal is a
separate explicit cleanup operation; everyday simulator and emulator state is
outside this harness's scope.

## Native callback routing

Both private apps use `test.ome-auth.metadata:/oauth/callback`, advertised by
the AppView metadata. The auth build passes `OME_OAUTH_CALLBACK_SCHEME` to
the iOS URL registration. Android derives its manifest scheme from the
authentication build profile and uses a single-task activity so the browser
returns to the pending authorization. Skip forwards the VIEW intent into the
existing `.onOpenURL` auth coordinator.

iOS uses ASWebAuthenticationSession. Android's shared external-browser strategy
is presented by SkipAuthenticationServices, which owns the browser callback and
cancellation result. The native Android presenter constructs its bridged
WebAuthenticationSession directly: the package's SwiftUI environment accessor is
a transpilation stub and traps when read by native Swift. Root URL handling does
not also exchange a callback while that browser session owns it. Neither route
bypasses token exchange or its state, issuer, PKCE, and DPoP checks.

Android OAuth sessions use the shared ATProtoOAuth secure-storage client backed
by SkipKeychain's encrypted preferences. Its dependency must be visible during
Skip's macOS prebuild as well as native Android compilation; an Android-only
SwiftPM product condition can compile the Swift bridge while omitting its JVM
class from the APK. The shared package gates this integration with its existing
`SkipAndroidBridge` trait.


To retry an incomplete run, pass `--resume .build/auth-e2e/runs/RUN_ID` to
`Scripts/auth-e2e/run.py` with the same four device/app arguments. Successful
phases keep their original evidence; failed phases rerun with the saved password.
A partially completed signup that created an account but did not finish callback
verification still needs investigation before retrying signup. Resume does not
reset accounts, clear app data, or turn a failed assertion into a pass.

Each new run uses unique private handles, persisted in its report and reused by
all login and cross-device phases. Repeating the suite does not require deleting
PDS accounts. Resume keeps the original handles and saved password.

Before UI work, prepare the run's exact hostnames in the private gateway, CoreDNS,
and Android hosts mount using the commands above. The Mac resolver is installed once. Signup itself
can succeed before account-handle DNS exists, but subsequent handle login cannot.
The runner checks Mac resolution before touching either UI. Provisioning preserves
existing PDS accounts and the private CA; restart the Android app and Chrome after
remounting routes. No administrator access is needed for subsequent runs.

## Native callback verification (2026-09-28)

Both installed apps completed real private-PDS signup/login callbacks and displayed
the exact authenticated handle. iOS and Android each restored a session after process
termination and demonstrated `getSession 401 → refresh 200 → getSession 200` after
real access-token expiry. Android evidence is in
`.build/auth-e2e/diagnostics/210945-android-relaunch/report.json`; iOS evidence is in
`.build/auth-e2e/diagnostics/201229-ios-relaunch/report.json`.

The combined run `20260929T022823Z` resumed after Mac routing was installed on
2026-09-29. Seventeen phases passed: signup, logout, login, restoration, actual
expiry/refresh, and restored refreshed sessions on both platforms; iOS login and
restoration using the Android-created account; Android peer-session verification;
and iOS local logout. Both expiry checks recorded the required ordered
`getSession 401 → refresh 200 → getSession 200` evidence.

The suite remains failed at `peer-survives-local-logout`: Android's next refresh
returned `invalid_grant` with `Refresh token replayed`. OME's local logout handler
clears local storage without a server revocation request, so temporal proximity
to iOS logout does not establish causation. The previous Android refresh had
succeeded; repeated rotation/persistence needs investigation before retrying this
story. The final three reverse cross-device phases have not run. Preserve this
report and its original artifacts; do not turn the failed phase into a pass by
silently signing in again.

An iOS browser-driver failure during cross-login was corrected by tapping the
static password-page heading instead of `hideKeyboard`, which fails when Safari
shows only its input toolbar. The retried login passed. No OAuth validation was
relaxed.

Validation: both app builds passed; 37 focused Swift account/callback tests and
10 Python harness tests passed. Standalone shared-package keychain tests were
blocked during dependency resolution by unavailable CasePaths revision
`c641088612486aac555d329163561f392043d162`; this is not a test pass.

Android exposes the account row identifier and verified-session accessibility
label on separate nodes, so the relaunch flow checks a labeled descendant. Network
evidence retains timestamps/process IDs before subtracting prior events, avoiding
false failures when logcat rotates older entries with the same HTTP status.

## Session independence investigation (2026-09-29)

A temporary wrapper around the pinned PDS token manager emitted only SHA-256
hashes of token/DPoP identities, method names, timestamps, and error descriptions.
It forwarded the original arguments, return values and errors without changing
validation. The original server module was restored after tracing; accounts and
CA were preserved. Hash evidence is in
`.build/auth-e2e/diagnostics/session-independence-hash-trace.json`.

Fresh authorizations for `android-tester.pds1.ome-auth.test` were independent:
Android's DPoP hash begins `a4ab3dba3014` and initial refresh-token hash begins
`bfd0a0575dc3`; iOS's DPoP hash begins `a05412272f7e` and initial refresh-token hash
begins `9138ecd115ab`. Three Android-only expiry/relaunch cycles passed, consuming
the latest token each time. Then iOS refreshed its own session and logged out;
Android's next relaunch refreshed successfully using its own latest token.
Reports: `121849-android-relaunch`, `122025-android-relaunch`,
`122200-android-relaunch`, `122247-ios-login`, `122631-ios-relaunch`,
`122657-ios-logout`, `122718-android-relaunch` under the diagnostics directory.
The original failed combined-suite report remains unchanged.

A separate deterministic regression test,
`AccountTests.accountValidationCannotRestoreATokenRotatedByAnotherRequest`,
compiled and failed. Account validation receives a copied session; after another
request replaces the stored credentials, the accepted validation result blindly
replaces the entire stored session in `Account.accountSessionValidationResponse`.
The test demonstrates rollback to the original refresh token. This is a confirmed
local state-ownership defect in shared OME account code, not evidence of shared
sessions between devices. It remains unproven that this exact interleaving caused
the earlier runtime replay; the traced reproduction did not replay a token.

Diagnostic test command (no production fix applied):
```sh
env SKIP_PLUGIN_DISABLED=1 SKIP_ACTION=none \
  ~/.codex/skills/woodys-swift-workflow/scripts/swift-compiler-lane.sh \
  --wait --priority interactive swift-test --build-system native --skip-update \
  --filter accountValidationCannotRestoreATokenRotatedByAnotherRequest
```
Result: build passed; one test failed at the no-rollback assertion.


## Account-bound refresh implementation (2026-09-29)

Account validation now accepts an account ID and returns only verification status
and the resolved handle. It cannot return or write credentials. Each account has
an independent validation task.

The shared `OAuth.StoredSession` binds an operation to the persistent account
entry and its authorization identity (account, token endpoint and DPoP key).
Ordinary authenticated API calls and account-list checks use the same refresh
path. Concurrent expired requests share refresh plus persistence; a late 401
retries the current access token. Selection changes do not retarget the operation,
and logout or a replacement authorization prevents an old response from writing
credentials back. Offline errors preserve the account. Terminal errors let the
account list request sign-in again; the older single-session interceptor retains
its existing logout behavior.

The no-rollback regression now passes. The focused OME graph runs 63 tests across
`StoredAccountRequestTests`, `AccountTests`, and `OpenMusicEventOAuthTests`, including
real refresh encoding/DPoP/HTTP retry and keychain persistence with only HTTP
transport replaced. Command:

```sh
env OME_COMPOSABLE_ATMOSPHERE_PATH=/Users/woody/Developer/ometools/worktrees/swift-composable-atmosphere \
  SKIP_PLUGIN_DISABLED=1 SKIP_ACTION=none \
  ~/.codex/skills/woodys-swift-workflow/scripts/swift-compiler-lane.sh \
  --wait --priority interactive swift-test --build-system native --skip-update \
  --filter 'StoredAccountRequestTests|AccountTests|OpenMusicEventOAuthTests'
```

Result: compilation and all 63 tests passed. Standalone shared-package tests
remain blocked by the unavailable CasePaths pin described above. The iOS simulator build passed with the local shared package override. Real
private-PDS login passed (`131849-ios-login`), followed by two successful
expiry/relaunch checks (`132105-ios-relaunch`, `132227-ios-relaunch`), each recording
`getSession 401 → refresh 200 → getSession 200` and a verified account row.
The Android native build and APK installation also passed. The fresh full run
`20260929T191452Z` passed all 21 UI/network phases on the rebuilt iOS and Android
apps: separate fresh signups, logout/login, process restoration, real token expiry
and refresh, restoration of rotated credentials, and cross-device login/logout
isolation against the same private PDS. Both expiry checks recorded the required
`getSession 401 → refresh 200 → getSession 200` sequence. The previously failing
`peer-survives-local-logout` phase also recorded that successful refresh sequence.
Report: `.build/auth-e2e/runs/20260929T191452Z/report.json`.

The first Android signup attempt selected the username preview instead of the
input and submitted an empty field. The Android flow now targets the browser
input's `handle` ID and asserts its entered value. Resuming retained the successful
iOS signup and original failure screenshot; Android signup and all remaining
phases passed. No account reset, credential injection, or OAuth relaxation was
used. All 10 Python harness tests passed as well.

Both source workspaces remain isolated; these changes have not been landed or
pushed. Validation-only root `Package.resolved` churn was restored.
The original failed combined report remains unchanged.


## Repeatable provisioning and recovery stories

macOS uses a one-time `/etc/resolver/ome-auth.test` domain resolver pointing to
CoreDNS on loopback port 1053. `host-dns.compose.yaml` serves wildcard loopback A
records only for the private domain; it does not change the Mac's default DNS.
`preflight.py` checks a new random hostname, so old `/etc/hosts` entries cannot
mask a broken resolver. Each run still provisions its private HTTPS routes and
Android names. New runs require no further Mac administrator command.

Use `run.py --prepared RUN` to start a provisioned, never-started baseline.
It refuses any recorded earlier attempt; `--resume` remains explicitly separate.
Run `recovery.py RUN` after a passed baseline to exercise both accounts through
browser login, in-flight selection, process restoration, removing one account,
browser cancellation, PDS interruption, grant revocation and reauthorization.
The recovery report records each phase's UI result and status-only network events.
Revocation is restricted to the UI-created private account and sandbox client.
Fault injection restores the PDS in a `finally` block, including failed UI checks.

Android provisioning checks source/target inode identity inside each mount
namespace before binding. Shared mount propagation means blind repeated binds
can multiply: the fresh `20260929T195720Z` run exposed 16,384 stacked binds on each
CA directory. Android killed OME during `AndroidBootstrap.setupCACerts`, before
signup. That failed run is preserved. Hosts updates now write into the existing
bound inode instead of replacing it with `adb push`. A dedicated emulator reboot
clears previously accumulated temporary mounts while preserving account data.

After the fix, two consecutive live provisioning runs each reported one mount at
all three sandbox targets. The installed Android app then cold-started in 3.2s.
The Python harness has 16 passing tests, including restoration after failed fault
injection, preserved timeout evidence, refusal to relabel a resumed run as fresh,
and skipping an already-bound inode. No Swift source or installed app changed
for this provisioning repair.

The post-repair fresh baseline `20260929T203916Z` passed all 21 phases on its first
attempt (`resumed: false`), using two new UI-created accounts. Both platforms
proved real expiry/refresh, persisted rotated credentials, and same-account
cross-device logout isolation. No resumed phase, account reset, or manual UI
intervention was used in this run. Recovery stories are recorded separately.

The first recovery run (`recovery-20260929T145612`) preserved two new failures:
- iOS passed multi-account switching/removal, browser cancellation/retry, and
  offline preservation/recovery. Reauthorization exchanged tokens successfully
  but left the account label without its verified handle: the account-ID set had
  not changed, so no validation ran for the replacement authorization.
- Android's Accounts sheet rendered its custom bridged Section as overlapping
  content, making Add Another Account inaccessible and blocking scenario setup.

The account feature now requests its existing account validation after successful
sign-in/sign-up storage completes, including replacement authorization for an
existing ID. The new `reauthorizingAnExistingAccountRefreshesItsVerifiedHandle`
test first failed on the missing handle and now passes. All 64 focused auth tests
pass. Account management sections now compose directly inside the native Form
builder, preserving the authentication surface when no accounts remain. Device
verification of these fixes is tracked in subsequent reports; the original
failure reports are retained.

The rebuilt iOS app passed the complete revocation story in
`recovery-20260929T152210`: private grant removal, Sign in required, reauthorization
with the verified handle restored, preservation of the other account, and
restoration after relaunch. The iOS build passed. Android also built and installed
successfully (Gradle 6m25s); its repaired account-sheet stories are tracked next.

Android recovery `recovery-20260929T152916` passed PDS interruption and recovery
with both accounts and selection preserved. Browser cancellation remains a
confirmed product failure: Back returns from Chrome, but the external-browser
authorization remains pending and the submit button stays disabled. The shared
Android external-browser path opens the URL without receiving a cancellation
result; the test remains red rather than adding a UI lifecycle workaround.

The corrected multi-account row selectors passed the visible assertions through
selection and validation in `recovery-20260929T154431`, but its network-evidence
assertion captured no new events. This is not counted as a complete pass. Earlier
revocation setup also exposed a test-input problem: Android eraseText left part
of the prefilled DID. Reauthorization now submits the asserted prefilled
identifier, exercising the actual product flow.

Account action icon mappings are implemented in shared SkipUI Image.swift, in
workspace skip-ui-label-accessibility, rather than as OME view substitutions.
The final Android APK compiled successfully with these mappings and was
installed preserving account data. Visual and final runtime results follow.

The final Android APK passed the complete revoked-grant story in
`recovery-20260929T155213`, including submission of the prefilled account ID,
reauthorization, verified handle restoration, preservation of the second
account, and relaunch.

The multi-account evidence gap was traced to Maestro 2.9.0
`AndroidDriver.startDeviceLogCapture`, which executes `logcat -c` at every flow
start. Requests completed between PDS unpause and the next flow were erased.
Recovery now keeps a filtered live auth-event reader across that boundary,
starts the assertion window immediately before unpause, and closes the reader
even on failure. Timestamped status-only observations are retained in each
phase artifact. The harness has 17 passing tests including this cleanup and
event-retention behavior. OAuth validation and UI assertions remain unchanged.

Android multi-account recovery passed completely in
`recovery-20260929T160133`: both accounts were checking while the PDS was paused,
switching preserved the selected identity, post-unpause validation had both UI
and HTTP proof, selection survived relaunch, removing the second account left
the first intact, and that state survived another relaunch. The Accounts screen
also visually confirmed the shared Add Account and Log Out icon mappings.

Fresh run `20260929T215517Z` was prepared on the final builds. Its routing
provisioning confirmed the existing Mac resolver and required no per-run sudo.

Final-build baseline `20260929T215517Z` passed all 21 phases on its first attempt
(`resumed: false`, no failures). Both iOS and Android recorded getSession 401,
refresh 200, and getSession 200 after the real expiry wait, then restored the
rotated session on another relaunch. Same-account sessions survived peer local
logout, and each platform signed into the account created on the other.
No manual UI intervention or account reset was used. Private PDS, DNS and
gateway were confirmed running and unpaused afterward.

Remaining failure: Android browser cancellation, preserved in
`recovery-20260929T152916`. Its fix belongs in the shared browser authorization
session completion/cancellation path. The broader recovery suite is not fully
green despite the fresh baseline, multi-account, offline and revocation passes.
All changes remain isolated; nothing has been landed or pushed.

## Fresh baseline after native browser integration (2026-09-30)

Run `20260930T073848Z` passed all 21 UI/network phases on its first attempt
(`resumed: false`). Both platforms created new accounts through the provider UI,
completed login callbacks, restored sessions and rotated credentials, and proved
cross-device local-logout isolation. Each expiry phase recorded
`getSession 401 → refresh 200 → getSession 200`. The preceding Android
environment-accessor crash remains recorded in `20260930T064544Z`.

The native Android presenter uses the bridged WebAuthenticationSession
initializer. The dependency's environment accessor is a transpilation stub that
traps in native Swift; the generated presenter no longer calls it. Callback
ownership and cancellation/retry are covered by deterministic coordinator tests.
The full recovery run is recorded separately and must pass before claiming
browser-cancellation runtime coverage.

### Android runtime cancellation investigation (2026-09-30)

The fresh 21-phase baseline above passed, but the following full recovery run did
not: `20260930T073848Z/recovery-20260930T020331/report.json`. iOS passed all four
stories. Android passed offline recovery, failed multi-account setup with a
FoundationNetworking task-registry trap, stalled during cancellation-story setup
with an ANR, and failed revocation reauthentication. These are retained failures,
not a completed slice.

The ANR matches [swift-corelibs-foundation issue 5412](https://github.com/swiftlang/swift-corelibs-foundation/issues/5412):
Swift task cancellation holds its task lock while synchronously entering the
URLSession work queue; request completion holds that queue while resuming the
Swift task. [Upstream PR 5417](https://github.com/swiftlang/swift-corelibs-foundation/pull/5417)
changes the cancellation hop to asynchronous. The installed 6.3.3 Android runtime
still uses the synchronous hop.

A second race occurs across cancellation's later `_getProtocol` callback: the
request can complete and leave the task registry before the queued cancellation
block reports failure. The candidate patch checks `state != .completed` inside
that later work-queue block. It does not suppress cancellation of active requests.

`Scripts/android-networking-overlay.py` builds an **explicit, local, arm64-only**
SDK overlay from the checksum-verified 6.3.3 source release, with these two changes.
It verifies the original runtime hash and matching compiler, preserves the
installed SDK, and records source/runtime hashes and the build command. No OAuth,
DNS, TLS, or private-CA validation changes are involved. This remains a local
runtime workaround pending an upstream SDK containing both fixes; it must not be
mistaken for a generally released Swift fix.

Build it through the compiler lane:

```sh
~/.codex/skills/woodys-swift-workflow/scripts/swift-compiler-lane.sh --wait --priority normal exec \
  python3 -B Scripts/android-networking-overlay.py \
  --sdk "$HOME/Library/org.swift.swiftpm/swift-sdks/swift-6.3.3-RELEASE_android.artifactbundle" \
  --swiftc "$HOME/Library/Developer/Toolchains/swift-6.3.3-RELEASE.xctoolchain/usr/bin/swiftc" \
  --output .build/android-networking-overlay
```

Pass the printed `SWIFT_ANDROID_SDK_BUNDLE` to the canonical Android build with
`--adopt-build-config`, retaining the local package overrides documented in
OME-033. Verify the packaged runtime hash against `manifest.json` before claiming
runtime proof. Other Android architectures retain the stock runtime and are not
covered by this workaround.

Isolated emulator evidence: stock runtime deadlocked; asynchronous cancellation
alone reproduced the registry trap; both changes completed 3,000 connection-error
cancellation races. A separate bounded HTTP keep-alive probe completed 1,000
successful responses, 1,861 cancellations, and 139 connection refusals without a
trap or deadlock. Earlier HTTP/1.0 stress probes had an empty response and a timeout;
those results are retained and are not counted as passes. App recovery validation with the overlay passed all four Android stories and
all 15 phases in `20260930T073848Z/recovery-20260930T030133`. The normal Android
test target also passed all 354 tests in 31 suites with the overlay. The fresh
two-platform baseline `20260930T091230Z` passed iOS signup but failed Android
signup after browser authorization, before token exchange. No native crash or
ANR was recorded. The retained failure is being investigated in Skip's Custom
Tabs fallback, which treats TAB_HIDDEN as cancellation even during a successful
redirect. This is separate from the fixed Foundation networking cancellation
failures. The cancellation story now also rejects a spurious Sign in failed label.

The Android harness now aligns Skip runtime packaging with the selected SwiftPM
SDK, records the arm64 networking runtime hash in its build inputs, and checks
all packaged networking libraries against that SDK before installation. The
artifact check accepts the overlay APK and rejects it against the stock SDK.

The Custom Tabs candidate is isolated in repository
`/Users/woody/Developer/swift-packages/3rd-party/skip/skip-authentication-services`,
workspace
`/Users/woody/Developer/swift-packages/3rd-party/skip/worktrees/skip-authentication-services-callback-race`,
change `nqqqzkmz`, based on the app's pinned `6ebda51ac9c2d2160a33c2563666ef1044ca89f2`.
Its local destination is unset. The canonical local alias is
`/Users/woody/Developer/ometools/worktrees/skip-authentication-services`; select it
with `OME_SKIP_AUTHENTICATION_SERVICES_PATH`. The fix keeps TAB_HIDDEN
nonterminal and uses the existing intent-before-resume lifecycle to distinguish
success from cancellation. Debug diagnostics contain lifecycle labels only.
Shared native authorization diagnostics record error type and numeric code, never
callback URLs, authorization codes, or tokens.

The packaged candidate contains the updated Custom Tabs code and the verified
networking runtime. Fresh baseline `20260930T093720Z` passed all 21 phases in one uninterrupted attempt: signup, logout, login, session restoration, real token expiry and refresh, refreshed-session restoration, cross-platform account login, and peer survival after local logout. Both expiry phases recorded `getSession 401 → refresh 200 → getSession 200`. Android passed all four recovery stories and all 15 phases, including the stricter cancellation assertion, in `20260930T093720Z/recovery-20260930T040401`. The clean iOS rerun passed all four stories and all 15 phases in `20260930T093720Z/recovery-20260930T043858`.
The normal UI rerun before this browser-only change passed all four stories and
all 18 image comparisons with zero changed pixels; the Compose rerun executed
both tests with zero failures or skips.

The first final recovery attempt retained two iOS infrastructure failures: cancellation/retry and offline setup both completed OAuth exchange, then Maestro 2.9.0 lost its XCTest driver while querying a stale Safari WebView. The driver retrieved the OME hierarchy, spent about 92 seconds querying Safari, and reported `Timed out while evaluating UI query`. Multiple-account and revocation stories passed. The [upstream hierarchy handler](https://github.com/mobile-dev-inc/Maestro/blob/main/maestro-ios-xctest-runner/maestro-driver-iosUITests/Routes/Handlers/ViewHierarchyHandler.swift) also queries background SafariViewService instances. The dedicated iOS simulator was restarted without erasing app data before a separate clean rerun; no app-side delay or auth bypass was added.

### Completed local validation (2026-09-30)

| Gate | Result |
| --- | --- |
| Host tests | 978 tests / 95 suites passed |
| iOS Simulator tests | 356 tests / 30 suites passed |
| Android instrumentation | 354 tests / 31 suites passed with the final Custom Tabs fix and networking overlay |
| Android Compose | 2 tests passed; no failures or skips |
| Normal UI stories | Attendee and refresh passed on both platforms |
| Image comparisons | 18 passed; zero changed pixels |
| Auth harness tests | 17 passed |
| Fresh private-auth baseline | 21 phases passed in one uninterrupted attempt on both platforms |
| Android recovery | All 4 stories / 15 phases passed |
| iOS recovery after simulator restart | All 4 stories / 15 phases passed; all 15 driver logs free of the earlier UI-query timeout |

Recovery covers multiple accounts, cancellation followed by successful login,
offline preservation and recovery, and revocation followed by reauthentication
and restoration. The preceding iOS driver failures remain recorded separately;
the successful rerun does not change their results. Restarting the dedicated
simulator was sufficient for this rerun, but does not establish a fix in Maestro.

The final local proof depends on the explicitly selected arm64 networking SDK
overlay and the isolated companion package overrides. It is not a remote-only
dependency build or proof of an upstream release. OME source change `ryuruqkz`,
shared authorization change `yvoxklxz`, and Custom Tabs change `nqqqzkmz`
remain isolated; no local landing or remote push was performed.

Final commands and evidence:

- `python3 -B Scripts/auth-e2e/run.py --prepared .build/auth-e2e/runs/20260930T093720Z --ios-device 736C34A7-D420-4F8C-964A-900ED47BF915 --android-device emulator-5580 --ios-app-id app.openmusicevent --android-app-id fm.woody.openmusicevent`: exit 0, baseline report above.
- `python3 -B Scripts/auth-e2e/recovery.py .build/auth-e2e/runs/20260930T093720Z --platform both --scenario all`: exit 1 because of the retained iOS driver failures; Android passed all phases.
- `python3 -B Scripts/auth-e2e/recovery.py .build/auth-e2e/runs/20260930T093720Z --platform ios --scenario all` after restarting the dedicated simulator: exit 0, clean iOS report above.
- Final Android test log: `/private/tmp/ome-custom-tabs-android-tests.log`.
- Normal UI and Compose rerun logs: `/private/tmp/ome-networking-overlay-normal-ui.log` and `/private/tmp/ome-overlay-compose-tests.log`.
