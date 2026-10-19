# The CUDA image: the base image with NVIDIA's CUDA compiler and runtime, for
# sandboxes given a GPU (sandbox-cli run --gpus 1). `sandbox-cuda-check` in it
# runs a kernel on the GPU and checks the result.
#
# What it does not have: the driver. libcuda, nvidia-smi and the kernel
# modules must match the node's guest kernel exactly, so they are the node's:
# sandboxd adds its GPU kit to the sandbox's root disk (sandbox-cli,
# docs/gpu.md). An image that carried its own libcuda would shadow the kit's.
#
# CUDA 13.3, the version the kit's driver (610.43.02) was released with. A
# driver from any later release runs it; an earlier 13.x driver runs it too,
# through CUDA's minor version compatibility, but cannot JIT its PTX.
#
# amd64 only: the GPU kit is. Built in CI only, on top of the base image
# (ghcr.io/<owner>/sandbox-base), which is published from sandbox-cli.
ARG BASE=ghcr.io/amitgb14/sandbox-base:edge
FROM ${BASE}

ARG CUDA=13-3
ARG KEYRING_SHA256=e7f219eab6fe4819cdb5c15b98233dc3420302d9c00883219cd3d896857cf48d

# NVIDIA's apt repository for Debian 12, signed by the key in cuda-keyring,
# whose package is checked against a pinned checksum.
#
# Only the compiler and the runtime: cuda-nvcc and cuda-cudart-dev. Not the
# whole toolkit, whose libraries (cuBLAS, cuFFT, ...) are several GB that a
# Python workload brings again in its own wheels (pip install torch), so
# python3-venv is here instead. Not cuda-drivers, which is the driver the kit
# provides.
RUN curl -fsSL -o /tmp/cuda-keyring.deb \
      https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64/cuda-keyring_1.1-1_all.deb \
    && echo "${KEYRING_SHA256}  /tmp/cuda-keyring.deb" | sha256sum -c - \
    && dpkg -i /tmp/cuda-keyring.deb \
    && rm /tmp/cuda-keyring.deb \
    && apt-get update && apt-get install -y --no-install-recommends \
      cuda-nvcc-${CUDA} \
      cuda-cudart-dev-${CUDA} \
      # For a virtual environment to pip install into, as the sandbox user.
      python3-venv \
    && rm -rf /var/lib/apt/lists/* \
    # The driver's stub (libcuda.so for linking against) stays where nvcc
    # finds it, and out of the loader's paths, so a program never loads it
    # in place of the kit's real libcuda.so.1.
    && ! ldconfig -p | grep -q 'libcuda\.so'

ENV PATH=/usr/local/cuda/bin:${PATH} \
    CUDA_HOME=/usr/local/cuda

# The check, built here with the image's own nvcc: native code for every
# architecture CUDA 13 supports (Turing to Blackwell), and PTX for the newest,
# so a later card JITs it.
COPY sandbox-cuda-check.cu /usr/local/src/sandbox-cuda-check.cu
RUN nvcc -O2 -arch=all-major -o /usr/local/bin/sandbox-cuda-check \
      /usr/local/src/sandbox-cuda-check.cu \
    # No setuid or setgid programs, as in the base image.
    && find / -xdev -type f -perm /6000 -exec chmod ug-s {} +
