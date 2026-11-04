# Runs a Windows build of the remote server (tool/build_remote_server.dart
# --only windows-<arch>) on this machine, as tool/test_remote_server_macos.sh
# runs the macOS ones: it has to start, answer `initialize` as the app
# expects, and list a folder.
#
#   pwsh tool/test_remote_server_windows.ps1 <binary> <arch>
#
# CI runs it where it builds the server (.github/workflows/remote.yml).
param(
  [Parameter(Mandatory)] [string] $Binary,
  [Parameter(Mandatory)] [ValidateSet('x64', 'arm64')] [string] $Arch
)
$ErrorActionPreference = 'Stop'

$data = Join-Path ([IO.Path]::GetTempPath()) "baocode-server-test-$PID"
# As the app puts it on a host: an .exe.
$exe = Join-Path ([IO.Path]::GetTempPath()) "baocode-server-test-$PID.exe"
Copy-Item -LiteralPath $Binary -Destination $exe
try {
  $info = New-Object Diagnostics.ProcessStartInfo $exe
  # Windows PowerShell's .NET has no ArgumentList.
  $info.Arguments = '--data "' + $data + '"'
  $info.RedirectStandardInput = $true
  $info.RedirectStandardOutput = $true
  $info.RedirectStandardError = $true
  $info.UseShellExecute = $false
  $process = [Diagnostics.Process]::Start($info)
  $errors = $process.StandardError.ReadToEndAsync()
  $folder = $env:SystemRoot
  $list = @{ jsonrpc = '2.0'; id = 2; method = 'fs/list'; params = @{ root = $folder; path = $folder } } |
    ConvertTo-Json -Compress
  $process.StandardInput.WriteLine('{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}')
  $process.StandardInput.WriteLine($list)
  $process.StandardInput.Flush()

  $answers = @{}
  $deadline = (Get-Date).AddSeconds(30)
  while ($answers.Count -lt 2 -and (Get-Date) -lt $deadline) {
    $line = $process.StandardOutput.ReadLineAsync()
    if (-not $line.Wait(30000) -or $null -eq $line.Result) { break }
    if ($line.Result.StartsWith('{')) {
      $message = $line.Result | ConvertFrom-Json
      if ($null -ne $message.id) { $answers[[int]$message.id] = $message }
    }
  }
  $process.StandardInput.Close()
  if (-not $process.WaitForExit(10000)) { $process.Kill() }

  $hello = $answers[1].result
  if (-not $hello) { throw "No answer to initialize: $($answers[1] | ConvertTo-Json -Compress)`n$($errors.Result)" }
  if ($hello.platform.os -ne 'win' -or $hello.platform.arch -ne $Arch) {
    throw "Says it runs on $($hello.platform | ConvertTo-Json -Compress), not win $Arch"
  }
  $listing = $answers[2].result
  if (-not $listing -or $listing.Count -eq 0) {
    throw "No listing of ${folder}: $($answers[2] | ConvertTo-Json -Compress)"
  }
  Write-Output "protocol $($hello.protocol), win $Arch, home $($hello.home), $($listing.Count) entries in $folder"
} finally {
  Remove-Item -LiteralPath $exe -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $data -Recurse -Force -ErrorAction SilentlyContinue
}
