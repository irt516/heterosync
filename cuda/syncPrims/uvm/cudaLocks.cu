#include "cudaLocks.h"

cudaError_t cudaLocksInit(const int maxBlocksPerKernel, const int numMutexes,
                          const int numSemaphores,
                          const bool pageAlign, /* const region_t locksReg*/
                          const int NUM_SM)
{
  cudaError_t cudaErr = cudaGetLastError();
  checkError(cudaErr, "Start cudaLocksInit");

  cudaMallocHost(&cpuLockData, sizeof(cudaLockData_t));

  if (maxBlocksPerKernel <= 0)    return cudaErrorInitializationError;
  if (numMutexes <= 0)            return cudaErrorInitializationError;
  if (numSemaphores <= 0)         return cudaErrorInitializationError;

  // initialize some of the lock data's values
  cpuLockData->maxBufferSize          = maxBlocksPerKernel;
  cpuLockData->arrayStride            = (maxBlocksPerKernel + NUM_SM) / 16 * 16;
  cpuLockData->mutexCount             = numMutexes;
  cpuLockData->semaphoreCount         = numSemaphores;

  cudaMalloc(&cpuLockData->barrierBuffers,   sizeof(unsigned int) * cpuLockData->arrayStride * 2);

  cudaMalloc(&cpuLockData->mutexBuffers,     sizeof(int) * cpuLockData->arrayStride * cpuLockData->mutexCount);
  cudaMalloc(&cpuLockData->mutexBufferHeads, sizeof(unsigned int) * cpuLockData->mutexCount);
  cudaMalloc(&cpuLockData->mutexBufferTails, sizeof(unsigned int) * cpuLockData->mutexCount);

  cudaMalloc(&cpuLockData->semaphoreBuffers, sizeof(unsigned int) * 4 * cpuLockData->semaphoreCount);

  cudaEvent_t start, end;
  cudaEventCreate(&start);
  cudaEventCreate(&end);

  cudaErr = cudaGetLastError();
  checkError(cudaErr, "Before memset");

  cudaThreadSynchronize();
  cudaEventRecord(start, 0);

  cudaMemset(cpuLockData->barrierBuffers, 0, sizeof(unsigned int) * cpuLockData->arrayStride * 2);

  cudaMemset(cpuLockData->mutexBufferHeads, 0, sizeof(unsigned int) * cpuLockData->mutexCount);
  cudaMemset(cpuLockData->mutexBufferTails, 0, sizeof(unsigned int) * cpuLockData->mutexCount);

  /*
    initialize mutexBuffers to appropriate values

    set the first location for each SM to 1 so that the ring buffer can be
    used by the first TB right away (otherwise livelock because no locations
    ever == 1)

    for all other locations initialize to -1 so TBs for these locations
    don't think it's their turn right away

    since cudaMemset sets everything in bytes, initialize all to 0 first
  */
  cudaMemset(&(cpuLockData->mutexBuffers[0]), 0,
            cpuLockData->arrayStride * cpuLockData->mutexCount * sizeof(int));
  for (int i = 0; i < (cpuLockData->arrayStride * cpuLockData->mutexCount);
       i += cpuLockData->arrayStride) {
    cudaMemset(&(cpuLockData->mutexBuffers[i]), 0x0001, 1);
    cudaMemset(&(cpuLockData->mutexBuffers[i + 1]), -1,
               (cpuLockData->arrayStride - 1) * sizeof(int));
  }

  cudaMemset(cpuLockData->semaphoreBuffers, 0, sizeof(unsigned int) * cpuLockData->semaphoreCount * 4);

  cudaThreadSynchronize();
  cudaEventRecord(end, 0);
  cudaEventSynchronize(end);
  float elapsedTime = 0.0f;
  cudaEventElapsedTime(&elapsedTime, start, end);
  fprintf(stdout, "\tmemcpy H->D 1 elapsed time: %f ms\n", elapsedTime);
  fflush(stdout);

  cudaEventDestroy(start);
  cudaEventDestroy(end);

  return cudaSuccess;
}

cudaError_t cudaLocksDestroy()
{
  if (cpuLockData == NULL) { return cudaErrorInitializationError; }
  cudaFree(cpuLockData->mutexBuffers);
  cudaFree(cpuLockData->mutexBufferHeads);
  cudaFree(cpuLockData->mutexBufferTails);

  cudaFree(cpuLockData->semaphoreBuffers);

  cudaFreeHost(cpuLockData);

  return cudaSuccess;
}
