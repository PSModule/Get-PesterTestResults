#Requires -Modules GitHub

[CmdletBinding()]
param()

$PSStyle.OutputRendering = 'Ansi'
$repo = $env:GITHUB_REPOSITORY
$runId = $env:GITHUB_RUN_ID
$testResultsFolder = New-Item -Path . -ItemType Directory -Name 'TestResults' -Force
gh run download $runId --repo $repo --pattern *-TestResults --dir TestResults
$files = Get-ChildItem -Path $testResultsFolder -Recurse -File -Filter *.json

LogGroup 'List TestResults files' {
    $files.Name | Out-String
}

# $allCases = [System.Collections.Generic.List[psobject]]::new()
# $testResults = [System.Collections.Generic.List[psobject]]::new()
# foreach ($file in $files) {
#     $fileName = $file.BaseName
#     $xmlDoc = [xml](Get-Content -Path $file.FullName)
#     LogGroup $fileName {
#         Get-Content -Path $file | Out-String
#     }
#     LogGroup "$fileName - Tests" {
#         $cases = $xmlDoc.SelectNodes('//test-case') | ForEach-Object {
#             [pscustomobject]@{
#                 Name           = $_.name
#                 Description    = $_.description
#                 Result         = $_.result
#                 Success        = [bool]($_.success -eq 'True')
#                 Time           = [float]$_.time
#                 Executed       = [bool]($_.executed -eq 'True')
#                 FailureMessage = $_.failure.message
#                 StackTrace     = $_.failure.'stack-trace'
#             }
#         }
#         $cases | ForEach-Object { $allCases.Add($_) }
#         $cases | Format-Table | Out-String
#     }
#     LogGroup "$fileName - Summary" {
#         $testResultXml = $xmlDoc.'test-results'
#         $testResult = [pscustomobject]@{
#             Name         = $testResultXml.name
#             Total        = $testResultXml.total
#             Errors       = $testResultXml.errors
#             Failures     = $testResultXml.failures
#             NotRun       = $testResultXml.'not-run'
#             Inconclusive = $testResultXml.inconclusive
#             Ignored      = $testResultXml.ignored
#             Skipped      = $testResultXml.skipped
#             Invalid      = $testResultXml.invalid
#             Date         = $testResultXml.date
#             Time         = $testResultXml.time
#         }
#         $testResults.Add($testResult)
#         $testResult | Format-Table | Out-String
#     }
# }

# $total = [pscustomobject]@{
#     Tests        = $allCases.Count
#     Failures     = [int]([math]::Round(($testResults | Measure-Object -Sum -Property Failures).Sum))
#     Errors       = [int]([math]::Round(($testResults | Measure-Object -Sum -Property Errors).Sum))
#     Invalid      = [int]([math]::Round(($testResults | Measure-Object -Sum -Property Invalid).Sum))
#     NotRun       = [int]([math]::Round(($testResults | Measure-Object -Sum -Property NotRun).Sum))
#     Inconclusive = [int]([math]::Round(($testResults | Measure-Object -Sum -Property Inconclusive).Sum))
#     Ignored      = [int]([math]::Round(($testResults | Measure-Object -Sum -Property Ignored).Sum))
#     Skipped      = [int]([math]::Round(($testResults | Measure-Object -Sum -Property Skipped).Sum))
# }
# $total | Format-Table | Out-String

# $totalErrors = 0
# if ($total.Failures -gt 0) {
#     Write-GitHubError "There are $($total.Failures) failed tests of $($total.Tests) tests"
#     $totalErrors += $_.Failures
# }

# if ($total.Errors -gt 0) {
#     Write-GitHubError "There are $($total.Errors) test errors of $($total.Tests) tests"
#     $totalErrors += $_.Errors
# }

# if ($total.Invalid -gt 0) {
#     Write-GitHubError "There are $($total.Invalid) invalid test of $($total.Tests) tests"
#     $totalErrors += $_.Invalid
# }

# if ($total.NotRun -gt 0) {
#     Write-GitHubError "There are $($total.NotRun) test not run of $($total.Tests) tests"
#     $totalErrors += $_.NotRun
# }

# if ($total.Inconclusive -gt 0) {
#     Write-GitHubError "There are $($total.Inconclusive) inconclusive tests of $($total.Tests) tests"
#     $totalErrors += $_.Inconclusive
# }

# exit $totalErrors
