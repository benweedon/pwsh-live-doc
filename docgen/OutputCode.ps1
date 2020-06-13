function RunPowerShellExe {
    [CmdletBinding()]
    [OutputType([Tuple[SemanticVersion, String][]])]
    param(
        [Parameter(Mandatory)]
        [Tuple[String, SemanticVersion]] $Tuple,
        [Parameter(Mandatory)]
        [String] $CodeToRun
    )

    Write-Host "Running $($Tuple.Item1)"

    [String] $commandOutput = InvokeExe $Tuple.Item1 $CodeToRun
    [String] $formattedCommandOutput = "<pre class=`"output-text`">" + $commandOutput + "</pre>"

    return [Tuple]::Create($Tuple.Item2, $formattedCommandOutput)
}

function OutputCode {
    [CmdletBinding()]
    [OutputType([String])]
    param(
        [Parameter(Mandatory)]
        [ScriptBlock] $Code,
        [String] $MinVersion = "0"
    )

    [String] $codeAsString = $Code.ToString()
    [String] $formattedCode = FormatPageText $codeAsString
    [String] $codeHtml = "<pre class=`"code-view`"><code class=`"powershell`">" + $formattedCode + "</code></pre>"

    [String] $outputTableHtml = "<table class=`"output-table`"><caption>Output by version</caption><thead><tr>"

    [Tuple[String, SemanticVersion][]] $exesToTest = GetPowerShellExesToTest ([SemanticVersion]::new($MinVersion))

    [Tuple[SemanticVersion, String][]] $powershellResults = $exesToTest | ForEach-Object -ThrottleLimit 8 -Parallel {
        [Tuple[String, System.Management.Automation.SemanticVersion]] $tuple = $_

        $docgen = Import-Module "$using:PSScriptRoot\..\docgen" -Force -PassThru
        # Run in the context of the docgen module
        return & $docgen { RunPowerShellExe $tuple $using:codeAsString }
    }

    [SemanticVersion[]] $allVersions = $powershellResults | ForEach-Object { $_.Item1 }

    # Create a map of output string to list of versions. This lets us group
    # versions by what their output is.
    [Dictionary[String, SemanticVersion[]]] $outputToVersionMap = [Dictionary[String, SemanticVersion[]]]::new()
    foreach ($tuple in $powershellResults) {
        [SemanticVersion] $version = $tuple.Item1
        [String] $output = $tuple.Item2

        if (-not $outputToVersionMap.ContainsKey($output)) {
            $outputToVersionMap[$output] = @()
        }

        $outputToVersionMap[$output] += $version
    }

    # Now create a map from version string to corresponding output. This lets
    # us sort the version strings without mismatching them with their outputs.
    [Dictionary[String, String]] $versionStringToOutputMap = [Dictionary[String, String]]::new()
    foreach ($output in $outputToVersionMap.Keys) {
        [String[]] $generalizedVersions = GeneralizeVersions $allVersions $outputToVersionMap[$output] | Sort-Object
        $versionStringToOutputMap["<th>$($generalizedVersions -join ", ")</th>"] = $output
    }

    [String[]] $sortedVersionKeys = $versionStringToOutputMap.Keys | Sort-Object
    $outputTableHtml += "$sortedVersionKeys"

    $outputTableHtml += "</tr></thead><tbody><tr>"

    foreach ($versionString in $sortedVersionKeys) {
        [String] $output = $versionStringToOutputMap[$versionString]
        $outputTableHtml += "<td>$output</td>"
    }

    $outputTableHtml += "</tr></tbody></table>"

    return $codeHtml + $outputTableHtml
}
