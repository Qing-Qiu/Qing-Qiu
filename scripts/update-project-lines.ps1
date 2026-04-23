Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$readmePath = Join-Path $repoRoot 'README.md'

$projects = @(
    [PSCustomObject]@{
        Name = 'TuneLab'
        Url = 'https://github.com/Qing-Qiu/TuneLab'
        CloneUrl = 'https://github.com/Qing-Qiu/TuneLab.git'
        Description = 'WeChat Mini Program for music playback, shared listening rooms, location-based song notes, melody challenges, surprise interactions, and Schulte grid training'
        Stack = 'JavaScript, WeChat Mini Program, WeChat Cloud Functions'
        Languages = @('JavaScript', 'WXSS', 'WXML')
    },
    [PSCustomObject]@{
        Name = 'MovieRec'
        Url = 'https://github.com/Qing-Qiu/MovieRec'
        CloneUrl = 'https://github.com/Qing-Qiu/MovieRec.git'
        Description = 'Movie recommendation and exploration system with search, personalized recommendations, movie/person details, comments, chart analysis, AI assistant, and music proxy'
        Stack = 'Vue, Java, Python, JavaScript, CSS, HTML'
        Languages = @('Vue', 'Java', 'Python', 'JavaScript', 'CSS', 'HTML')
    }
)

$languageByExtension = @{
    '.js' = 'JavaScript'
    '.jsx' = 'JavaScript'
    '.mjs' = 'JavaScript'
    '.cjs' = 'JavaScript'
    '.vue' = 'Vue'
    '.java' = 'Java'
    '.py' = 'Python'
    '.css' = 'CSS'
    '.scss' = 'CSS'
    '.less' = 'CSS'
    '.html' = 'HTML'
    '.htm' = 'HTML'
    '.wxml' = 'WXML'
    '.wxss' = 'WXSS'
}

$ignoredPathPattern = '(^|/)(node_modules|miniprogram_npm|dist|build|target|\.git|\.idea|coverage|__pycache__)(/|$)'

function Format-Number {
    param([int]$Number)
    return $Number.ToString('N0', [System.Globalization.CultureInfo]::InvariantCulture)
}

function Count-ProjectLines {
    param(
        [Parameter(Mandatory = $true)] [object] $Project,
        [Parameter(Mandatory = $true)] [string] $TempRoot
    )

    $projectDir = Join-Path $TempRoot $Project.Name
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        git clone --depth 1 $Project.CloneUrl $projectDir *> $null
        $cloneExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    if ($cloneExitCode -ne 0) {
        throw "Failed to clone $($Project.CloneUrl)"
    }

    $counts = @{}
    foreach ($language in $Project.Languages) {
        $counts[$language] = 0
    }

    $files = git -C $projectDir ls-files
    foreach ($file in $files) {
        $normalizedPath = $file -replace '\\', '/'
        if ($normalizedPath -match $ignoredPathPattern) {
            continue
        }

        $extension = [System.IO.Path]::GetExtension($file).ToLowerInvariant()
        if (-not $languageByExtension.ContainsKey($extension)) {
            continue
        }

        $language = $languageByExtension[$extension]
        if (-not $counts.ContainsKey($language)) {
            continue
        }

        $fullPath = Join-Path $projectDir $file
        try {
            $counts[$language] += ([System.IO.File]::ReadLines($fullPath) | Measure-Object).Count
        }
        catch {
            Write-Warning "Skipped unreadable file: $file"
        }
    }

    return [PSCustomObject]@{
        Project = $Project
        Counts = $counts
        Total = ($counts.Values | Measure-Object -Sum).Sum
    }
}

function Set-MarkdownBlock {
    param(
        [Parameter(Mandatory = $true)] [string] $Content,
        [Parameter(Mandatory = $true)] [string] $StartMarker,
        [Parameter(Mandatory = $true)] [string] $EndMarker,
        [Parameter(Mandatory = $true)] [string] $Replacement
    )

    $pattern = "(?s)<!-- $([regex]::Escape($StartMarker)) -->.*?<!-- $([regex]::Escape($EndMarker)) -->"
    $newBlock = "<!-- $StartMarker -->`n$Replacement`n<!-- $EndMarker -->"

    if ($Content -notmatch $pattern) {
        throw "Could not find markdown block: $StartMarker"
    }

    return [regex]::Replace($Content, $pattern, $newBlock)
}

$tempBase = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [System.IO.Path]::GetTempPath() }
$tempRoot = Join-Path $tempBase ("qing-qiu-project-lines-" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot | Out-Null

try {
    $results = foreach ($project in $projects) {
        Count-ProjectLines -Project $project -TempRoot $tempRoot
    }

    $projectRows = foreach ($result in $results) {
        $project = $result.Project
        "| [$($project.Name)]($($project.Url)) | $($project.Description) | $($project.Stack) | $(Format-Number $result.Total) |"
    }
    $projectTable = @(
        '| Project | Main Content | Tech Stack | Lines |'
        '| --- | --- | --- | --- |'
        $projectRows
    ) -join "`n"

    $languageRows = foreach ($result in $results) {
        foreach ($language in $result.Project.Languages) {
            "| $($result.Project.Name) | $language | $(Format-Number $result.Counts[$language]) |"
        }
    }
    $languageTable = @(
        '| Project | Language | Lines |'
        '| --- | --- | --- |'
        $languageRows
    ) -join "`n"

    $readme = [System.IO.File]::ReadAllText($readmePath, [System.Text.Encoding]::UTF8)
    $readme = Set-MarkdownBlock -Content $readme -StartMarker 'PROJECT_SHOWCASE_START' -EndMarker 'PROJECT_SHOWCASE_END' -Replacement $projectTable
    $readme = Set-MarkdownBlock -Content $readme -StartMarker 'LANGUAGE_LINES_START' -EndMarker 'LANGUAGE_LINES_END' -Replacement $languageTable

    [System.IO.File]::WriteAllText($readmePath, $readme, [System.Text.UTF8Encoding]::new($false))
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Get-ChildItem -LiteralPath $tempRoot -Recurse -Force | ForEach-Object { $_.Attributes = 'Normal' }
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
