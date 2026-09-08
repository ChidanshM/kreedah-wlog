# Permanent signing key

Android treats a change of signing key as a change of app. A build signed with
a different key than the one already installed cannot update it — the install
fails, and the only way forward is to uninstall, which deletes the database.

Early builds were signed with whatever throwaway debug key the build machine
happened to have, so this happened. A permanent key fixes it: every build
carries the same identity and installs straight over the previous one.

## Repository secrets

Four secrets, added under **Settings → Secrets and variables → Actions**.

| Name | Value |
|---|---|
| `KEYSTORE_B64` | the keystore, base64 encoded, as a single line |
| `KEYSTORE_PASSWORD` | the keystore password |
| `KEY_ALIAS` | `wlog` |
| `KEY_PASSWORD` | same as `KEYSTORE_PASSWORD` |

The workflow decodes `KEYSTORE_B64` into a temporary file and re-signs the
built APKs with `apksigner`. It signs the artefact rather than patching
Flutter's generated Gradle files, so it does not break when Flutter changes
its build templates. The build fails loudly if the secrets are missing rather
than silently producing an APK that cannot update the installed one.

## The keystore itself

`wlog.jks` and its password are **not** in this repository and must never be.
`.gitignore` blocks `*.jks`, `*.keystore` and `key.properties` as a safety net,
but the file belongs outside the project entirely — a password manager or an
encrypted drive.

Losing it means the installed app can never be updated again. Recovering
requires generating a new key, and installing a build signed with it costs
another uninstall and another wipe.

## Generating a replacement

```bash
keytool -genkeypair -v -keystore wlog.jks -alias wlog \
  -keyalg RSA -keysize 4096 -validity 10000 \
  -dname "CN=wlog, OU=personal, O=kreedah, L=, ST=, C="

base64 -w0 wlog.jks > wlog.jks.b64
```

Paste the contents of `wlog.jks.b64` into the `KEYSTORE_B64` secret, then
delete that file — it carries exactly the same risk as the keystore.

Changing keys always costs one uninstall. Do it before accumulating training
history, never after.

## The application ID is separate, and also permanent

`com.kreedah.workout_log`, set by `--org` in the workflow. Android treats it
as the app's identity, so changing it produces a different app: it installs
alongside the old one rather than updating it, and it cannot reach the old
app's database or its export folder.

It is fixed permanently the moment the app is published to any store. Settle
it before that, never after.

## Verifying a build

The signing step prints the certificate fingerprint of every APK it signs.
It should match across builds. If it changes, the key changed, and that build
will not install over the previous one.
