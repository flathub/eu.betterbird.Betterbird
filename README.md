# Betterbird (Flathub)

Betterbird is a fine-tuned version of [Mozilla Thunderbird](https://www.thunderbird.net/), Thunderbird on steroids, if you will.

[Betterbird](https://betterbird.eu/) for [Flatpak](https://flatpak.org/) installation instructions are available by [clicking here to visit the Betterbird app page on Flathub](https://flathub.org/apps/details/eu.betterbird.Betterbird).

## Useful links
- [Flathub builds](https://buildbot.flathub.org/#/apps/eu.betterbird.Betterbird)
- [Betterbird repo](https://github.com/Betterbird/thunderbird-patches)
- [Thunderbird flathub repo](https://github.com/flathub/org.mozilla.Thunderbird)
- [Thunderbird 102 builds](https://treeherder.mozilla.org/jobs?repo=comm-esr102)

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

## Known issues
#### Language support
The Betterbird flatpak ships all language packs that are currently available for Betterbird. Flatpak installs a selection matching the user configuration that has been set with `flatpak config --set languages` and `flatpak config --set extra-languages`, defaulting to the system language. **Thunderbird language packs do not work with Betterbird**, so do not attempt to install them.
In case the localization of your Betterbird is incomplete, check if a Thunderbird language pack is installed (e.g. after migrating your profile from Thunderbird to Betterbird) and remove it.

#### Wayland
([#75](https://github.com/flathub/org.mozilla.Thunderbird/issues/75)) To enable the experimental [Wayland](https://wayland.freedesktop.org/) backend (assuming the desktop session runs under a Wayland):<br>
1. Give the `eu.betterbird.Betterbird` flatpak the `--socket=wayland` permission, e.g. by using [Flatseal](https://flathub.org/apps/details/com.github.tchx84.Flatseal).
2. Run `flatpak override --env=MOZ_ENABLE_WAYLAND=1 eu.betterbird.Betterbird` to enable the Wayland backend.

#### Smartcard
([#51](https://github.com/flathub/org.mozilla.Thunderbird/issues/51)) For Smartcard support you need at least Flatpak 1.3.2.

#### Lacking file permissions / inconsistent access
([#263](https://github.com/flathub/org.mozilla.Thunderbird/issues/263)) Thunderbird does not use '[Portals](https://docs.flatpak.org/en/latest/sandbox-permissions.html#portals)' for file access everywhere leading to an inconsistent user experience. For example:
- When attaching a file using the "Attach" button in the compose window, you can select any file and attach it successfully.
- Drag & drop or attaching a mail signature from a file only works for files in a limited set of folders, e.g. ~/Downloads. 
- Composing a new mail with attachment from the command line by running `flatpak -compose "attachment='file:///home/username/file.txt'"` works only for files in a limited set of folders.
- When selecting a default location for saving attachments, the selected folder is replaced by some path under `/run/user/1000/doc`. (This one is actually a consequence of using the Portals mechanism, but can also be avoided by applying the work around below.)

You can work around this issue by giving the Betterbird flatpak access to your complete home directory, either by starting it using `flatpak run --filesystem=home:rw eu.betterbird.Betterbird` or by giving it the `filesystem=home` permission using Flatseal. 

**Caveats**: Once Betterbird has access to your home directory, it will use the profile in `~/.thunderbird` instead of `~/.var/app/eu.betterbird.Betterbird/.thunderbird`. Meaning that in order to keep using your current profile, you will have to move it to `~/.thunderbird` after applying the work-around. Make sure that Betterbird is closed while moving the profile!

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
