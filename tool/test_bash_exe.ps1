# Runs a build of BaoCode Bash (bash.exe, github.com/baocode-dev/bash-exe)
# as the app's agents do, `bash -c COMMAND`: its built-in tools, both kinds
# of path, Windows programs, exit statuses, stdin.
#
#   pwsh tool/test_bash_exe.ps1 <bash.exe>
#
# CI runs it where it builds it (.github/workflows/bash-exe.yml); it runs on
# a Windows machine with the build copied there as well.
param([Parameter(Mandatory)] [string] $Bash)
$ErrorActionPreference = 'Stop'

$Bash = (Resolve-Path -LiteralPath $Bash).Path
$work = Join-Path ([IO.Path]::GetTempPath()) "bash-exe-test-$PID"
New-Item -ItemType Directory -Path $work | Out-Null
Set-Content -LiteralPath (Join-Path $work 'a.txt') -Value "one`nfoo bar`nthree" -NoNewline
Set-Content -LiteralPath (Join-Path $work 'b.json') -Value '{"name":"bao","tags":["x","y"]}'
$failed = 0

# `bash ARGS…`, in [work], [stdin] given; its status, stdout and stderr.
function Invoke-Bash([string[]] $Arguments, [string] $Stdin = '', [int] $Seconds = 60) {
  $info = New-Object Diagnostics.ProcessStartInfo $Bash
  foreach ($argument in $Arguments) { $info.ArgumentList.Add($argument) }
  $info.WorkingDirectory = $work
  $info.RedirectStandardInput = $true
  $info.RedirectStandardOutput = $true
  $info.RedirectStandardError = $true
  $info.UseShellExecute = $false
  $process = [Diagnostics.Process]::Start($info)
  $out = $process.StandardOutput.ReadToEndAsync()
  $err = $process.StandardError.ReadToEndAsync()
  $process.StandardInput.Write($Stdin)
  $process.StandardInput.Close()
  if (-not $process.WaitForExit($Seconds * 1000)) {
    $process.Kill($true)
    return @{ Status = -1; Out = ''; Err = "still running after ${Seconds}s" }
  }
  $process.WaitForExit()
  @{ Status = $process.ExitCode; Out = $out.Result.Replace("`r`n", "`n"); Err = $err.Result }
}

# `bash -c COMMAND` has to exit with [Status] and print what [Expected]
# matches.
function Test-Bash([string] $Name, [string] $Command, [string] $Expected, [int] $Status = 0, [string] $Stdin = '') {
  $ran = Invoke-Bash @('-c', $Command) $Stdin
  if ($ran.Status -eq $Status -and $ran.Out -match $Expected) {
    Write-Host "ok   $Name"
    return
  }
  Write-Host "FAIL $Name"
  Write-Host "     command:  $Command"
  Write-Host "     status:   $($ran.Status) (expected $Status)"
  Write-Host "     stdout:   $($ran.Out)"
  Write-Host "     stderr:   $($ran.Err)"
  Write-Host "     expected: /$Expected/"
  $script:failed++
}

try {
  $version = Invoke-Bash @('--version')
  Write-Host $version.Out
  if ($version.Status -ne 0 -or $version.Out -notmatch '(?m)^GNU bash, version 5\.' -or $version.Out -notmatch 'BaoCode Bash \d') {
    Write-Host "FAIL --version: $($version.Status) $($version.Err)"
    $failed++
  }

  Test-Bash 'echo' 'echo hello' '^hello\n$'
  Test-Bash 'no arguments' 'echo "[$1]"' '^\[\]\n$'
  $named = Invoke-Bash @('-c', 'echo "$0|$1|$2"', 'name', 'a b', "it's")
  if ($named.Out -ne "name|a b|it's`n") { Write-Host "FAIL -c with arguments: $($named.Out)"; $failed++ } else { Write-Host 'ok   -c with arguments' }
  Test-Bash 'exit status' 'exit 7' '^$' 7
  Test-Bash 'set -e' 'set -e; false; echo after' '^$' 1
  Test-Bash 'command not found' 'no-such-command-here' '^$' 127
  Test-Bash 'stdin' 'read line; echo "got:$line"' '^got:piped\n$' 0 "piped`n"
  Test-Bash 'arithmetic, [[ ]], arrays' 'a=(x y z); [[ ${#a[@]} -eq 3 ]] && echo $(( 6 * 7 ))' '^42\n$'

  Test-Bash 'rg' 'rg -n foo a.txt' '^2:foo bar\n$'
  Test-Bash 'grep' 'grep -c o a.txt' '^2\n$'
  Test-Bash 'sed' 'sed -n "s/foo/baz/p" a.txt' '^baz bar\n$'
  Test-Bash 'awk' 'awk "NR==2 {print \$2}" a.txt' '^bar\n$'
  Test-Bash 'jq' 'jq -r ".tags | join(\",\")" b.json' '^x,y\n$'
  Test-Bash 'find' 'find . -name "*.json"' '^\./b\.json\n$'
  Test-Bash 'pipes, sort, uniq, wc' 'printf "b\na\nb\n" | sort | uniq | wc -l' '^\s*2\n$'
  Test-Bash 'xargs' 'echo a.txt | xargs cat | head -1' '^one\n$'
  Test-Bash 'tar' 'tar -cf t.tar a.txt && tar -tf t.tar' '^a\.txt\n$'
  Test-Bash 'built in' 'type -t rg sed' '^builtin\nbuiltin\n$'

  $windows = $env:SystemRoot.Replace('\', '/')
  $drive = $windows.Substring(0, 1).ToLower()
  $msys = "/$drive" + $windows.Substring(2)
  Test-Bash 'C:\ path' "ls '$($env:SystemRoot)\System32\cmd.exe'" 'cmd\.exe'
  Test-Bash 'C:/ path' "ls '$windows/System32/cmd.exe'" 'cmd\.exe'
  Test-Bash '/c/ path' "ls '$msys/System32/cmd.exe'" 'cmd\.exe'
  Test-Bash '/mnt/c/ path' "test -f '/mnt$msys/System32/cmd.exe' && echo yes" '^yes\n$'
  Test-Bash 'cd /c/' "cd '$msys' && ls -d System32" '^System32\n$'

  Test-Bash 'pwd, in Windows spelling' "cd '$msys' && pwd -P" '(?i)^[a-z]:[\\/]windows\n$'

  # As bao_agent's Bash tool runs a command (Shell.arguments in
  # packages/bao_agent/lib/src/util/processes.dart): where it ended up is
  # written to a file, for the next.
  $cwdFile = Join-Path $work 'cwd.txt'
  $script = 'eval "$1" < /dev/null; __bao_status=$?; pwd -P >| "$2" 2>/dev/null; exit $__bao_status'
  $agent = Invoke-Bash @('-c', $script, 'bash', "cd '$msys' && echo moved && (exit 3)", $cwdFile)
  $ended = if (Test-Path -LiteralPath $cwdFile) { (Get-Content -LiteralPath $cwdFile -Raw).Trim() } else { '' }
  if ($agent.Status -ne 3 -or $agent.Out -ne "moved`n" -or $ended -notmatch '(?i)^[a-z]:[\\/]windows$') {
    Write-Host "FAIL as the agent runs it: $($agent.Status) '$($agent.Out)' '$ended' $($agent.Err)"
    $failed++
  } else {
    Write-Host "ok   as the agent runs it ($ended)"
  }

  Test-Bash 'Windows programs' 'cmd.exe /c echo from-cmd' '^from-cmd\s*$'
  Test-Bash 'a program on PATH' 'git --version' '^git version'
  Test-Bash 'Windows find, as written for it' 'find /c "foo" a.txt' '(?i)a\.txt: 1'
  Test-Bash 'a redirection to a file' 'echo written > out.txt && cat out.txt' '^written\n$'

  # A job left in the background is not waited for, as bash's are not.
  $started = Get-Date
  $background = Invoke-Bash @('-c', 'sleep 30 & echo started') '' 20
  $took = ((Get-Date) - $started).TotalSeconds
  if ($background.Out -ne "started`n" -or $took -gt 15) {
    Write-Host "FAIL background job: '$($background.Out)' after $([int]$took)s $($background.Err)"
    $failed++
  } else {
    Write-Host 'ok   background job'
  }
} finally {
  Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failed -gt 0) {
  Write-Host "$failed failed"
  exit 1
}
Write-Host 'All passed'
