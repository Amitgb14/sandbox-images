#!/bin/sh
# cuda-smoke.sh IMAGE: checks a built CUDA image in a container — the compiler
# and the check are there, a venv can be made, the image carries no driver of its own, nothing is
# setuid, and the sandbox user can build a CUDA program with nvcc.
#
# What it cannot check here: a kernel on a GPU, which needs a sandbox given
# one. See docs/cuda.md, "Checking on a real host".
#
#   ENGINE   docker or podman (default: whichever is installed, docker first)
#   GPU_KIT  a GPU kit (sandbox-cli's scripts/gpu-kit.sh): also check that the
#            image finds the kit's driver once the kit is added, as sandboxd
#            adds it to a GPU sandbox's root disk
set -eu

image=${1:?usage: cuda-smoke.sh IMAGE}
engine=${ENGINE:-$(command -v docker >/dev/null 2>&1 && echo docker || echo podman)}
work=$(mktemp -d)

fail() { echo "smoke: FAIL: $*" >&2; exit 1; }
cleanup() {
  [ -z "${kitimage:-}" ] || "$engine" rmi -f "$kitimage" >/dev/null 2>&1 || true
  rm -rf "$work"
}
trap cleanup EXIT

echo "smoke: programs"
"$engine" run --rm --user 1001:1001 "$image" sh -c '
  for p in nvcc sandbox-cuda-check gcc; do
    command -v "$p" >/dev/null || { echo "missing: $p"; exit 1; }
  done
  nvcc --version | grep -q "release 13\." || { echo "nvcc is not CUDA 13"; exit 1; }
  [ "$CUDA_HOME" = /usr/local/cuda ] || { echo "CUDA_HOME is $CUDA_HOME"; exit 1; }
  python3 -m venv /tmp/venv && /tmp/venv/bin/pip --version >/dev/null || { echo "no venv to pip install into"; exit 1; }
' || fail "a program is missing"

echo "smoke: no driver in the image"
# The kit brings it; one here would be loaded in its place, and would not
# match the node's kernel modules.
"$engine" run --rm "$image" sh -c '
  found=$(find / -xdev \( -name "libcuda.so*" -o -name "libnvidia-ml.so*" -o -name nvidia-smi \) \
    -not -path "*/stubs/*" 2>/dev/null)
  [ -z "$found" ] || { echo "$found"; exit 1; }
  if ldconfig -p | grep -q "libcuda\.so"; then echo "the loader knows a libcuda"; exit 1; fi
' || fail "the image has a driver of its own"

echo "smoke: no setuid or setgid files"
n=$("$engine" run --rm "$image" sh -c 'find / -xdev -type f -perm /6000 2>/dev/null | wc -l')
[ "$n" -eq 0 ] || fail "$n setuid or setgid files"

echo "smoke: without a GPU, the check says so"
set +e
out=$("$engine" run --rm --user 1001:1001 "$image" sandbox-cuda-check 2>&1); rc=$?
set -e
[ "$rc" -eq 2 ] || { echo "$out" >&2; fail "sandbox-cuda-check exited $rc without a driver, want 2"; }
echo "$out" | grep -q "^runtime: CUDA 13\." || { echo "$out" >&2; fail "no runtime version"; }
echo "$out" | grep -q "no CUDA driver" || { echo "$out" >&2; fail "it does not say there is no driver"; }

echo "smoke: the sandbox user builds a CUDA program"
"$engine" run --rm --user 1001:1001 "$image" sh -c '
  cd /tmp && cat > add.cu <<"CU"
#include <cstdio>
__global__ void add(int *x) { x[threadIdx.x] += threadIdx.x; }
int main() {
  int *x;
  cudaError_t err = cudaMallocManaged(&x, 32 * sizeof(int));
  printf("%s\n", cudaGetErrorName(err));
  return 0;
}
CU
  nvcc -arch=all-major -o add add.cu && ./add
' >"$work/add.out" 2>&1 || { cat "$work/add.out" >&2; fail "nvcc could not build a program"; }
# It runs, and finds no driver, as there is none.
grep -qx "cudaErrorInsufficientDriver" "$work/add.out" || { cat "$work/add.out" >&2; fail "the program did not run as expected"; }

if [ -n "${GPU_KIT:-}" ]; then
  echo "smoke: with the GPU kit, the driver is found"
  [ -f "$GPU_KIT/kit.json" ] || fail "$GPU_KIT is not a GPU kit (no kit.json)"
  # Laid out as sandboxd adds it, through the image's own symlinks: the kit's
  # lib/firmware is the image's /usr/lib/firmware, Debian's /lib being a link.
  mkdir -p "$work/kit/rootfs"
  cp -a "$GPU_KIT/rootfs/." "$work/kit/rootfs/"
  if [ -d "$work/kit/rootfs/lib" ]; then
    mkdir -p "$work/kit/rootfs/usr/lib"
    cp -a "$work/kit/rootfs/lib/." "$work/kit/rootfs/usr/lib/"
    rm -rf "$work/kit/rootfs/lib"
  fi
  printf 'FROM %s\nCOPY rootfs/ /\n' "$image" >"$work/kit/Containerfile"
  kitimage=sandbox-cuda-smoke-kit:$$
  "$engine" build -q -t "$kitimage" -f "$work/kit/Containerfile" "$work/kit" >/dev/null
  set +e
  out=$("$engine" run --rm --user 1001:1001 "$kitimage" sandbox-cuda-check 2>&1); rc=$?
  set -e
  echo "$out" | grep -q "^driver:  CUDA " || { echo "$out" >&2; fail "the kit's driver is not found"; }
  # There is the driver, but no card in a container.
  [ "$rc" -eq 2 ] || { echo "$out" >&2; fail "sandbox-cuda-check exited $rc with the kit, want 2"; }
  echo "$out" | grep "^driver:"
fi

echo "smoke: ok"
