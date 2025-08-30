function Prompt {
    "PS [" + $env:PERSONA + "][" + $env:RESOURCE_GROUP + "][" + $env:DEMO + "] " + (Get-Location) + "> "
}

Set-PSReadLineOption -PredictionSource History
set-PSReadLineOption -PredictionViewStyle ListView