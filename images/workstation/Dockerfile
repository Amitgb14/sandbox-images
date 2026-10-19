# The workstation image: the desktop image, made into a full desktop. A sandbox
# made from it runs `sandbox-desktop`, which starts an XFCE desktop on a
# TigerVNC display served on the guest's own loopback (port 5900) — the same
# port, with the same rules, as the desktop image, so Studio's Desktop tab
# shows it unchanged: only pixels and input cross.
#
# What it adds to the desktop image: XFCE (panel, desktop, settings), the
# Thunar file manager, Pinta for painting, a text editor, an image viewer, a
# PDF viewer, an archive manager, and Flatpak, so the sandbox user installs
# more from Flathub without root.
#
# Built in CI only, on top of the desktop image (ghcr.io/<owner>/sandbox-desktop),
# which is published from sandbox-cli.
ARG BASE=ghcr.io/amitgb14/sandbox-desktop:edge
FROM ${BASE}

# --no-install-recommends keeps out what a headless VM has no use for: the
# screensaver and screen locker (a locked screen in a sandbox has no password
# to unlock it), the power manager and the sound stack (audio comes later).
RUN apt-get update && apt-get install -y --no-install-recommends \
      # The display: Xvnc is the X server and the VNC server in one, and
      # resizes through RandR, so a viewer can make the screen fit its window.
      tigervnc-standalone-server \
      tigervnc-tools \
      x11-xserver-utils \
      # Software rendering (llvmpipe), for a sandbox without a GPU.
      libgl1-mesa-dri \
      # The desktop.
      xfce4-session \
      xfwm4 \
      xfdesktop4 \
      xfce4-panel \
      xfce4-settings \
      xfce4-appfinder \
      xfce4-helpers \
      xfce4-notifyd \
      xfce4-whiskermenu-plugin \
      adwaita-icon-theme \
      elementary-xfce-icon-theme \
      xdg-user-dirs \
      xdg-utils \
      desktop-file-utils \
      at-spi2-core \
      # The file manager, with trash, thumbnails and archives.
      thunar \
      thunar-archive-plugin \
      thunar-volman \
      gvfs \
      tumbler \
      file-roller \
      unzip \
      zip \
      xz-utils \
      # Everyday tools.
      xfce4-terminal \
      mousepad \
      ristretto \
      evince \
      # Installing more, without root.
      flatpak \
      xdg-desktop-portal \
      xdg-desktop-portal-gtk \
      fonts-noto-core \
    && rm -rf /var/lib/apt/lists/*

# Pinta, the paint program, from Flathub: Debian 12 does not package it. It is
# installed system-wide at build time, so it is there with no network at all;
# the sandbox user runs it, but cannot change or remove it. What the user
# installs goes to their own installation in HOME (see sandbox-desktop).
#
# The Flathub remote description is kept in the image too, so adding the
# remote for the user needs no network either — only installing from it does.
#
# FLATPAK_GL_DRIVERS: only Mesa, which draws in software. Left to itself,
# Flatpak adds the GL drivers for whatever GPU the build machine has, and a
# guest has none. The bwrap errors this step prints are Flatpak's
# post-install triggers, which cannot make a namespace inside the build; what
# they would refresh (the icon and MIME caches) is not needed to run the app.
ARG PINTA=com.github.PintaProject.Pinta
RUN mkdir -p /usr/share/sandbox-workstation \
    && curl -fsSL -o /usr/share/sandbox-workstation/flathub.flatpakrepo \
         https://dl.flathub.org/repo/flathub.flatpakrepo \
    && flatpak remote-add --system --if-not-exists flathub \
         /usr/share/sandbox-workstation/flathub.flatpakrepo \
    && flatpak config --system --set languages en \
    && FLATPAK_GL_DRIVERS=default \
       flatpak install --system --noninteractive flathub "${PINTA}" \
    && flatpak list --system --app --columns=application | grep -qx "${PINTA}" \
    # The whole of HOME, which is where a sandbox's work is. Pinta's own
    # permissions name Pictures, Documents and the like, and count on the
    # document portal for anything else; that portal needs FUSE, which the
    # guest does not have. The VM is the boundary that matters here.
    && flatpak override --system --filesystem=home "${PINTA}"

# VirtualGL, so a sandbox given a GPU (sandbox-cli run --gpus) draws OpenGL on
# it. Its EGL back end renders on the card with no X server there, reads each
# frame back and puts it on the VNC display, so the display, its port and
# Studio's Desktop tab are the same with a GPU or without one. sandbox-desktop
# runs the session through it when the GPU answers, and draws in software
# otherwise. The driver is not here: sandboxd adds the node's GPU kit,
# NVIDIA's EGL driver among it, to a GPU sandbox's root disk. Debian 12 does
# not package VirtualGL, so it is the project's own release, checked against
# its checksum.
ARG VIRTUALGL=3.1.5
ARG VIRTUALGL_SHA256_AMD64=df3f7788ce41b182a47c0d298e5cd6d2d63579522cb41825970b7726e825485e
ARG VIRTUALGL_SHA256_ARM64=9ac238e8a18c06d84ef65444a591a7a5bb4c4ce9e8cfdd92f8a2aea35edbb5d7
RUN arch=$(dpkg --print-architecture) \
    && case $arch in \
         amd64) sum=${VIRTUALGL_SHA256_AMD64} ;; \
         arm64) sum=${VIRTUALGL_SHA256_ARM64} ;; \
         *) echo "no VirtualGL for $arch" >&2; exit 1 ;; \
       esac \
    && curl -fsSL -o /tmp/virtualgl.deb \
         "https://github.com/VirtualGL/virtualgl/releases/download/${VIRTUALGL}/virtualgl_${VIRTUALGL}_${arch}.deb" \
    && echo "${sum}  /tmp/virtualgl.deb" | sha256sum -c - \
    && apt-get update && apt-get install -y --no-install-recommends /tmp/virtualgl.deb \
    && rm -rf /tmp/virtualgl.deb /var/lib/apt/lists/*

COPY sandbox-desktop /usr/local/bin/sandbox-desktop
COPY flatpak /usr/local/bin/flatpak
COPY helpers.rc /etc/xdg/xfce4/helpers.rc
COPY xfce4-desktop.xml /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml
COPY xfwm4.xml /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml
COPY appimage.sh /etc/profile.d/sandbox-appimage.sh

RUN chmod 0755 /usr/local/bin/sandbox-desktop /usr/local/bin/flatpak \
    # The panel's own default, put where XFCE looks first: without it, the
    # first start asks "default config or one empty panel?" in a dialog.
    && cp /etc/xdg/xfce4/panel/default.xml \
          /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml \
    # No setuid or setgid programs. Every process runs as the sandbox user,
    # and nothing in this image needs to become another: Flatpak's bubblewrap
    # here uses user namespaces, not setuid. The guest mounts the image layer
    # without nosuid, so a setuid program left in it would be a way to root
    # inside the guest that no sandbox setting asked for.
    && find / -xdev -type f -perm /6000 -exec chmod ug-s {} +
