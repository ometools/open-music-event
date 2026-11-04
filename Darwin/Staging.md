# OME Staging

Open `Project.xcworkspace` and choose **OME Staging**. It shares the app package and
`Main.swift` with **OpenMusicEvent App**, but installs alongside it as
`app.openmusicevent.staging`, with an amber STAGING icon and the name OME Staging.
Both Debug and Release use staging. The ordinary app target uses production.
Neither target exposes the runtime environment picker; other hosts without a fixed
build setting retain it. Each bundle has its own app container and keychain access.

The shared OpenMusicEventAppTests scheme includes app, browse, authentication, and
OAuth identity tests. OME Staging also exposes these tests from its scheme. Server
route tests check the shipped staging association file and OAuth metadata through
the OpenMusicEventAppViewServerTests scheme on macOS. The current permission
manifest lives in `Sources/OpenMusicEventAppViewServer/Resources/Site/.well-known/`.

## Provisioning and server configuration

Register `app.openmusicevent.staging` under team `YJRWV8Z7KT` with Associated Domains
and Push Notifications enabled, then create development and distribution profiles.
Debug uses APNs development; Release uses APNs production. The app registers its
actual bundle identifier as the notification application ID.

On the staging AppView, configure:

```
OME_APPVIEW_PUBLIC_HOST=stg.openmusicevent.app
OME_OAUTH_CLIENT=staging
```

Deploy the server resources including `WellKnown/stg.openmusicevent.app/`.
The staging OAuth metadata keeps the common permission manifest and advertises
`app.openmusicevent.staging:/oauth/callback`. Production retains its own callback.
For push, include `app.openmusicevent.staging` in `OME_NOTIFICATION_APPLICATION_IDS`
and in the provider configuration with APNs topic `app.openmusicevent.staging`:

```json
{
  "applicationID": "app.openmusicevent.staging",
  "environment": "development",
  "allowedEnvironments": ["development", "production"],
  "topic": "app.openmusicevent.staging"
}
```

The association file maps `/events/*` only to the staging app. After deployment and
installation, verify a tap from Notes or Safari into this published Wicked Woods URL:

https://stg.openmusicevent.app/events/did%3Aplc%3A5df2u7ief6m6tn77jznicxob/3myb27j3qi225

Reducer and route tests do not prove iOS universal-link delivery. That requires the
live association file, a correctly provisioned app, and a real OS link handoff.
