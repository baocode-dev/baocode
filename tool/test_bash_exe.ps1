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
  $info.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
  $info.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
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
  Test-Bash '/tmp, redirected to and read' 'echo kept > /tmp/bash-exe-test-$$ && cat /tmp/bash-exe-test-$$ && rm /tmp/bash-exe-test-$$' '^kept\n$'

  # A Windows program gets its arguments as Git Bash passes them: POSIX
  # paths in Windows spelling, `//x` as `/x`, switches as they are.
  Test-Bash 'a doubled slash, to a Windows program' 'cmd //c echo from-cmd' '^from-cmd\s*$'
  Test-Bash 'POSIX paths, to a Windows program' "cmd //c echo '$msys' --file='$msys'" '(?i)^[a-z]:/windows --file=[a-z]:/windows\s*$'
  Test-Bash '/tmp, to a Windows program' 'cmd //c echo /tmp/x' '(?i)^[a-z]:/\S+/x\s*$'
  Test-Bash 'switches, to a Windows program' 'cmd /c echo /s /nologo' '^/s /nologo\s*$'
  Test-Bash 'MSYS_NO_PATHCONV' "MSYS_NO_PATHCONV=1 cmd /c echo '$msys'" '(?i)^/[a-z]/windows\s*$'

  # What programs write reaches the agent as UTF-8.
  Test-Bash 'a console program writes UTF-8' 'cmd //c echo 中文' '^中文\s*$'
  Test-Bash 'PowerShell writes UTF-8' "powershell -NoProfile -Command 'Write-Output 中文'" '^中文\s*$'
  Test-Bash 'Python in UTF-8 mode' 'echo "$PYTHONUTF8"' '^1\n$'
  Test-Bash 'SHELL' '"$SHELL" -c "echo nested"' '^nested\s*$'
  # `bash`, `sh` are this bash (with its tools), not WSL's or Git's.
  Test-Bash 'bash script.sh' 'echo "type -t rg" > nested.sh && bash nested.sh && sh -c "type -t rg"' '^builtin\nbuiltin\n$'
  Test-Bash 'a script is its own BASH_SOURCE' 'echo ''[[ "${BASH_SOURCE[0]}" == "$0" ]] && echo main'' > main.sh && bash main.sh' '^main\n$'
  Test-Bash 'BASH, the path of this bash' 'case "$BASH" in *[/\\]bash.exe) echo path ;; esac' '^path\n$'

  # What scripts written for Git Bash test for and use.
  Test-Bash 'uname and OSTYPE, as Git Bash' 'uname -s; echo "$OSTYPE"' '^MINGW64_NT-\S+\nmsys\n$'
  Test-Bash 'process substitution' 'diff <(printf "a\n") <(printf "b\n"); cat <(echo sub)' '^1c1\n< a\n---\n> b\nsub\n$'
  Test-Bash '/dev/stdin and /dev/stderr' 'echo in | cat /dev/stdin; echo teed | tee /dev/stderr 2>&1 >/dev/null' '^in\nteed\n$'
  Test-Bash '/dev/urandom and /dev/zero' 'head -c 16 /dev/urandom | wc -c; tr -dc a-z < /dev/urandom | head -c 5 | wc -c; head -c 3 /dev/zero | od -An -tx1' '^\s*16\n\s*5\n\s*00 00 00\n$'
  Test-Bash 'env and xargs find .exe programs' 'env A=1 git --version; echo --version | xargs git' '^git version.*\ngit version'
  Test-Bash 'sed, on input not in UTF-8' 'printf "caf\xe9 x\n" | sed s/x/y/ | od -An -tx1' '^\s*63 61 66 e9 20 79 0a\n$'
  Test-Bash 'a #! line' 'printf "#!/usr/bin/env node\nconsole.log(process.argv[2])\n" > shebang.js && ./shebang.js arg' '^arg\n$'
  Test-Bash 'chmod' 'touch ro.txt && chmod 444 ro.txt && [ ! -w ro.txt ] && chmod u+w ro.txt && [ -w ro.txt ] && echo ok' '^ok\n$'

  # A script run as `bash script.sh` has the tools ahead of PATH, as `-c`
  # has (System32's `sort`, Git's `xargs` came first).
  [IO.File]::WriteAllText((Join-Path $work 'tools.sh'), "printf 'b\na\n' | sort | tr '\n' ' '; printf 'x\n' | xargs -I{} echo `"got {}`"; exit 4`n")
  $ran = Invoke-Bash @('tools.sh')
  if ($ran.Status -ne 4 -or $ran.Out -ne "a b got x`n") {
    Write-Host "FAIL a script's tools: $($ran.Status) '$($ran.Out)' $($ran.Err)"
    $failed++
  } else {
    Write-Host "ok   a script's tools"
  }

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
