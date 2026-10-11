# The guest has no /dev/fuse, so an AppImage cannot mount itself: it unpacks to
# a temporary directory and runs from there instead.
export APPIMAGE_EXTRACT_AND_RUN=1
