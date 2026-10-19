# The CUDA image

The base image with NVIDIA's CUDA 13.3 compiler and runtime, for a sandbox
that owns a GPU. A program built with `nvcc` in it runs on the sandbox's GPU,
and `sandbox-cuda-check` proves that it does:

```sh
sandbox-cli run --gpus 1 --image ghcr.io/amitgb14/sandbox-cuda:edge -- sandbox-cuda-check
```

```
runtime: CUDA 13.3
driver:  CUDA 13.3
device 0: <the card's name>, compute <major.minor>, <n> SMs, <n> MiB
saxpy on 16777216 floats: right, in <t> ms (<n> GB/s)
ok
```

A sandbox with a GPU needs a node that serves one: `--gpus` works only on an
endpoint with the capability `gpu`. Preparing one is
[sandbox-cli's docs/gpu.md](https://github.com/Amitgb14/sandbox-cli/blob/main/docs/gpu.md).
Everything in the base image is here too: the agents, git, Node, Python, gcc.
It is about 400 MB larger than the base image.

## What's in it

| | |
|---|---|
| `nvcc` and the CUDA headers | `cuda-nvcc-13-3`, `cuda-cudart-dev-13-3`, from NVIDIA's apt repository for Debian 12 |
| The CUDA runtime | `libcudart`, shared and static |
| `python3-venv` | For a virtual environment to `pip install` into (see below) |
| `sandbox-cuda-check` | Prints the runtime, the driver and each device, runs a kernel on device 0 and checks its result. Its source is `/usr/local/src/sandbox-cuda-check.cu` |

`PATH` has `/usr/local/cuda/bin`, and `CUDA_HOME` is `/usr/local/cuda`.

`sandbox-cuda-check` exits 0 when the kernel ran and its result is right,
1 when it did not, and 2 when there is no driver or no device: in a sandbox
made without `--gpus`, or in a container.

## The driver is not in the image

`libcuda`, `nvidia-smi` and the kernel modules must match the kernel the
sandbox boots, which is the node's, not the image's. sandboxd adds the node's
**GPU kit** to the root disk of a sandbox it gives a GPU, so in a GPU sandbox
`nvidia-smi` and `libcuda.so.1` are there, and in any other sandbox they are
not. An image that carried its own `libcuda` would be loaded in place of the
kit's and would not match; the smoke test checks there is none.

**Versions.** CUDA 13.3 is the release the kit's driver, 610.43.02, came
with. A kit with a newer driver runs it. One with an older 13.x driver runs it
too, through CUDA's minor version compatibility, but cannot JIT its PTX, so
build for the card's own architecture (`nvcc -arch=native` in the sandbox).
A 12.x driver cannot run it.

`sandbox-cuda-check` is built for every architecture CUDA 13 supports, Turing
(7.5) to Blackwell (12.0), with PTX for the newest.

## Installing more

Every process runs as the sandbox user (uid 1001), so `apt install` does not
work, and the image keeps out the rest of the toolkit (cuBLAS, cuFFT, cuDNN:
several GB). A Python workload brings its own:

```sh
python3 -m venv ~/venv && . ~/venv/bin/activate
pip install torch      # its wheels carry the CUDA libraries they need
python -c 'import torch; print(torch.cuda.get_device_name(0))'
```

The same goes for any wheel built against CUDA: the driver is the kit's, and
the libraries come with the wheel.

## Limits

- **amd64 only**, as the GPU kit is.
- **A GPU sandbox cannot be suspended, snapshotted or resized** (docs/gpu.md
  in sandbox-cli). Keep what matters in the workspace or push it somewhere.
- **No desktop.** This image has none; the
  [workstation image](workstation.md#with-a-gpu) draws its desktop on the GPU
  in a sandbox given one (it has no `nvcc`, but `pip` wheels bring CUDA).

## Checking on a real host

`tests/cuda-smoke.sh IMAGE` checks a built image in a container, without a
GPU: `nvcc` and the check are there, the image has no driver of its own,
nothing is setuid, the check says there is no driver, and the sandbox user
builds and runs a CUDA program with `nvcc`. Given `GPU_KIT=<kit>`, it also adds
the kit as sandboxd would and checks that the kit's driver is found (there is
still no card, so the check then says there is no device).

```sh
podman build -t localhost/sandbox-cuda:dev images/cuda
ENGINE=podman GPU_KIT=/var/lib/sandboxd/gpu-kit sh tests/cuda-smoke.sh localhost/sandbox-cuda:dev
```

On a node that serves a GPU, through a throwaway registry:

```sh
podman run -d --name cudareg -p 127.0.0.1:5005:5000 docker.io/library/registry:2
podman push --tls-verify=false localhost/sandbox-cuda:dev 127.0.0.1:5005/sandbox-cuda:dev
sandbox-cli run --gpus 1 --image 127.0.0.1:5005/sandbox-cuda:dev -- sh -c 'nvidia-smi -L && sandbox-cuda-check'
# expect the card, then "ok"
```

(sandboxd needs `--insecure-registry 127.0.0.1:5005` for that registry.)

Checked on 2026-10-18 on the card itself, in a container: the image with the
kit added, given the host's `/dev/nvidia0`, `/dev/nvidiactl` and
`/dev/nvidia-uvm*` (the host runs the kit's driver, 610.43.02).
`sandbox-cuda-check` found the RTX 5070 Ti (compute 12.0, 70 SMs), ran SAXPY
right at about 600 GB/s, and exited 0.

Checked the same day, Linux, without a card: the smoke test passed with the
node's kit (driver 610.43.02, which reports CUDA 13.3), and a Firecracker
sandbox made from the image, without `--gpus`, ran `nvcc` and got exit 2 from
the check. Not yet checked: a sandbox given the GPU,
which waits for the node to hand the card over (sandbox-cli's docs/gpu.md,
step 3).
