$ErrorActionPreference = 'Stop'

# Default test-signing certificate for local pujjoteen builds: the
# "CN=audiodriver test signing" certificate created by the earlier bring-up
# project. The Chromebook already trusts it, so packages signed with it
# install without importing another certificate. Set SIGN_CERT_SHA1 to use
# a different code-signing certificate instead.
$subject = 'CN=audiodriver test signing'
$now = Get-Date
$cert = Get-ChildItem Cert:\CurrentUser\My, Cert:\LocalMachine\My -ErrorAction SilentlyContinue |
    Where-Object { $_.Subject -eq $subject -and $_.HasPrivateKey -and
                   $now -ge $_.NotBefore -and $now -le $_.NotAfter } |
    Sort-Object NotAfter |
    Select-Object -Last 1

if (-not $cert) { exit 1 }
Write-Output $cert.Thumbprint
