/** Download and verify the pinned macOS FRP client used by managed mobile access. */
export function prepareRelayClient(
  directory: string,
  architecture: 'arm64' | 'x64',
  environment?: NodeJS.ProcessEnv,
): Promise<string>
