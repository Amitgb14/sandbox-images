// sandbox-cuda-check: proves a sandbox can run CUDA on its GPU. It prints the
// driver, the runtime and each device, then runs a kernel on device 0 and
// checks its result on the host.
//
// Exit status: 0 the kernel ran and its result is right; 1 it ran wrong or
// failed; 2 there is no driver or no device (a sandbox without --gpus, or a
// container), which is not a fault of the image.
#include <cstdio>
#include <cstdlib>
#include <cuda_runtime.h>

__global__ void saxpy(int n, float a, const float *x, float *y) {
  int i = blockIdx.x * blockDim.x + threadIdx.x;
  if (i < n) y[i] = a * x[i] + y[i];
}

static int fail(const char *what, cudaError_t err) {
  fprintf(stderr, "sandbox-cuda-check: %s: %s (%s)\n", what, cudaGetErrorString(err), cudaGetErrorName(err));
  return 1;
}

int main() {
  // In order with stderr, when both go to one log.
  setvbuf(stdout, NULL, _IOLBF, 0);
  int runtime = 0, driver = 0;
  cudaRuntimeGetVersion(&runtime);
  cudaDriverGetVersion(&driver);
  printf("runtime: CUDA %d.%d\n", runtime / 1000, runtime % 1000 / 10);
  if (driver == 0) {
    fprintf(stderr, "sandbox-cuda-check: no CUDA driver: libcuda.so.1 is not here; a sandbox gets it from the node's GPU kit with --gpus\n");
    return 2;
  }
  printf("driver:  CUDA %d.%d\n", driver / 1000, driver % 1000 / 10);

  int count = 0;
  cudaError_t err = cudaGetDeviceCount(&count);
  if (err == cudaErrorNoDevice || err == cudaErrorInsufficientDriver || (err == cudaSuccess && count == 0)) {
    fprintf(stderr, "sandbox-cuda-check: no CUDA device: %s\n", err == cudaSuccess ? "none found" : cudaGetErrorString(err));
    return 2;
  }
  if (err != cudaSuccess) return fail("counting devices", err);
  for (int d = 0; d < count; d++) {
    cudaDeviceProp p;
    if ((err = cudaGetDeviceProperties(&p, d)) != cudaSuccess) return fail("reading a device", err);
    printf("device %d: %s, compute %d.%d, %d SMs, %zu MiB\n", d, p.name, p.major, p.minor,
           p.multiProcessorCount, p.totalGlobalMem >> 20);
  }

  const int n = 1 << 24;
  const size_t bytes = n * sizeof(float);
  float *x = (float *)malloc(bytes), *y = (float *)malloc(bytes), *dx, *dy;
  for (int i = 0; i < n; i++) { x[i] = 1.0f; y[i] = 2.0f; }
  if ((err = cudaMalloc(&dx, bytes)) != cudaSuccess) return fail("allocating on the device", err);
  if ((err = cudaMalloc(&dy, bytes)) != cudaSuccess) return fail("allocating on the device", err);
  cudaMemcpy(dx, x, bytes, cudaMemcpyHostToDevice);
  cudaMemcpy(dy, y, bytes, cudaMemcpyHostToDevice);

  cudaEvent_t start, stop;
  cudaEventCreate(&start);
  cudaEventCreate(&stop);
  cudaEventRecord(start);
  saxpy<<<(n + 255) / 256, 256>>>(n, 3.0f, dx, dy);
  cudaEventRecord(stop);
  if ((err = cudaGetLastError()) != cudaSuccess) return fail("starting the kernel", err);
  if ((err = cudaEventSynchronize(stop)) != cudaSuccess) return fail("running the kernel", err);
  float ms = 0;
  cudaEventElapsedTime(&ms, start, stop);
  if ((err = cudaMemcpy(y, dy, bytes, cudaMemcpyDeviceToHost)) != cudaSuccess) return fail("copying back", err);

  for (int i = 0; i < n; i++) {
    if (y[i] != 5.0f) {
      fprintf(stderr, "sandbox-cuda-check: FAIL: y[%d] = %f, want 5\n", i, y[i]);
      return 1;
    }
  }
  printf("saxpy on %d floats: right, in %.2f ms (%.0f GB/s)\n", n, ms, 3.0 * bytes / ms / 1e6);
  printf("ok\n");
  return 0;
}
