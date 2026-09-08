# Adding the brand typefaces

The Botanical Vitality spec names **Playfair Display** for headlines and
**Inter** for body, labels and data. Both are free, but a phone app that
works offline has to carry the font files inside it rather than fetch them
from Google Fonts the way a website does — and those files aren't included
here.

Until they're added, the app runs on Android's default typeface. Every
other part of the brand — colours, spacing, radii, the type scale, tabular
figures — is already applied. Adding the fonts is the last 10%.

## Steps

1. Go to fonts.google.com and download **Playfair Display** and **Inter**.
   Each arrives as a zip.
2. Inside the app folder, make a new folder: `assets/fonts`
3. From the Playfair zip, copy these two files into `assets/fonts`:
   - `PlayfairDisplay-SemiBold.ttf`
   - `PlayfairDisplay-Bold.ttf`
4. From the Inter zip, copy these three:
   - `Inter-Regular.ttf`
   - `Inter-Medium.ttf`
   - `Inter-SemiBold.ttf`

   Newer Google Fonts downloads sometimes ship one variable-weight file
   named `Inter-VariableFont_opsz,wght.ttf` instead of separate weights.
   If that's what you get, look in the `static` subfolder of the zip —
   the individual weight files are in there.

5. Open `pubspec.yaml` and add this underneath the existing `assets:`
   block, at the same indentation as `assets:`:

```yaml
  fonts:
    - family: PlayfairDisplay
      fonts:
        - asset: assets/fonts/PlayfairDisplay-SemiBold.ttf
          weight: 600
        - asset: assets/fonts/PlayfairDisplay-Bold.ttf
          weight: 700
    - family: Inter
      fonts:
        - asset: assets/fonts/Inter-Regular.ttf
          weight: 400
        - asset: assets/fonts/Inter-Medium.ttf
          weight: 500
        - asset: assets/fonts/Inter-SemiBold.ttf
          weight: 600
```

6. Open `lib/theme.dart` and change these two lines near the top:

```dart
const String? kDisplayFont = 'PlayfairDisplay';
const String? kBodyFont = 'Inter';
```

7. Rebuild.

## If the build breaks after this

The usual cause is a filename that doesn't match. Flutter fails with
"unable to locate asset entry" and names the file it couldn't find —
check the spelling against what's actually in `assets/fonts`, or send me
the error.

To back out, set both font constants to `null` again and delete the
`fonts:` block. The app returns to the system typeface.
