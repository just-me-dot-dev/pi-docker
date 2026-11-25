#Requires -Version 5.1
<#
.SYNOPSIS
	Runs the pi coding agent in a hardened container (Windows wrapper).

.DESCRIPTION
	PowerShell port of bin/pi-docker for Windows with Docker Desktop or Podman.
	Wrapper options must come first. Everything after them, or after "--", is
	passed to pi unchanged. Run "pi-docker.ps1 --help" for the options.
	See README.md for usage and docs/threat-model.md for the security model.
#>

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

# Settings, overridable from the environment
$Image = if ($env:PI_DOCKER_IMAGE) { $env:PI_DOCKER_IMAGE } else { 'pi-docker:latest' }
$StateDir = if ($env:PI_DOCKER_HOME) { $env:PI_DOCKER_HOME } else { Join-Path $HOME '.pi-docker' }
$Memory = if ($env:PI_DOCKER_MEMORY) { $env:PI_DOCKER_MEMORY } else { '4g' }
$Pids = if ($env:PI_DOCKER_PIDS) { $env:PI_DOCKER_PIDS } else { '1024' }
$Cpus = $env:PI_DOCKER_CPUS

# Fixed values of the image
$ContainerHome = '/home/pi'
$ImageUid = '1000'
$ImageGid = '1000'

# OAuth callback ports of pi's providers (OpenAI 1455, Radius 1456,
# Anthropic 53692). Providers with a random port fall back to pasting the URL.
$OAuthPorts = @(1455, 1456, 53692)

function Show-Usage {
	<#
	.SYNOPSIS
		Prints the help text.
	#>
	@'
Usage: pi-docker [wrapper options] [--] [pi arguments]

Runs pi in a hardened container with the current directory mounted.
Wrapper options must come first. Everything after them, or after "--",
is passed to pi unchanged.

Wrapper options:
  --build [args]     Build the image, passing [args] to "docker build"
  --login            Publish the OAuth callback ports for this run
  --shell            Start bash in the container instead of pi
  --mount-ro PATH    Mount PATH read-only (repeatable)
  --env NAME         Pass the host variable NAME into the container (repeatable)
  --unsafe-git       Do not mount .git/hooks and .git/config read-only
  --help             Show this help

Environment:
  PI_DOCKER_IMAGE    Image tag (default: pi-docker:latest)
  PI_DOCKER_HOME     Host directory mounted as ~/.pi (default: ~/.pi-docker)
  PI_DOCKER_ENGINE   docker or podman (default: auto-detect)
  PI_DOCKER_USER     Value for --user (default: the image user)
  PI_DOCKER_MEMORY   Memory limit (default: 4g)
  PI_DOCKER_PIDS     Process limit (default: 1024)
  PI_DOCKER_CPUS     CPU limit (default: none)
'@
}

function Write-Failure([string]$Message) {
	<#
	.SYNOPSIS
		Prints an error message and exits.
	#>
	[Console]::Error.WriteLine("pi-docker: $Message")
	exit 1
}

function Get-Engine {
	<#
	.SYNOPSIS
		Returns docker or podman, honouring PI_DOCKER_ENGINE.
	#>
	if ($env:PI_DOCKER_ENGINE) { return $env:PI_DOCKER_ENGINE }
	foreach ($name in @('docker', 'podman')) {
		if (Get-Command $name -ErrorAction SilentlyContinue) { return $name }
	}
	Write-Failure 'neither docker nor podman found in PATH'
}

function Test-Podman([string]$Engine) {
	<#
	.SYNOPSIS
		Returns true when the engine is Podman, also when it hides behind "docker".
	#>
	$version = & $Engine --version 2>$null
	return ($version -match 'podman')
}

function ConvertTo-ContainerPath([string]$Path) {
	<#
	.SYNOPSIS
		Returns the container path for a host path (C:\x\y becomes /c/x/y).
	#>
	if ($Path -match '^([A-Za-z]):[\\/]*(.*)$') {
		$rest = ($Matches[2] -replace '\\', '/').TrimEnd('/')
		$drive = $Matches[1].ToLower()
		if ($rest) { return "/$drive/$rest" }
		return "/$drive"
	}
	if ($Path.StartsWith('/')) { return $Path.TrimEnd('/') }
	Write-Failure "unsupported path (network shares cannot be mounted): $Path"
}

function Format-BindMount([string]$Source, [string]$Target, [switch]$ReadOnly) {
	<#
	.SYNOPSIS
		Returns a --mount value for a bind mount.
	#>
	if ("$Source$Target".Contains(',')) { Write-Failure "paths with commas cannot be mounted: $Source" }
	$value = "type=bind,src=$Source,dst=$Target"
	if ($ReadOnly) { $value += ',readonly' }
	return $value
}

function Test-Workspace([string]$Cwd) {
	<#
	.SYNOPSIS
		Refuses working directories that would expose too much or clash.
	#>
	$homeDir = (Resolve-Path $HOME).ProviderPath.TrimEnd('\', '/')
	if ($Cwd.TrimEnd('\', '/') -eq $homeDir) {
		Write-Failure 'refusing to mount your home directory; cd into a project first'
	}
	$target = ConvertTo-ContainerPath $Cwd
	if ($target -match '^/[a-z]$' -or $target -eq '/') {
		Write-Failure 'refusing to mount a drive root; cd into a project first'
	}
	if ($target -match '^/(bin|dev|etc|lib|proc|sbin|sys|usr)(/|$)' -or $target -like "$ContainerHome*") {
		Write-Failure "the working directory clashes with a container path: $Cwd"
	}
}

# Parse wrapper options
$Engine = Get-Engine
$Login = $false
$ShellMode = $false
$UnsafeGit = $false
$ExtraArgs = New-Object System.Collections.Generic.List[string]
$i = 0
$done = $false
while (-not $done -and $i -lt $args.Count) {
	$arg = [string]$args[$i]
	switch -CaseSensitive ($arg) {
		'--build' {
			$buildArgs = @($args | Select-Object -Skip ($i + 1))
			& $Engine build --tag $Image @buildArgs (Split-Path $PSScriptRoot -Parent)
			exit $LASTEXITCODE
		}
		'--login' { $Login = $true }
		'--shell' { $ShellMode = $true }
		'--unsafe-git' { $UnsafeGit = $true }
		'--mount-ro' {
			if ($i + 1 -ge $args.Count) { Write-Failure '--mount-ro needs a path' }
			$i++
			$path = (Resolve-Path ([string]$args[$i])).ProviderPath
			$ExtraArgs.Add('--mount')
			$ExtraArgs.Add((Format-BindMount $path (ConvertTo-ContainerPath $path) -ReadOnly))
		}
		'--env' {
			if ($i + 1 -ge $args.Count) { Write-Failure '--env needs a variable name' }
			$i++
			$name = [string]$args[$i]
			# An unset variable would remove the image default, so skip it
			if (Test-Path "env:$name") {
				$ExtraArgs.Add('--env')
				$ExtraArgs.Add($name)
			}
			else {
				[Console]::Error.WriteLine("pi-docker: $name is not set on the host, not passing it")
			}
		}
		'--help' { Show-Usage; exit 0 }
		'--' { $i++; $done = $true; continue }
		default { $done = $true; continue }
	}
	if (-not $done) { $i++ }
}
$PiArgs = @($args | Select-Object -Skip $i)

# Check the image and the working directory
& $Engine image inspect $Image *> $null
if ($LASTEXITCODE -ne 0) { Write-Failure "image $Image not found; build it with: pi-docker --build" }
$Cwd = (Get-Location).ProviderPath
Test-Workspace $Cwd
$WorkDir = ConvertTo-ContainerPath $Cwd

# Prepare the persistent pi state directory (login, settings, sessions)
New-Item -ItemType Directory -Force -Path (Join-Path $StateDir 'agent') | Out-Null
$StateDir = (Resolve-Path $StateDir).ProviderPath

# Choose the user. Podman maps the host user with keep-id; Docker Desktop
# uses the image user.
$TmpfsUid = $ImageUid
$TmpfsGid = $ImageGid
if ($env:PI_DOCKER_USER) {
	$ExtraArgs.Add('--user')
	$ExtraArgs.Add($env:PI_DOCKER_USER)
	$parts = $env:PI_DOCKER_USER.Split(':')
	$TmpfsUid = $parts[0]
	if ($parts.Count -gt 1) { $TmpfsGid = $parts[1] }
}
elseif (Test-Podman $Engine) {
	$ExtraArgs.Add('--userns=keep-id')
}

# Protect git metadata that would run code on the host later
$gitDir = Join-Path $Cwd '.git'
if (-not $UnsafeGit -and (Test-Path $gitDir -PathType Container)) {
	$hooks = Join-Path $gitDir 'hooks'
	New-Item -ItemType Directory -Force -Path $hooks | Out-Null
	$ExtraArgs.Add('--mount')
	$ExtraArgs.Add((Format-BindMount $hooks "$WorkDir/.git/hooks" -ReadOnly))
	$config = Join-Path $gitDir 'config'
	if (Test-Path $config -PathType Leaf) {
		$ExtraArgs.Add('--mount')
		$ExtraArgs.Add((Format-BindMount $config "$WorkDir/.git/config" -ReadOnly))
	}
}

# Pass the host git identity, so commits are attributed correctly
if (Get-Command git -ErrorAction SilentlyContinue) {
	$gitName = git config --get user.name 2>$null
	$gitMail = git config --get user.email 2>$null
	if ($gitName) {
		$env:GIT_AUTHOR_NAME = $gitName
		$env:GIT_COMMITTER_NAME = $gitName
		$ExtraArgs.AddRange([string[]]@('--env', 'GIT_AUTHOR_NAME', '--env', 'GIT_COMMITTER_NAME'))
	}
	if ($gitMail) {
		$env:GIT_AUTHOR_EMAIL = $gitMail
		$env:GIT_COMMITTER_EMAIL = $gitMail
		$ExtraArgs.AddRange([string[]]@('--env', 'GIT_AUTHOR_EMAIL', '--env', 'GIT_COMMITTER_EMAIL'))
	}
}

# Publish the OAuth callback ports on the host loopback only
if ($Login) {
	foreach ($port in $OAuthPorts) {
		$ExtraArgs.Add('--publish')
		$ExtraArgs.Add("127.0.0.1:${port}:${port}")
	}
	$ExtraArgs.AddRange([string[]]@('--env', 'PI_OAUTH_CALLBACK_HOST=0.0.0.0'))
}

# Optional limits and interactive mode
if ($Cpus) { $ExtraArgs.AddRange([string[]]@('--cpus', $Cpus)) }
$ExtraArgs.Add('--interactive')
if (-not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected) {
	$ExtraArgs.Add('--tty')
}
if ($ShellMode) { $ExtraArgs.AddRange([string[]]@('--entrypoint', 'bash')) }

# Run the container
$runArgs = @(
	'run', '--rm',
	'--init',
	'--hostname', 'pi-docker',
	'--cap-drop', 'ALL',
	'--security-opt', 'no-new-privileges',
	'--read-only',
	'--memory', $Memory,
	'--pids-limit', $Pids,
	'--tmpfs', '/tmp:rw,exec,nosuid,nodev,size=1g',
	'--tmpfs', "${ContainerHome}:rw,exec,nosuid,nodev,size=2g,mode=0700,uid=$TmpfsUid,gid=$TmpfsGid",
	'--mount', (Format-BindMount $StateDir "$ContainerHome/.pi"),
	'--mount', (Format-BindMount $Cwd $WorkDir),
	'--workdir', $WorkDir,
	'--env', 'TERM',
	'--env', 'COLORTERM',
	'--env', 'TERM_PROGRAM',
	'--env', 'TERM_PROGRAM_VERSION'
) + $ExtraArgs.ToArray() + @($Image) + $PiArgs
& $Engine @runArgs
exit $LASTEXITCODE
