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

`flatpak` is a small wrapper (`/usr/local/bin/flatpak`) around Debian's. The
guest runs no system services, so it has no D-Bus system bus, and Flatpak asks
that bus about parental controls before it installs an app: with no bus at all
it fails ("Could not connect: No such file or directory"). The wrapper starts a
private bus for the sandbox user, with nothing on it, and Flatpak then skips the
check as it does on any machine without parental controls.

Pinta is installed system-wide, in the image: it works with no network at all,
and the sandbox user can run it but not remove or update it.

## Settings

`sandbox-desktop` reads the desktop image's two variables, and two more:

| Variable | Default | |
|---|---|---|
| `SANDBOX_DESKTOP_SIZE` | `1280x800x24` | the screen at start: width x height x depth |
| `SANDBOX_DESKTOP_PORT` | `5900` | the VNC port; Studio's tab reaches 5900 only |
| `SANDBOX_DESKTOP_SESSION` | `xfce` | `openbox` for the desktop image's lighter session |
| `SANDBOX_DESKTOP_GPU` | `auto` | `auto`: OpenGL on the sandbox's GPU when it has one that answers, in software otherwise; `on`: the GPU, or the desktop does not start; `off`: software (see "With a GPU") |

Running `sandbox-desktop` while a desktop is already up starts nothing: it says
so and stays in the foreground for as long as that desktop runs. Studio's
Desktop tab runs it each time it connects, and an agent's tools may have
started the desktop first.

## With a GPU

In a sandbox given a GPU (`sandbox-cli run --gpus 1`, on a node that serves
one), OpenGL programs started on the desktop draw on the card. Nothing else
changes: the same display, the same port, Studio's same Desktop tab.

```sh
sandbox-cli run --keep --name gws --gpus 1 \
  --image ghcr.io/amitgb14/sandbox-workstation:edge \
  --cpus 4 --memory 8192 -- true
```

`sandbox-desktop` asks the card for an OpenGL renderer when it starts. When it
answers, the whole session runs through [VirtualGL](https://virtualgl.org):
each program's OpenGL is drawn on the card, through NVIDIA's EGL driver with
no X server on the card, and every frame is copied to the VNC display. It says
which in its log and in `$XDG_RUNTIME_DIR/sandbox-desktop.gl`:

```
sandbox-desktop: OpenGL draws on the GPU: NVIDIA GeForce RTX 5070 Ti/PCIe/SSE2
```

The driver is not in the image. sandboxd adds the node's GPU kit to a GPU
sandbox's root disk, and the kit has NVIDIA's OpenGL, EGL and Vulkan drivers
beside CUDA's.

| | With a GPU |
|---|---|
| OpenGL programs started on the desktop, or from a terminal on it (Blender, glxgears, a game on OpenGL) | the GPU |
| `glxspheres64` (VirtualGL's own test, in `/opt/VirtualGL/bin`) | about 2000 frames a second on an RTX 5070 Ti, against about 120 in software |
| Chromium and Chrome | software: their GPU process does not take VirtualGL's visual ("Invalid visual ID"), and they fall back to drawing it themselves. Browsing is as without a GPU |
| Flatpak apps | software: an app's own runtime has its own Mesa, and VirtualGL does not reach inside its sandbox |
| Vulkan | the card is there (`/usr/share/vulkan/icd.d/nvidia_icd.json`), for compute and drawing off screen; but NVIDIA's driver cannot make a Vulkan window on this display (`vkcube` picks the card, then fails to make its swapchain), so games on Vulkan (and Proton) do not work yet |
| CUDA | as in any GPU sandbox; the [CUDA image](cuda.md) has the compiler |

What a frame costs: it is drawn on the card, copied back to memory, and then
encoded and sent to the viewer like any change on the screen. A program that
draws thousands of frames a second shows as many as the viewer's connection
carries.

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

- **No GPU, unless the sandbox has one.** A sandbox without `--gpus` draws
  everything in software (Mesa's llvmpipe). Browsing, office work and painting are fine;
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

**With a GPU.** Given a GPU kit and `GPU_DEVICES=1`, `tests/smoke.sh` also
adds the kit to the image as sandboxd does, gives the container the host's
`/dev/nvidia0`, `/dev/nvidiactl` and `/dev/nvidia-uvm*` (the nodes a GPU
sandbox has), and checks that the desktop draws on the card: the renderer is
NVIDIA's, the session runs through VirtualGL, and `glxspheres64` draws frames
on the card. The host's NVIDIA driver must be the kit's version, as the kit's
libraries talk to the host's kernel module.

```sh
ENGINE=podman GPU_KIT=/var/lib/sandboxd/gpu-kit GPU_DEVICES=1 \
  sh tests/smoke.sh localhost/sandbox-workstation:dev
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
its window, Flathub was set up for the user.

Checked on 2026-10-15 in a guest with network (Firecracker, through the
agentos image): `flatpak install --user` failed for want of a system bus, which
the wrapper above now provides; with it, GNOME Calculator installed from
Flathub.

Checked on 2026-10-15 with Studio's Desktop tab on a desktop that was already
running: each time the tab connected it ran `sandbox-desktop`, which started a
second XFCE session on the same display ("The notification area lost
selection"). It now reuses the running desktop, under a lock, and
tests/smoke.sh checks it. Not yet checked: arm64.

Checked on 2026-10-18 with the host's RTX 5070 Ti and driver 610.43.02 (the
kit's), in a container as above: the desktop drew on the card
(`NVIDIA GeForce RTX 5070 Ti/PCIe/SSE2`), `glxspheres64` drew about 2000 frames
a second against about 120 with llvmpipe, Chromium started in the session and
drew in software, and `vkcube` found the card but could not make a window. Not
yet checked: the same in a sandbox given the card, which waits for the node to
hand it over (sandbox-cli's docs/gpu.md, step 3).
