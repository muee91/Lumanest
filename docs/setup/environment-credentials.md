# LumaNest environment credentials

Real map and weather verification uses local Dart defines. Secrets must never be
added to source, tests, screenshots, logs, or Git.

## 1. AMap Android key

Create an Android key in the AMap console with:

- Package name: `com.muee.lumanest`
- Debug SHA1: `53:6C:6B:58:4A:02:03:44:B2:BA:BC:51:9B:66:AD:4E:99:5B:60:55`

The release key must be created separately when a release keystore exists.

## 2. QWeather credentials

Create a QWeather project and obtain both values:

- Project API Host, for example `abcxyz.qweatherapi.com`
- API Key used through the `X-QW-Api-Key` request header

Use the exact API Host shown in the project console. Do not assume the legacy
shared development host.

## 3. Local secret file

Create `.secrets/environment.debug.json` locally:

```json
{
  "AMAP_ANDROID_KEY": "replace-locally",
  "QWEATHER_API_HOST": "https://replace-locally.qweatherapi.com",
  "QWEATHER_API_KEY": "replace-locally"
}
```

The `.secrets/` directory is ignored by Git.

Run with:

```bash
flutter run --dart-define-from-file=.secrets/environment.debug.json
```

Build with:

```bash
flutter build apk --debug \
  --dart-define-from-file=.secrets/environment.debug.json
```

## 4. Privacy order

1. Show the in-app privacy disclosure.
2. Record explicit user agreement.
3. Notify AMap SDK of privacy agreement and initialize it.
4. Request the operating-system foreground location permission.

Do not initialize AMap or request location before the corresponding disclosure.
