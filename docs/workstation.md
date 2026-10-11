# The workstation image

A full Linux desktop in a sandbox: XFCE with a panel and an applications menu,
a file manager, a browser, a paint program and the everyday tools, and Flatpak,
so more can be installed without root. You see and use it in Studio's
**Desktop** tab, exactly as you would the desktop image.

It is the desktop image from sandbox-cli (`sandbox-desktop`) with more on top,
so everything in that image and the base image is here too: the agents, git,
the toolchains, Chromium.

## Making one

```sh
sandbox-cli run --keep --name ws \
  --image ghcr.io/amitgb14/sandbox-workstation:edge \
  --cpus 2 --memory 4096 -- true
```

Then `sandbox-cli studio`, the sandbox's **Desktop** tab, **Start desktop**.

Give it 2 CPUs and 4 GiB. It works in less, but a browser and a paint program
side by side in 2 GiB are slow. The image is large (about 2 GB more than the
desktop image, most of it Pinta's runtime), so the first sandbox from it on a
machine takes a while to build its disk.

## What's in it

| | Program | From |
|---|---|---|
| Desktop | XFCE 4.18: panel, desktop, settings, app finder, notifications | Debian |
| Files | Thunar, with trash, thumbnails and archives (file-roller) | Debian |
| Browser | Chromium | the desktop image |
| Paint | Pinta | Flathub, installed in the image |
| Terminal | xfce4-terminal (and xterm) | Debian |
| Text | Mousepad | Debian |
| Images | Ristretto | Debian |
| PDF | Evince | Debian |
| Installing | Flatpak, with Flathub | Debian |

The display is TigerVNC's `Xvnc`: the X server and the VNC server in one
process, listening on the guest's loopback, port 5900, with no password — the
same port and the same rules as the desktop image. A viewer may resize the
screen to fit its window.

## Installing more

Every process in a sandbox runs as the sandbox user (uid 1001), so `apt
install` does not work. Everything below does, and installs into HOME, so it
lives with the sandbox's work and is kept in its snapshots.

- **Flatpak, from Flathub** — most desktop apps: GIMP, LibreOffice, Inkscape,
  VS Code, Firefox, Krita and so on. Flathub is already set up for the user.

  ```sh
  flatpak search gimp
  flatpak install --user -y flathub org.gimp.GIMP
  ```

  It appears in the applications menu straight away.

- **AppImages** — download one, `chmod +x`, run it. The guest has no FUSE, so
  it unpacks itself to a temporary directory and runs from there
  (`APPIMAGE_EXTRACT_AND_RUN=1` is set for the desktop and for login shells).
  Starting it is slower than usual; running it is not.

- **Language package managers** — pip, npm, cargo, go: as in any sandbox.

Installing needs the network to reach Flathub (`dl.flathub.org`, `flathub.org`)
and whatever the app downloads. Use `--network open`, or an allowlist naming
those.

Pinta is installed system-wide, in the image: it works with no network at all,
and the sandbox user can run it but not remove or update it.

## Settings

`sandbox-desktop` reads the desktop image's two variables, and one more:

| Variable | Default | |
|---|---|---|
| `SANDBOX_DESKTOP_SIZE` | `1280x800x24` | the screen at start: width x height x depth |
| `SANDBOX_DESKTOP_PORT` | `5900` | the VNC port; Studio's tab reaches 5900 only |
| `SANDBOX_DESKTOP_SESSION` | `xfce` | `openbox` for the desktop image's lighter session |

## What is different from the desktop image

- **No setuid or setgid programs.** The image removes the bit from every file.
  Nothing in it needs to change user, and Flatpak's bubblewrap uses user
  namespaces instead. The guest mounts the image without `nosuid`, so a
  setuid program left in it would be a way to root inside the guest that no
  sandbox setting asked for.
- **Xvnc instead of Xvfb and x11vnc**, so one process, and resizable.
- **No compositor and a plain background.** With no GPU, shadows and a
  photograph are drawn in software and sent as pixels on every change.

## Limits

- **No GPU.** Firecracker has none to give the guest, so everything draws in
  software (Mesa's llvmpipe). Browsing, office work and painting are fine;
  video, 3D and games are slow.
- **No sound**, yet.
- **No FUSE**, so AppImages unpack themselves (above), and Flatpak's document
  portal is absent: a Flatpak app reaches files through its own permissions
  rather than through files you hand it one at a time. Pinta is given all of
  HOME. An app you install may name only Pictures, Documents and the like; to
  give it HOME too: `flatpak override --user --filesystem=home <app id>`.
- **It keeps the sandbox up**, as the desktop image does: a running desktop is
  activity, so the sandbox never reaches its idle timeout. Stop the desktop,
  or the sandbox, when you are done.

## Checking on a real host

`tests/smoke.sh IMAGE` checks a built image in a container: the programs are
there, nothing is setuid, the desktop starts as the sandbox user and serves VNC
on loopback only. A container cannot run a Flatpak app (bubblewrap needs to
mount `/proc` in a new namespace), so that part is checked in a Firecracker
guest. With a local `sandboxd` and a throwaway registry:

```sh
podman build -t localhost/sandbox-workstation:dev images/workstation
podman run -d --name wsreg -p 127.0.0.1:5005:5000 docker.io/library/registry:2
podman push --tls-verify=false localhost/sandbox-workstation:dev 127.0.0.1:5005/sandbox-workstation:dev

sandboxd --backend firecracker --kernel ~/.local/share/sandboxd/vmlinux \
  --firecracker ~/.local/bin/firecracker --insecure-registry 127.0.0.1:5005 &

sandbox-cli run --image 127.0.0.1:5005/sandbox-workstation:dev --cpus 2 --memory 4096 -- sh -c '
  sandbox-desktop >/tmp/desk.log 2>&1 & sleep 6
  export DISPLAY=:1 XDG_RUNTIME_DIR=/tmp/runtime-$(id -u)
  dbus-launch flatpak run com.github.PintaProject.Pinta >/tmp/pinta.log 2>&1 & sleep 30
  xwininfo -root -tree | grep -i pinta'
# expect a window named "Unsaved Image 1 - Pinta"
```

**A `sandboxd` run without root** (as above) builds disks whose files all belong
to the building user, not to the sandbox user, and says so in its log ("built
without root"). Directories the image made for the sandbox user, `~/.cache`
among them, are then not writable, and `flatpak run` fails with a bare
`error: Permission denied`. Prefix the command with `XDG_CACHE_HOME=/tmp/cache`
there. A `sandboxd` run as root, as on a server, keeps the image's owners and
needs nothing of the kind.

Checked on 2026-10-11, Linux, Firecracker 1.17, guest kernel 6.1.155: the
desktop started, VNC answered on 127.0.0.1:5900, no setuid files, Pinta opened
its window, Flathub was set up for the user. Not yet checked: installing from
Flathub inside a guest (the local `sandboxd` had no network), Studio's
Desktop tab against this image, arm64.
