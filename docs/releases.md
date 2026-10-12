# Releases and updates

## Releases

Each release carries two builds, named for their platform: `DevDeck-<version>-<build>-macos.zip` and the Windows installer `DevDeck-<version>-<build>-windows-setup.exe` with its SHA256 file.

Publishing a release on GitHub builds the app and attaches it: `.github/workflows/release.yml`
runs the suite, builds the bundle and uploads `DevDeck-<version>-<build>-macos.zip` to the tag, so the
tag and the download cannot disagree about what is in it. Nothing is built on an ordinary push,
because a build nobody asked for is a build nobody checks. `.github/workflows/tests.yml` runs the
suite on every push to main and on every pull request and fails on a compiler warning, which is the one place
nobody is in a hurry.

**Releases are signed with a Developer ID, hardened, notarised by Apple and stapled on the
runner**, from 0.12 on. macOS opens the download as it is: unzip, drag into Applications, open.
It takes five repository secrets, `DEVELOPER_ID_P12`, `DEVELOPER_ID_P12_PASSWORD`,
`NOTARY_KEY_ID`, `NOTARY_ISSUER_ID` and `NOTARY_KEY_P8`; [docs/development.md](development.md)
says where each comes from. `DEVELOPER_ID_P12` and `NOTARY_KEY_P8` decide the path, so with those
two set a missing or wrong other secret fails the release rather than quietly shipping ad-hoc. Notarisation is Apple's queue and takes minutes, occasionally most of
an hour.

Without those two the workflow builds the ad-hoc release it always did, and macOS quarantines
that download. The notes then carry two routes: Finder (unzip, drag into Applications,
right-click and Open, which needs no permissions), and a line for a terminal that may read
Downloads:

```
pkill -f "DevDeck.app/Contents/MacOS/DevDeck"; ditto -x -k ~/Downloads/DevDeck-<version>-<build>-macos.zip /Applications && xattr -dr com.apple.quarantine /Applications/DevDeck.app && open /Applications/DevDeck.app
```

The workflow writes the install section itself, naming the file it actually built and saying
which of the two builds it is, so a version number is never typed by hand into the notes.

To cut a release: bump `VERSION`, commit, then create the release on GitHub with a tag like
`v0.18`. The build number in the bundle is the commit count, so it moves on its own. A manual
run of the workflow against an existing tag builds that tag's commit and replaces its asset.

## Updating

From 0.11 on the app keeps itself current, by asking rather than by doing. Thirty seconds after
launch and every six hours it reads the latest release on GitHub; when that is newer than the
running copy, the menu-bar menu has an **Update to …** row under Good to know and one banner says
so, once per version and only if notifications and **New versions of DevDeck** are on. Nothing is downloaded until you ask:
that line, the banner, **Update Now** in Settings, or `open -a DevDeck --args --update`. Then:
download, `ditto`, a check that what unpacked is DevDeck at the promised version and, from a
signed copy, signed by the same identity as the running one, the old copy to the Trash, the new
one in its place, and a relaunch a second later with every panel where it was. Option-click the
row to read the notes first. A copy signed with a certificate of your own therefore does not
update itself to a release, which is signed with the Developer ID.

A copy opened straight from Downloads without being moved to Applications runs from a read-only
folder macOS makes for it, and cannot be replaced where it is. Its update goes into
`/Applications/DevDeck.app` instead (`~/Applications` without the right to write there), the old
copy in Downloads goes to the Trash, and General in Settings says why the copy is read-only rather
than showing the random folder it runs from.

What the app downloads itself carries no quarantine, so an update never needs the right-click
dance a first install does. No install starts while a card is mid-command, however it was asked
for, because replacing the bundle under a running `fusion start` is how a stack is left half up:
the row says what it waits for, and an install already asked for goes ahead by itself once the
command is done. Settings, General has the switch and a **Check Now** button with the last answer beside it. See
[adr/0016-self-update.md](adr/0016-self-update.md).
