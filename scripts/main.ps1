#Requires -Modules GitHub

[CmdletBinding()]
param()

$PSStyle.OutputRendering = 'Ansi'
$repo = $env:GITHUB_REPOSITORY
$runId = $env:GITHUB_RUN_ID
gh run download $runId --repo $repo --pattern *-TestResults
$files = Get-ChildItem -Path . -Recurse -File

LogGroup 'List TestResults files' {
    $files.Name | Out-String
}
$files | Format-Table -AutoSize | Out-String

$allCases = [System.Collections.Generic.List[psobject]]::new()
foreach ($file in $files) {
    $fileName = $file.BaseName
    LogGroup $fileName {
        Get-Content -Path $file | Out-String
    }
    LogGroup "$fileName - Process" {
        $xmlDoc = [xml](Get-Content -Path $file.FullName)
        $cases = $xmlDoc.SelectNodes('//test-case') | ForEach-Object {
            [pscustomobject]@{
                Name           = $_.name
                Description    = $_.description
                Result         = $_.result
                Success        = [bool]($_.success -eq 'True')
                Time           = [float]$_.time
                Executed       = [bool]($_.executed -eq 'True')
                FailureMessage = $_.failure.message
                StackTrace     = $_.failure.'stack-trace'
            }
        }
        $cases | ForEach-Object { $allCases.Add($_) }
        $cases | Format-List | Out-String
    }
}
