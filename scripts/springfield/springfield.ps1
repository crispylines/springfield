# Springfield - Autonomous Development Loop (PowerShell)
# Usage: .\scripts\springfield\springfield.ps1 [-MaxIterations 40] [-SkipSetup]
#
# Phases:
#   0. User Input     - Ask what to build
#   1. Decomposer     - Research & generate stories
#   2. Architect       - Create implementation plan
#   3. Build Loop      - Builder implements, Reviewer validates
#   4. Completion      - Summary report

param(
    [int]$MaxIterations = 40,
    [switch]$SkipSetup,
    [switch]$NoDashboard
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$ErrorActionPreference = "Continue"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $ScriptDir)
$PromptsDir = Join-Path $ScriptDir "prompts"
$MaxAttempts = 3

$PrdPath = Join-Path $ScriptDir "prd.json"
$ProgressPath = Join-Path $ScriptDir "progress.txt"
$ResearchPath = Join-Path $ScriptDir "research.md"
$ArchitecturePath = Join-Path $ScriptDir "architecture.md"
$StatusPath = Join-Path $ScriptDir "status.json"
$DashboardPort = 3333
$script:eventLog = @()
$script:projectName = ""
$script:currentIteration = 0
$script:serverProcess = $null
$script:loopStartTime = $null

# --- Helper Functions -------------------------------------------------

function Write-Phase {
    param([string]$Phase, [string]$Message, [string]$Color = "Cyan")
    Write-Host ""
    Write-Host "==============================================" -ForegroundColor $Color
    Write-Host "  [$Phase] $Message" -ForegroundColor $Color
    Write-Host "==============================================" -ForegroundColor $Color
    Write-Host ""
}

function Write-Step {
    param([string]$Message, [string]$Color = "Gray")
    Write-Host "  -> $Message" -ForegroundColor $Color
}

function Invoke-Claude {
    param([string]$Prompt)
    
    # Write prompt to temp file to avoid command-line length limits
    $tempFile = Join-Path $ScriptDir ".springfield-current-prompt.md"
    $Prompt | Out-File -FilePath $tempFile -Encoding UTF8 -NoNewline
    
    try {
        $instruction = "Read and follow ALL instructions in this file: $tempFile"
        $output = & claude --dangerously-skip-permissions -p $instruction 2>&1
        $outputStr = $output | Out-String
        Write-Host $outputStr
        return $outputStr
    }
    catch {
        Write-Host "  ERROR: Claude execution failed: $_" -ForegroundColor Red
        return ""
    }
    finally {
        Remove-Item $tempFile -ErrorAction SilentlyContinue
    }
}

function Get-PrdStories {
    if (Test-Path $PrdPath) {
        $prd = Get-Content $PrdPath -Raw | ConvertFrom-Json
        return $prd.userStories
    }
    return @()
}

function Test-HasUnfinishedStories {
    $stories = Get-PrdStories
    foreach ($story in $stories) {
        if (-not $story.passes -and -not $story.blocked) {
            return $true
        }
    }
    return $false
}

function Test-HasUnreviewedStories {
    $stories = Get-PrdStories
    foreach ($story in $stories) {
        if ($story.passes -and -not $story.reviewed) {
            return $true
        }
    }
    return $false
}

function Get-StoryStatus {
    $stories = Get-PrdStories
    $total = $stories.Count
    $passed = ($stories | Where-Object { $_.passes }).Count
    $reviewed = ($stories | Where-Object { $_.reviewed }).Count
    $blocked = ($stories | Where-Object { $_.blocked }).Count
    $remaining = $total - $passed - $blocked
    return @{
        Total = $total
        Passed = $passed
        Reviewed = $reviewed
        Blocked = $blocked
        Remaining = $remaining
    }
}

function Write-Status {
    param(
        [string]$Phase,
        [string]$ActiveAgent = "",
        [string]$StoryId = "",
        [string]$StoryTitle = "",
        [string]$StatusEvent = ""
    )

    if ($StatusEvent) {
        $time = (Get-Date).ToString("HH:mm:ss")
        $script:eventLog += @{ time = $time; event = $StatusEvent }
    }

    $stories = Get-PrdStories
    $ss = Get-StoryStatus

    $storyDetails = @()
    foreach ($s in $stories) {
        $storyDetails += @{
            id = if ($s.id) { $s.id } else { "" }
            passes = [bool]$s.passes
            reviewed = [bool]$s.reviewed
            blocked = [bool]$s.blocked
            active = ($s.id -eq $StoryId)
        }
    }

    $statusObj = @{
        phase = $Phase
        activeAgent = $ActiveAgent
        currentStory = @{ id = $StoryId; title = $StoryTitle }
        stories = @{
            total = $ss.Total
            passed = $ss.Passed
            reviewed = $ss.Reviewed
            blocked = $ss.Blocked
            remaining = $ss.Remaining
        }
        iteration = $script:currentIteration
        maxIterations = $MaxIterations
        lastEvent = $StatusEvent
        eventLog = $script:eventLog
        startTime = if ($script:loopStartTime) { $script:loopStartTime.ToString("yyyy-MM-ddTHH:mm:ss") } else { "" }
        projectName = $script:projectName
        storyDetails = $storyDetails
    }

    $statusObj | ConvertTo-Json -Depth 10 | Set-Content $StatusPath -Encoding UTF8
}

function Start-Dashboard {
    if ($NoDashboard) { return }
    try {
        $existingPidFile = Join-Path $ScriptDir ".dashboard-pid"
        if (Test-Path $existingPidFile) {
            $oldPid = Get-Content $existingPidFile -Raw
            Stop-Process -Id ([int]$oldPid.Trim()) -ErrorAction SilentlyContinue
        }
        $script:serverProcess = Start-Process python -ArgumentList "-m http.server $DashboardPort" -WorkingDirectory $ProjectRoot -PassThru -WindowStyle Hidden
        $script:serverProcess.Id | Out-File $existingPidFile -Encoding UTF8
        Write-Step "Dashboard server started on port $DashboardPort"
        Start-Sleep -Milliseconds 800
        Start-Process "http://localhost:$DashboardPort/dashboard/"
        Write-Step "Dashboard opened in browser"
    }
    catch {
        Write-Step "Could not start dashboard (Python required)" "Yellow"
    }
}

function Stop-Dashboard {
    if ($script:serverProcess) {
        Stop-Process -Id $script:serverProcess.Id -ErrorAction SilentlyContinue
        $pidFile = Join-Path $ScriptDir ".dashboard-pid"
        Remove-Item $pidFile -ErrorAction SilentlyContinue
        Write-Step "Dashboard server stopped"
    }
}

# --- Startup ----------------------------------------------------------

Write-Host ""
Write-Host "+----------------------------------------------+" -ForegroundColor Magenta
Write-Host "|          SPRINGFIELD - Starting Up           |" -ForegroundColor Magenta
Write-Host "|  Decomposer > Architect > Builder > Reviewer |" -ForegroundColor Magenta
Write-Host "+----------------------------------------------+" -ForegroundColor Magenta
Write-Host "  Project Root   : $ProjectRoot" -ForegroundColor Gray
Write-Host "  Max Iterations : $MaxIterations" -ForegroundColor Gray
Write-Host ""

Set-Location $ProjectRoot

Start-Dashboard
Write-Status -Phase "input" -StatusEvent "Springfield starting up"

# --- RESUME CHECK -----------------------------------------------------

$hasPrd = $false
if (Test-Path $PrdPath) {
    try {
        $prdContent = Get-Content $PrdPath -Raw | ConvertFrom-Json
        if ($prdContent.userStories.Count -gt 0) { $hasPrd = $true }
    } catch { $hasPrd = $false }
}
$hasArchitecture = Test-Path $ArchitecturePath
$needsDecomposer = -not $hasPrd
$needsArchitect = -not $hasArchitecture

if ($hasPrd) {
    try {
        $resumePrd = Get-Content $PrdPath -Raw | ConvertFrom-Json
        if ($resumePrd.projectName) { $script:projectName = $resumePrd.projectName }
    } catch {}
}

if ($hasPrd -and $hasArchitecture) {
    $status = Get-StoryStatus
    Write-Phase "RESUME" "Existing progress detected" "Yellow"
    Write-Step "Stories: $($status.Total) total, $($status.Passed) passed, $($status.Reviewed) reviewed, $($status.Blocked) blocked"
    Write-Step "Skipping Decomposer and Architect phases"
    Write-Step "Resuming build loop..."
}
elseif ($hasPrd -and -not $hasArchitecture) {
    Write-Phase "RESUME" "PRD exists but no architecture plan" "Yellow"
    Write-Step "Skipping Decomposer, running Architect..."
}

# --- Verify prompt files exist ---
foreach ($promptFile in @("decomposer.md","architect.md","builder.md","reviewer.md")) {
    if (-not (Test-Path (Join-Path $PromptsDir $promptFile))) {
        Write-Host "  ERROR: Missing prompt file: $promptFile" -ForegroundColor Red
        Stop-Dashboard
        exit 1
    }
}

# --- PHASE 0: USER INPUT ---------------------------------------------

if ($needsDecomposer -and -not $SkipSetup) {
    Write-Phase "PHASE 0" "What are we building?" "Cyan"
    
    $projectDescription = Read-Host "  Describe your project in a few sentences"
    
    if ([string]::IsNullOrWhiteSpace($projectDescription)) {
        Write-Host "  ERROR: You must provide a project description." -ForegroundColor Red
        Stop-Dashboard
        exit 1
    }
    
    $referenceUrls = Read-Host "  Any reference URLs or docs? (comma-separated, or press Enter to skip)"
    
    Write-Host ""
    Write-Step "Project: $projectDescription" "White"
    if (-not [string]::IsNullOrWhiteSpace($referenceUrls)) {
        Write-Step "References: $referenceUrls" "White"
    }
    $script:projectName = $projectDescription
    
    # --- FOLLOW-UP QUESTIONS ---
    
    Write-Host ""
    Write-Step "Springfield is generating follow-up questions..." "Cyan"
    
    $followupPrompt = Get-Content (Join-Path $PromptsDir "followup.md") -Raw
    $followupPrompt += "`n$projectDescription"
    if (-not [string]::IsNullOrWhiteSpace($referenceUrls)) {
        $followupPrompt += "`nReference URLs: $referenceUrls"
    }
    
    $followupTemp = Join-Path $ScriptDir ".springfield-current-prompt.md"
    $followupPrompt | Out-File -FilePath $followupTemp -Encoding UTF8 -NoNewline
    
    try {
        $followupInstruction = "Read and follow ALL instructions in this file: $followupTemp"
        $followupOutput = & claude --dangerously-skip-permissions -p $followupInstruction 2>&1 | Out-String
    }
    catch {
        $followupOutput = ""
    }
    Remove-Item $followupTemp -ErrorAction SilentlyContinue
    
    $followupAnswers = ""
    
    $questions = $followupOutput -split "`n" | Where-Object { $_ -match '^\s*Q\d' } | ForEach-Object { $_.Trim() }
    
    if ($questions.Count -gt 0) {
        Write-Host ""
        Write-Host "  Springfield has a few follow-up questions:" -ForegroundColor Cyan
        Write-Host ""
        
        foreach ($q in $questions) {
            $questionText = $q -replace '^\s*Q\d:\s*', ''
            $qNum = "?"
            if ($q -match 'Q(\d)') { $qNum = $Matches[1] }
            Write-Host "  $qNum. $questionText" -ForegroundColor White
            $answer = Read-Host "     "
            if (-not [string]::IsNullOrWhiteSpace($answer)) {
                $followupAnswers += "`n- Q: $questionText`n  A: $answer"
            }
            Write-Host ""
        }
    }
    else {
        Write-Step "No follow-up questions generated, proceeding..." "Gray"
    }
}

# --- PHASE 1: DECOMPOSER ---------------------------------------------

if ($needsDecomposer) {
    Write-Phase "PHASE 1" "Decomposer - Researching & generating stories" "Green"
    Write-Status -Phase "decomposing" -ActiveAgent "decomposer" -StatusEvent "Decomposer started"
    
    $decomposerPrompt = Get-Content (Join-Path $PromptsDir "decomposer.md") -Raw
    
    $userInput = @"

## User Input

**Project Description**: $projectDescription
**Reference URLs**: $referenceUrls
**Project Root**: $ProjectRoot
**Scripts Directory**: $ScriptDir
"@
    
    if (-not [string]::IsNullOrWhiteSpace($followupAnswers)) {
        $userInput += @"

**Follow-up Q&A** (user clarifications):
$followupAnswers
"@
    }
    
    $fullPrompt = $decomposerPrompt + $userInput
    
    Write-Step "Running Decomposer agent..."
    $output = Invoke-Claude $fullPrompt
    
    # Verify prd.json was created with stories
    if (-not (Test-Path $PrdPath)) {
        Write-Host "  ERROR: Decomposer failed to create prd.json" -ForegroundColor Red
        Stop-Dashboard
        exit 1
    }
    
    $stories = Get-PrdStories
    if ($stories.Count -eq 0) {
        Write-Host "  ERROR: Decomposer created empty prd.json" -ForegroundColor Red
        Stop-Dashboard
        exit 1
    }
    
    Write-Step "prd.json created with $($stories.Count) stories" "Green"
    Write-Status -Phase "decomposing" -ActiveAgent "decomposer" -StatusEvent "PRD generated: $($stories.Count) stories"
    Write-Host ""
}

# --- PHASE 2: ARCHITECT ----------------------------------------------

if ($needsArchitect) {
    Write-Phase "PHASE 2" "Architect - Creating implementation plan" "Blue"
    Write-Status -Phase "architecting" -ActiveAgent "architect" -StatusEvent "Architect started"
    
    $architectPrompt = Get-Content (Join-Path $PromptsDir "architect.md") -Raw
    
    Write-Step "Running Architect agent..."
    $output = Invoke-Claude $architectPrompt
    
    if (-not (Test-Path $ArchitecturePath)) {
        Write-Host "  ERROR: Architect failed to create architecture.md" -ForegroundColor Red
        exit 1
    }
    
    Write-Step "architecture.md created" "Green"
    Write-Status -Phase "architecting" -ActiveAgent "architect" -StatusEvent "Architecture plan created"
    Write-Host ""
}

# --- PHASE 3: BUILD LOOP ---------------------------------------------

Write-Phase "PHASE 3" "Build Loop - Builder + Reviewer" "Yellow"

$startTime = Get-Date
$script:loopStartTime = $startTime

for ($i = 1; $i -le $MaxIterations; $i++) {
    $script:currentIteration = $i
    $status = Get-StoryStatus
    
    Write-Host ""
    Write-Host "  +------------------------------------------+" -ForegroundColor Yellow
    Write-Host "  |  Iteration $i of $MaxIterations" -ForegroundColor Yellow
    Write-Host "  |  Passed: $($status.Passed)/$($status.Total)  Reviewed: $($status.Reviewed)/$($status.Total)  Blocked: $($status.Blocked)" -ForegroundColor Yellow
    Write-Host "  +------------------------------------------+" -ForegroundColor Yellow
    Write-Host ""
    
    # Check if all stories are done
    if (-not (Test-HasUnfinishedStories) -and -not (Test-HasUnreviewedStories)) {
        break
    }
    
    # -- BUILDER PASS --
    
    if (Test-HasUnfinishedStories) {
        # Create git checkpoint tag
        $nextStory = (Get-PrdStories | Where-Object { -not $_.passes -and -not $_.blocked } | Sort-Object priority | Select-Object -First 1)
        if ($nextStory) {
            $tagName = "springfield-checkpoint-$($nextStory.id)"
            & git tag -f $tagName 2>$null
            Write-Step "Git checkpoint: $tagName"
        }
        
        Write-Step "BUILDER: Working on next story..." "Cyan"
        Write-Status -Phase "building" -ActiveAgent "builder" -StoryId $nextStory.id -StoryTitle $nextStory.title -StatusEvent "Builder started $($nextStory.id): $($nextStory.title)"
        
        $builderPrompt = Get-Content (Join-Path $PromptsDir "builder.md") -Raw
        $builderOutput = Invoke-Claude $builderPrompt
        
        Write-Status -Phase "building" -ActiveAgent "builder" -StoryId $nextStory.id -StoryTitle $nextStory.title -StatusEvent "Builder finished $($nextStory.id)"
    }
    
    # -- REVIEWER PASS --
    
    if (Test-HasUnreviewedStories) {
        Write-Step "REVIEWER: Validating completed work..." "Magenta"
        Write-Status -Phase "reviewing" -ActiveAgent "reviewer" -StatusEvent "Reviewer started"
        
        $reviewerPrompt = Get-Content (Join-Path $PromptsDir "reviewer.md") -Raw
        $reviewerOutput = Invoke-Claude $reviewerPrompt
        
        Write-Status -Phase "reviewing" -ActiveAgent "reviewer" -StatusEvent "Reviewer finished"
    }
    
    # -- CHECK FOR BLOCKED STORIES (runs every iteration regardless) --
    
    $stories = Get-PrdStories
    foreach ($story in $stories) {
        if ($story.attempts -ge $MaxAttempts -and -not $story.passes -and -not $story.blocked) {
            Write-Host ""
            Write-Host "  +=========================================+" -ForegroundColor Red
            Write-Host "  | STORY FAILED 3 TIMES: $($story.id)" -ForegroundColor Red
            Write-Host "  | $($story.title)" -ForegroundColor Red
            Write-Host "  | Last error: $($story.lastError)" -ForegroundColor Red
            Write-Host "  +=========================================+" -ForegroundColor Red
            Write-Host ""
            
            $tagName = "springfield-checkpoint-$($story.id)"
            $tagExists = & git tag -l $tagName 2>$null
            if ($tagExists) {
                Write-Step "Rolling back to checkpoint: $tagName" "Yellow"
                & git reset --hard $tagName 2>$null
            }
            
            Write-Host "  What would you like to do?" -ForegroundColor White
            Write-Host "  [1] Continue to next story (mark this one blocked)" -ForegroundColor White
            Write-Host "  [2] Stop the loop to debug" -ForegroundColor White
            $choice = Read-Host "  Enter 1 or 2"
            
            if ($choice -eq "2") {
                Write-Host ""
                Write-Step "Stopping loop. Debug the issue, then restart the script to resume." "Yellow"
                Write-Step "Story $($story.id) has $($story.attempts) attempts logged."
                Write-Step "Review notes: $($story.reviewNotes)"
                Stop-Dashboard
                exit 0
            }
            else {
                $prd = Get-Content $PrdPath -Raw | ConvertFrom-Json
                foreach ($s in $prd.userStories) {
                    if ($s.id -eq $story.id) {
                        $s.blocked = $true
                    }
                }
                $prd | ConvertTo-Json -Depth 10 | Set-Content $PrdPath -Encoding UTF8
                Write-Status -Phase "blocked" -StatusEvent "Story $($story.id) marked as blocked"
                Write-Step "Story $($story.id) marked as blocked. Continuing..." "Yellow"
            }
            break
        }
    }
    
    Write-Host ""
    Write-Step "Sleeping 3 seconds before next iteration..."
    Start-Sleep -Seconds 3
}

# --- PHASE 4: COMPLETION ---------------------------------------------

$endTime = Get-Date
$duration = $endTime - $startTime
$status = Get-StoryStatus
$durationMin = [math]::Floor($duration.TotalMinutes)
$durationSec = $duration.Seconds

Write-Host ""
Write-Host "+----------------------------------------------+" -ForegroundColor Green
Write-Host "|           SPRINGFIELD - COMPLETE             |" -ForegroundColor Green
Write-Host "+----------------------------------------------+" -ForegroundColor Green
Write-Host "|  Stories Total    : $($status.Total)" -ForegroundColor Green
Write-Host "|  Passed           : $($status.Passed)" -ForegroundColor Green
Write-Host "|  Reviewed         : $($status.Reviewed)" -ForegroundColor Green
Write-Host "|  Blocked          : $($status.Blocked)" -ForegroundColor Green
Write-Host "|  Duration         : ${durationMin}m ${durationSec}s" -ForegroundColor Green
Write-Host "+----------------------------------------------+" -ForegroundColor Green
Write-Host ""
Write-Host "  Check commits  : git log --oneline -20" -ForegroundColor Gray
Write-Host "  Check progress : Get-Content scripts/springfield/progress.txt" -ForegroundColor Gray
Write-Host "  Check stories  : Get-Content scripts/springfield/prd.json" -ForegroundColor Gray
Write-Host ""

if ($status.Blocked -gt 0) {
    Write-Host "  WARNING: $($status.Blocked) stories were blocked. Review them manually." -ForegroundColor Yellow
    $blockedStories = Get-PrdStories | Where-Object { $_.blocked }
    foreach ($s in $blockedStories) {
        Write-Host "    - $($s.id): $($s.title)" -ForegroundColor Yellow
        if ($s.reviewNotes) {
            Write-Host "      Notes: $($s.reviewNotes)" -ForegroundColor Gray
        }
    }
}

if ($status.Remaining -gt 0) {
    Write-Host ""
    Write-Host "  Max iterations reached with $($status.Remaining) stories remaining." -ForegroundColor Yellow
    Write-Host "  Run the script again to continue." -ForegroundColor Yellow
    Stop-Dashboard
    exit 1
}

Write-Status -Phase "complete" -StatusEvent "Springfield finished"
Write-Host "  Dashboard will close in 30 seconds (or press Ctrl+C)..." -ForegroundColor Gray
Start-Sleep -Seconds 30
Stop-Dashboard
exit 0
