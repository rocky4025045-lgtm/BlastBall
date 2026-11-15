# Blast Ball — 1,000 stages

Pop every ball before it touches a screen edge. Stage N needs exactly N blasts;
never more than 10 balls on screen. Progress is saved between launches.

## Get it on your iPhone without a Mac

1. Create a new GitHub repository and upload everything in this folder
   (including the hidden `.github` folder).
2. Open the repo's **Actions** tab → **Build Blast Ball IPA** → **Run workflow**.
   It runs the tests and builds `BlastBall-unsigned.ipa` (about 5–10 minutes).
3. Download the artifact from the finished run and unzip it to get the `.ipa`.
4. On a Windows PC or Mac, install **Sideloadly** (sideloadly.io), connect your
   iPhone by USB, drag in the `.ipa`, enter your Apple ID and press Start.
   Sideloadly signs it for your device automatically.
5. On the iPhone: Settings → General → VPN & Device Management → trust your
   Apple ID; then Settings → Privacy & Security → Developer Mode → On (restart).

Free Apple ID: the app runs for 7 days, then re-sign it with Sideloadly.
Paid Apple Developer account: register your UDID under Certificates, IDs &
Profiles → Devices, and the signed app lasts up to a year.

## With a Mac instead
`brew install xcodegen && xcodegen generate`, open `BlastBall.xcodeproj`,
pick your Team under Signing & Capabilities, choose your iPhone, press ⌘R.
