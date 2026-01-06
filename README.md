# Betterbird (Flathub)

Betterbird is a fine-tuned version of [Mozilla Thunderbird](https://www.thunderbird.net/), Thunderbird on steroids, if you will.

[Betterbird](https://betterbird.eu/) for [Flatpak](https://flatpak.org/) installation instructions are available by [clicking here to visit the Betterbird app page on Flathub](https://flathub.org/apps/details/eu.betterbird.Betterbird).

## Useful links
- [Flathub builds](https://buildbot.flathub.org/#/apps/eu.betterbird.Betterbird)
- [Betterbird repo](https://github.com/Betterbird/thunderbird-patches)
- [Thunderbird flatpak build script](https://searchfox.org/comm-central/source/taskcluster/docker/tb-flatpak/repack.sh)
- [Thunderbird 140 builds](https://treeherder.mozilla.org/jobs?repo=comm-esr140)
- [Mozilla Code Search](https://searchfox.org/)
- [Firefox ESR release schedule](https://whattrainisitnow.com/release/?version=esr)
- [Firefox Rust version schedule](https://searchfox.org/mozilla-central/source/docs/writing-rust-code/update-policy.md#73)

## Migration from pre-exisiting installations

#### Migration from pre-exisiting Thunderbird flatpak installations
In order to migrate from pre-exisiting Thunderbird flatpak installation and preserve all settings please copy or move entire<br>
`~/.var/app/org.mozilla.Thunderbird/.thunderbird`<br>
folder into<br>
`~/.var/app/eu.betterbird.Betterbird/.thunderbird`<br>
When starting Betterbird for the first time, check if a Thunderbird language pack is installed (that has been migrated with your profile) and remove it.

#### Migration from pre-exisiting Thunderbird non-flatpak installations
In order to migrate from pre-exisiting non-flatpak Thunderbird installation and preserve all settings please copy or move entire<br>
`~/.thunderbird`<br>
folder into<br>
`~/.var/app/eu.betterbird.Betterbird/.thunderbird`<br>
When starting Betterbird for the first time, check if a Thunderbird language pack is installed (that has been migrated with your profile) and remove it.

#### Migration from pre-exisiting Betterbird non-flatpak installations
In order to migrate from pre-exisiting non-flatpak Betterbird installation and preserve all settings please copy or move entire<br>
`~/.thunderbird`<br>
folder into<br>
`~/.var/app/eu.betterbird.Betterbird/.thunderbird`

In case Betterbird opens a new profile instead of the existing one, run:<br>
`flatpak run eu.betterbird.Betterbird -P`<br>
then select the right profile and tick "*Use the selected profile without asking on startup*" box.

## Customizing the icons
In order to customize the app icon or the status icons:
1. Check the value of the `$XDG_DATA_HOME` environment variable. If it is unset, it means that the default value of `~/.local/share` is effective.
2. Save your custom app icon as `$XDG_DATA_HOME/icons/hicolor/scalable/apps/eu.betterbird.Betterbird.svg`. Create any folders that may be inexistent.
3. Custom status icons (shown in the systray) go into the `$XDG_DATA_HOME/icons/hicolor/scalable/status/` folder and must be named `eu.betterbird.Betterbird-default.svg` and `eu.betterbird.Betterbird-newmail.svg` respectively. 
4. Reboot.

## Known issues
#### Language support
The Betterbird flatpak ships all language packs that are currently available for Betterbird. Flatpak installs a selection matching the user configuration that has been set with `flatpak config --set languages` and `flatpak config --set extra-languages`, defaulting to the system language. **Thunderbird language packs do not work with Betterbird**, so do not attempt to install them.
In case the localization of your Betterbird is incomplete, check if a Thunderbird language pack is installed (e.g. after migrating your profile from Thunderbird to Betterbird) and remove it.

#### Smartcard
([#51](https://github.com/flathub/org.mozilla.Thunderbird/issues/51)) For Smartcard support you need at least Flatpak 1.3.2.

#### Lacking file permissions / inconsistent access
([#263](https://github.com/flathub/org.mozilla.Thunderbird/issues/263)) Thunderbird does not use '[Portals](https://docs.flatpak.org/en/latest/sandbox-permissions.html#portals)' for file access everywhere leading to an inconsistent user experience. For example:
- When attaching a file using the "Attach" button in the compose window, you can select any file and attach it successfully.
- Drag & drop or attaching a mail signature from a file only works for files in a limited set of folders, e.g. ~/Downloads. 
- Composing a new mail with attachment from the command line by running `flatpak -compose "attachment='file:///home/username/file.txt'"` works only for files in a limited set of folders.
- When selecting a default location for saving attachments, the selected folder is replaced by some path under `/run/user/1000/doc`. (This one is actually a consequence of using the Portals mechanism, but can also be avoided by applying the work around below.)

You can work around this issue by giving the Betterbird flatpak access to your complete home directory 
* temporarily: by starting Betterbird using `flatpak run --filesystem=home:rw eu.betterbird.Betterbird` every time.
* permanently: by giving Betterbird the `filesystem=home` permission using the [Flatseal app](https://flathub.org/apps/details/com.github.tchx84.Flatseal) or by running `flatpak override --user --filesystem=home eu.betterbird.Betterbird` (once is enough). 

**Caveats**: Once Betterbird has access to your home directory, it will use the profile in `~/.thunderbird` instead of `~/.var/app/eu.betterbird.Betterbird/.thunderbird`. Meaning that in order to keep using your current profile, you will have to move it to `~/.thunderbird` after applying the work-around. Make sure that Betterbird is closed while moving the profile!

#### Sending documents as mail attachments from LibreOffice
Sending a document from LibreOffice using the flatpak-version of Betterbird does not work by default because of the isolation that the flatpak sandbox provides. There is, however, a way to work around this. The work-around depends on wether you are using the flatpak version of LibreOffice or a non-flatpak version of LibreOffice.

##### Work-around for non-flatpak LibreOffice 
1. Create a wrapper script at `~/.local/bin/betterbird` with the following content (add the `--user` flag to `flatpak run` in case you have installed Betterbird in your user installation).
    ```bash
    #!/bin/bash
    flatpak run eu.betterbird.Betterbird "$@"
    ```
    While you are free to choose any folder to place the script in, the script file must be named `betterbird` (case-sensitive) because [LibreOffice uses the name to decide how it calls the e-mail client](https://github.com/Betterbird/thunderbird-patches/issues/85#issuecomment-1271865427).

2. In any of the LibreOffice apps, configure `~/.local/bin/betterbird` as your e-mail program (setting at Extras -> Options -> Internet -> E-Mail).
   
3. Give Betterbird the `filesystem=/tmp` permission using the [Flatseal app](https://flathub.org/apps/details/com.github.tchx84.Flatseal) or by running `flatpak override --user --filesystem=/tmp eu.betterbird.Betterbird` (once is enough). This is needed because LibreOffice places the document to be attached in `/tmp` on the host.


##### Work-around for flatpak-version of LibreOffice 
1. Make sure you have `flatpak-spawn`. For Fedora, this comes as its own `dnf` package named `flatpak-spawn`.
2. Create a wrapper script at `~/.local/bin/betterbird` with the following content (add the `--user` flag to `flatpak run` in case you have installed Betterbird in your user installation). 
    ```bash
    #!/bin/bash
    flatpak-spawn --host flatpak run eu.betterbird.Betterbird "$@"
    ```
    While you are free to choose any folder to place the script in, the script file must be named `betterbird` (case-sensitive) because [LibreOffice uses the name to decide how it calls the e-mail client](https://github.com/Betterbird/thunderbird-patches/issues/85#issuecomment-1271865427).

3. In any of the LibreOffice apps, configure `~/.local/bin/betterbird` as your e-mail program (setting at Extras -> Options -> Internet -> E-Mail).
   
4. Give Betterbird the `filesystem=/tmp` permission using the [Flatseal app](https://flathub.org/apps/details/com.github.tchx84.Flatseal) or by running `flatpak override --user --filesystem=/tmp eu.betterbird.Betterbird` (once is enough). This is needed because LibreOffice places the document to be attached in `/tmp` on the host.

5. Give LibreOffice the `filesystem=/tmp` and `talk-name=org.freedesktop.Flatpak` permissions using the [Flatseal app](https://flathub.org/apps/details/com.github.tchx84.Flatseal) or by running `flatpak override --user --filesystem=/tmp --talk-name=org.freedesktop.Flatpak org.libreoffice.LibreOffice` (once is enough). This enables LibreOffice to run `flatpak-spawn` in the Betterbird wrapper script and gives it access to `/tmp` on the host, so it can place the document to be attached in a folder where Betterbird can see it.

#### Other flatpak issues unresolved yet by upstream
([#123](https://github.com/flathub/org.mozilla.Thunderbird/issues/123)) Opening Profile Directory doesn't work: https://bugzilla.mozilla.org/show_bug.cgi?id=1625111

## Bug Reporting / Support

For issues related to the flathub package for Betterbird, please check [the issue tracker for this repository](https://github.com/flathub/eu.betterbird.Betterbird/issues) if the issue has already been reported and open a new issue otherwise.

For bugs concerning Betterbird itself, please read [www.betterbird.eu/support/](https://www.betterbird.eu/support/) before creating a bug report in the [Betterbird issue tracker](https://github.com/Betterbird/thunderbird-patches/issues). Here is an abridged version of the bug reporting guidelines:

1. Thunderbird has 14.000+ bugs which won't be fixed as part of Betterbird.
1. First step: Check whether the bug exists in Thunderbird. If so, check whether it has been reported at [Bugzilla](https://bugzilla.mozilla.org/). If reported, please let us know the bug number. If not reported, either you or our project will need to report it (see following item).
1. If the bug is also in Thunderbird, let us know that it's important to you, please provide reasons why Betterbird should fix it and not upstream Thunderbird. We'll check whether we deem it "must have" enough to fix it considering the necessary effort.
1. If the bug is only in Betterbird, let us know, we'll endeavour to fix it asap, usually within days.
1. Common sense bug reporting rules apply: Bug needs to be reproducible, user needs to cooperate in debugging.
