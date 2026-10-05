/** PowerShell child setup for DACL probes without administrator privilege overrides. */
export const DACL_ONLY_TOKEN = String.raw`
Add-Type -Namespace DshTest -Name DaclToken -MemberDefinition @'
[DllImport("kernel32.dll")]
public static extern IntPtr GetCurrentProcess();
[DllImport("kernel32.dll", SetLastError=true)]
public static extern bool CloseHandle(IntPtr handle);
[DllImport("advapi32.dll", SetLastError=true)]
public static extern bool OpenProcessToken(IntPtr process, uint access, out IntPtr token);
[DllImport("advapi32.dll", SetLastError=true)]
public static extern bool AdjustTokenPrivileges(IntPtr token, bool disableAll, IntPtr state, uint length, IntPtr previous, IntPtr returned);
'@ | Out-Null
$testToken = [IntPtr]::Zero
if (-not [DshTest.DaclToken]::OpenProcessToken([DshTest.DaclToken]::GetCurrentProcess(), 0x20, [ref]$testToken)) { throw 'OpenProcessToken failed' }
try {
  if (-not [DshTest.DaclToken]::AdjustTokenPrivileges($testToken, $true, [IntPtr]::Zero, 0, [IntPtr]::Zero, [IntPtr]::Zero)) { throw 'AdjustTokenPrivileges failed' }
} finally { [void][DshTest.DaclToken]::CloseHandle($testToken) }
`
