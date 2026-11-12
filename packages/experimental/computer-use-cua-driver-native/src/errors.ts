/** Structured failures owned by the supervised native worker adapter. */
import { HarnessError } from '@deepseek-ai/dsh-error'

const failures = {
  configuration: ['NATIVE_WORKER_CONFIGURATION_INVALID', 'Private native worker cannot replace custom CUA_DRIVER_* process configuration; use the in-process runtime.'],
  startup: ['NATIVE_WORKER_STARTUP_FAILED', 'Native computer-use worker startup failed. Check its executable and host identity.'],
  call: ['NATIVE_WORKER_CALL_FAILED', 'Native computer-use worker call failed; input may already have been delivered. Inspect fresh desktop state before retrying.'],
  shutdown: ['NATIVE_WORKER_SHUTDOWN_FAILED', 'Native computer-use worker shutdown failed. Restart the Host before mounting another runtime.'],
} as const

/** Failure with an operation-specific code and retained native cause. */
export class NativeWorkerError extends HarnessError {
  /**
   * @param operation - Worker operation that could not complete.
   * @param cause - Native failure retained for host diagnostics.
   */
  constructor(operation: keyof typeof failures, cause?: unknown) {
    const [code, message] = failures[operation]
    super(message, code, { cause })
  }
}
