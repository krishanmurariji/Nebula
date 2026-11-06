# Building and releasing the Android app

Every push to `master` or a `claude/**` branch builds a release APK in GitHub
Actions and publishes it to a rolling pre-release called **dev-latest**.
Pushing a tag like `v1.0.0` publishes a permanent, versioned release instead.

| What | Link (replace `OWNER/REPO`) |
|---|---|
| Newest build of any branch | `https://github.com/OWNER/REPO/releases/download/dev-latest/nebula.apk` |
| Newest tagged release | `https://github.com/OWNER/REPO/releases/latest/download/nebula.apk` |

Open either link on the phone, download, install. Or install
[Obtainium](https://github.com/ImranR98/Obtainium) and add the repo URL: it
watches the releases and offers every new build as an update.

## One-time setup: the signing key

Android only installs an update over an existing app when both are signed with
**the same key**. Without your own key, each CI run signs with a different
throwaway key and the phone refuses the update ("signature mismatch").

1. Create a key once (Windows PowerShell; `keytool` ships with Android Studio):

   ```powershell
   & "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" -genkeypair -v `
     -keystore nebula-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias nebula
   ```

   Pick strong passwords and remember them.

2. **Back up `nebula-release.jks` and the passwords somewhere safe** (not in the
   repo). If you lose them you can never publish an update that installs over
   the old app.

3. Put the file into a secret:

   ```powershell
   [Convert]::ToBase64String([IO.File]::ReadAllBytes("nebula-release.jks")) | Set-Clipboard
   ```

4. GitHub → repo → **Settings → Secrets and variables → Actions → New
   repository secret**, add four secrets:

   | Name | Value |
   |---|---|
   | `ANDROID_KEYSTORE_BASE64` | the base64 text from step 3 |
   | `ANDROID_KEYSTORE_PASSWORD` | the keystore password |
   | `ANDROID_KEY_ALIAS` | `nebula` |
   | `ANDROID_KEY_PASSWORD` | the key password |

Until the secrets exist, branch builds still work (debug key, with a warning in
the run log) but **tag builds refuse to publish**, so a versioned release can
never be signed with a throwaway key.

The first time you install a CI build, uninstall any copy you installed with
`flutter run` first: it was signed with your local debug key.

## Cutting a versioned release

```bash
git tag v1.0.0
git push origin v1.0.0
```

The app version comes from the tag; the Android version code is the workflow run
number, so it always increases.

## Local release build with the same key (optional)

Create `android/key.properties` (git-ignored) pointing at your `.jks`:

```properties
storePassword=...
keyPassword=...
keyAlias=nebula
storeFile=C:/path/to/nebula-release.jks
```

then `flutter build apk --release`.
