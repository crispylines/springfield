#!/bin/bash
# Springfield - Autonomous Development Loop (Bash)
# Usage: ./scripts/springfield/springfield.sh [max_iterations] [--no-dashboard]
#
# Phases:
#   0. User Input     - Ask what to build
#   1. Decomposer     - Research & generate stories
#   2. Architect       - Create implementation plan
#   3. Build Loop      - Builder implements, Reviewer validates
#   4. Completion      - Summary report

set -euo pipefail

MAX_ITERATIONS=40
MAX_ATTEMPTS=3
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROMPTS_DIR="$SCRIPT_DIR/prompts"

PRD_PATH="$SCRIPT_DIR/prd.json"
PROGRESS_PATH="$SCRIPT_DIR/progress.txt"
RESEARCH_PATH="$SCRIPT_DIR/research.md"
ARCHITECTURE_PATH="$SCRIPT_DIR/architecture.md"
STATUS_PATH="$SCRIPT_DIR/status.json"
DASHBOARD_PORT=3333
PROJECT_NAME_VAR=""
CURRENT_ITERATION=0
SERVER_PID=""
LOOP_START_TIME=""
NO_DASHBOARD=false

for arg in "$@"; do
    case "$arg" in
        --no-dashboard) NO_DASHBOARD=true ;;
        [0-9]*) MAX_ITERATIONS="$arg" ;;
    esac
done

if ! command -v claude &>/dev/null; then
    echo "ERROR: 'claude' CLI not found on PATH. Install: npm install -g @anthropic-ai/claude-code" >&2
    exit 1
fi
if ! command -v python3 &>/dev/null; then
    echo "ERROR: 'python3' is required but not found." >&2
    exit 1
fi

# --- Helper Functions -------------------------------------------------

write_phase() {
    local phase="$1" message="$2" color="${3:-36}"
    echo ""
    echo -e "\033[${color}m==============================================\033[0m"
    echo -e "\033[${color}m  [$phase] $message\033[0m"
    echo -e "\033[${color}m==============================================\033[0m"
    echo ""
}

write_step() {
    local message="$1" color="${2:-37}"
    echo -e "\033[${color}m  -> $message\033[0m"
}

invoke_claude() {
    local prompt="$1"
    local temp_file="$SCRIPT_DIR/.springfield-current-prompt.md"
    
    echo "$prompt" > "$temp_file"
    
    local instruction="Read and follow ALL instructions in this file: $temp_file"
    local output
    output=$(claude --dangerously-skip-permissions -p "$instruction" 2>&1) || true
    
    rm -f "$temp_file"
    
    echo "$output"
    echo "$output" >&2
}

get_story_count() {
    if [ -f "$PRD_PATH" ]; then
        python3 -c "
import json, sys
with open('$PRD_PATH') as f:
    prd = json.load(f)
stories = prd.get('userStories', [])
total = len(stories)
passed = sum(1 for s in stories if s.get('passes'))
reviewed = sum(1 for s in stories if s.get('reviewed'))
blocked = sum(1 for s in stories if s.get('blocked'))
remaining = total - passed - blocked
print(f'{total} {passed} {reviewed} {blocked} {remaining}')
" 2>/dev/null || echo "0 0 0 0 0"
    else
        echo "0 0 0 0 0"
    fi
}

has_unfinished_stories() {
    if [ -f "$PRD_PATH" ]; then
        python3 -c "
import json
with open('$PRD_PATH') as f:
    prd = json.load(f)
for s in prd.get('userStories', []):
    if not s.get('passes') and not s.get('blocked'):
        exit(0)
exit(1)
" 2>/dev/null
    else
        return 1
    fi
}

has_unreviewed_stories() {
    if [ -f "$PRD_PATH" ]; then
        python3 -c "
import json
with open('$PRD_PATH') as f:
    prd = json.load(f)
for s in prd.get('userStories', []):
    if s.get('passes') and not s.get('reviewed'):
        exit(0)
exit(1)
" 2>/dev/null
    else
        return 1
    fi
}

get_next_story_id() {
    python3 -c "
import json
with open('$PRD_PATH') as f:
    prd = json.load(f)
stories = [s for s in prd.get('userStories', []) if not s.get('passes') and not s.get('blocked')]
stories.sort(key=lambda s: s.get('priority', 999))
if stories:
    print(stories[0]['id'])
else:
    print('')
" 2>/dev/null
}

check_blocked_stories() {
    python3 -c "
import json
with open('$PRD_PATH') as f:
    prd = json.load(f)
for s in prd.get('userStories', []):
    if s.get('attempts', 0) >= $MAX_ATTEMPTS and not s.get('passes') and not s.get('blocked'):
        print(f\"{s['id']}|{s.get('title','')}|{s.get('lastError','')}|{s.get('reviewNotes','')}\")
" 2>/dev/null
}

mark_story_blocked() {
    local story_id="$1"
    python3 -c "
import json
with open('$PRD_PATH', 'r') as f:
    prd = json.load(f)
for s in prd.get('userStories', []):
    if s['id'] == '$story_id':
        s['blocked'] = True
with open('$PRD_PATH', 'w') as f:
    json.dump(prd, f, indent=2)
" 2>/dev/null
}

has_prd_with_stories() {
    if [ -f "$PRD_PATH" ]; then
        local count
        count=$(python3 -c "
import json
with open('$PRD_PATH') as f:
    prd = json.load(f)
print(len(prd.get('userStories', [])))
" 2>/dev/null)
        [ "$count" -gt 0 ] 2>/dev/null
    else
        return 1
    fi
}

write_status() {
    local phase="${1:-}" active_agent="${2:-}" story_id="${3:-}" story_title="${4:-}" event="${5:-}"
    python3 -c "
import json, os, sys
from datetime import datetime
phase, active_agent, story_id, story_title, event = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
status_path, prd_path = sys.argv[6], sys.argv[7]
project_name, iteration, max_iter, start_time = sys.argv[8], int(sys.argv[9]), int(sys.argv[10]), sys.argv[11]
event_log = []
if os.path.exists(status_path):
    try:
        with open(status_path) as f:
            event_log = json.load(f).get('eventLog', [])
    except: pass
if event:
    event_log.append({'time': datetime.now().strftime('%H:%M:%S'), 'event': event})
sd, si = [], {'total':0,'passed':0,'reviewed':0,'blocked':0,'remaining':0}
if os.path.exists(prd_path):
    try:
        with open(prd_path) as f:
            stories = json.load(f).get('userStories', [])
        for s in stories:
            if s.get('passes'): si['passed'] += 1
            if s.get('reviewed'): si['reviewed'] += 1
            if s.get('blocked'): si['blocked'] += 1
            sd.append({'id':s.get('id',''),'passes':bool(s.get('passes')),'reviewed':bool(s.get('reviewed')),'blocked':bool(s.get('blocked')),'active':s.get('id')==story_id})
        si['total'] = len(sd)
        si['remaining'] = si['total'] - si['passed'] - si['blocked']
    except: pass
with open(status_path, 'w') as f:
    json.dump({'phase':phase,'activeAgent':active_agent,'currentStory':{'id':story_id,'title':story_title},'stories':si,'iteration':iteration,'maxIterations':max_iter,'lastEvent':event,'eventLog':event_log,'startTime':start_time,'projectName':project_name,'storyDetails':sd}, f, indent=2)
" "$phase" "$active_agent" "$story_id" "$story_title" "$event" "$STATUS_PATH" "$PRD_PATH" "$PROJECT_NAME_VAR" "$CURRENT_ITERATION" "$MAX_ITERATIONS" "$LOOP_START_TIME" 2>/dev/null || true
}

start_dashboard() {
    if [ "$NO_DASHBOARD" = true ]; then return; fi
    if [ -f "$SCRIPT_DIR/.dashboard-pid" ]; then
        kill "$(cat "$SCRIPT_DIR/.dashboard-pid")" 2>/dev/null || true
    fi
    python3 -m http.server "$DASHBOARD_PORT" --directory "$PROJECT_ROOT" &>/dev/null &
    SERVER_PID=$!
    echo "$SERVER_PID" > "$SCRIPT_DIR/.dashboard-pid"
    write_step "Dashboard server started on port $DASHBOARD_PORT"
    sleep 1
    if command -v xdg-open &>/dev/null; then
        xdg-open "http://localhost:$DASHBOARD_PORT/dashboard/" &>/dev/null &
    elif command -v open &>/dev/null; then
        open "http://localhost:$DASHBOARD_PORT/dashboard/"
    fi
    write_step "Dashboard opened in browser"
}

stop_dashboard() {
    if [ -n "$SERVER_PID" ]; then
        kill "$SERVER_PID" 2>/dev/null || true
        rm -f "$SCRIPT_DIR/.dashboard-pid"
        write_step "Dashboard server stopped"
    fi
}

trap stop_dashboard EXIT

# --- Startup ----------------------------------------------------------

echo ""
echo -e "\033[35m+----------------------------------------------+\033[0m"
echo -e "\033[35m|          SPRINGFIELD - Starting Up           |\033[0m"
echo -e "\033[35m|  Decomposer > Architect > Builder > Reviewer |\033[0m"
echo -e "\033[35m+----------------------------------------------+\033[0m"
echo -e "\033[37m  Project Root   : $PROJECT_ROOT\033[0m"
echo -e "\033[37m  Max Iterations : $MAX_ITERATIONS\033[0m"
echo ""

cd "$PROJECT_ROOT"

start_dashboard
write_status "input" "" "" "" "Springfield starting up"

# --- RESUME CHECK -----------------------------------------------------

NEEDS_DECOMPOSER=true
NEEDS_ARCHITECT=true

if has_prd_with_stories; then
    NEEDS_DECOMPOSER=false
fi

if [ -f "$ARCHITECTURE_PATH" ]; then
    NEEDS_ARCHITECT=false
fi

if [ "$NEEDS_DECOMPOSER" = false ]; then
    PROJECT_NAME_VAR=$(python3 -c "import json; print(json.load(open('$PRD_PATH')).get('projectName',''))" 2>/dev/null || echo "")
fi

if [ "$NEEDS_DECOMPOSER" = false ] && [ "$NEEDS_ARCHITECT" = false ]; then
    read -r total passed reviewed blocked remaining <<< "$(get_story_count)"
    write_phase "RESUME" "Existing progress detected" "33"
    write_step "Stories: $total total, $passed passed, $reviewed reviewed, $blocked blocked"
    write_step "Skipping Decomposer and Architect phases"
    write_step "Resuming build loop..."
elif [ "$NEEDS_DECOMPOSER" = false ] && [ "$NEEDS_ARCHITECT" = true ]; then
    write_phase "RESUME" "PRD exists but no architecture plan" "33"
    write_step "Skipping Decomposer, running Architect..."
fi

# --- Verify prompt files exist ---
for pfile in decomposer.md architect.md builder.md reviewer.md; do
    if [ ! -f "$PROMPTS_DIR/$pfile" ]; then
        echo "ERROR: Missing prompt file: $pfile" >&2
        stop_dashboard
        exit 1
    fi
done

# --- PHASE 0: USER INPUT ---------------------------------------------

if [ "$NEEDS_DECOMPOSER" = true ]; then
    write_phase "PHASE 0" "What are we building?" "36"
    
    echo -n "  What do you want to build? (1 sentence): "
    read -r PROJECT_DESCRIPTION
    
    if [ -z "$PROJECT_DESCRIPTION" ]; then
        echo -e "\033[31m  ERROR: You must provide a project description.\033[0m"
        exit 1
    fi
    
    echo -n "  Any reference URLs or docs? (comma-separated, or press Enter to skip): "
    read -r REFERENCE_URLS
    
    echo ""
    write_step "Project: $PROJECT_DESCRIPTION" "37"
    if [ -n "$REFERENCE_URLS" ]; then
        write_step "References: $REFERENCE_URLS" "37"
    fi
    PROJECT_NAME_VAR="$PROJECT_DESCRIPTION"
fi

# --- PHASE 1: DECOMPOSER ---------------------------------------------

if [ "$NEEDS_DECOMPOSER" = true ]; then
    write_phase "PHASE 1" "Decomposer - Researching & generating stories" "32"
    write_status "decomposing" "decomposer" "" "" "Decomposer started"
    
    DECOMPOSER_PROMPT=$(cat "$PROMPTS_DIR/decomposer.md")
    
    USER_INPUT="

## User Input

**Project Description**: $PROJECT_DESCRIPTION
**Reference URLs**: $REFERENCE_URLS
**Project Root**: $PROJECT_ROOT
**Scripts Directory**: $SCRIPT_DIR
"
    
    FULL_PROMPT="${DECOMPOSER_PROMPT}${USER_INPUT}"
    
    write_step "Running Decomposer agent..."
    invoke_claude "$FULL_PROMPT" > /dev/null
    
    if [ ! -f "$PRD_PATH" ]; then
        echo -e "\033[31m  ERROR: Decomposer failed to create prd.json\033[0m"
        exit 1
    fi
    
    read -r total _ _ _ _ <<< "$(get_story_count)"
    if [ "$total" -eq 0 ]; then
        echo -e "\033[31m  ERROR: Decomposer created empty prd.json\033[0m"
        exit 1
    fi
    
    write_step "prd.json created with $total stories" "32"
    write_status "decomposing" "decomposer" "" "" "PRD generated: $total stories"
    echo ""
fi

# --- PHASE 2: ARCHITECT ----------------------------------------------

if [ "$NEEDS_ARCHITECT" = true ]; then
    write_phase "PHASE 2" "Architect - Creating implementation plan" "34"
    write_status "architecting" "architect" "" "" "Architect started"
    
    ARCHITECT_PROMPT=$(cat "$PROMPTS_DIR/architect.md")
    
    write_step "Running Architect agent..."
    invoke_claude "$ARCHITECT_PROMPT" > /dev/null
    
    if [ ! -f "$ARCHITECTURE_PATH" ]; then
        echo -e "\033[31m  ERROR: Architect failed to create architecture.md\033[0m"
        exit 1
    fi
    
    write_step "architecture.md created" "32"
    write_status "architecting" "architect" "" "" "Architecture plan created"
    echo ""
fi

# --- PHASE 3: BUILD LOOP ---------------------------------------------

write_phase "PHASE 3" "Build Loop - Builder + Reviewer" "33"

START_TIME=$(date +%s)
LOOP_START_TIME=$(date +"%Y-%m-%dT%H:%M:%S")

for i in $(seq 1 $MAX_ITERATIONS); do
    CURRENT_ITERATION=$i
    read -r total passed reviewed blocked remaining <<< "$(get_story_count)"
    
    echo ""
    echo -e "\033[33m  +------------------------------------------+\033[0m"
    echo -e "\033[33m  |  Iteration $i of $MAX_ITERATIONS\033[0m"
    echo -e "\033[33m  |  Passed: $passed/$total  Reviewed: $reviewed/$total  Blocked: $blocked\033[0m"
    echo -e "\033[33m  +------------------------------------------+\033[0m"
    echo ""
    
    # Check if all stories are done
    if ! has_unfinished_stories && ! has_unreviewed_stories; then
        break
    fi
    
    # -- BUILDER PASS --
    
    if has_unfinished_stories; then
        NEXT_STORY_ID=$(get_next_story_id)
        if [ -n "$NEXT_STORY_ID" ]; then
            TAG_NAME="springfield-checkpoint-$NEXT_STORY_ID"
            git tag -f "$TAG_NAME" 2>/dev/null || true
            write_step "Git checkpoint: $TAG_NAME"
        fi
        
        NEXT_STORY_TITLE=$(python3 -c "
import json
with open('$PRD_PATH') as f:
    prd = json.load(f)
for s in prd.get('userStories', []):
    if s.get('id') == '$NEXT_STORY_ID':
        print(s.get('title', ''))
        break
" 2>/dev/null)
        
        write_step "BUILDER: Working on next story..." "36"
        write_status "building" "builder" "$NEXT_STORY_ID" "$NEXT_STORY_TITLE" "Builder started $NEXT_STORY_ID"
        
        BUILDER_PROMPT=$(cat "$PROMPTS_DIR/builder.md")
        BUILDER_OUTPUT=$(invoke_claude "$BUILDER_PROMPT")
        
        write_status "building" "builder" "$NEXT_STORY_ID" "$NEXT_STORY_TITLE" "Builder finished $NEXT_STORY_ID"
    fi
    
    # -- REVIEWER PASS --
    
    if has_unreviewed_stories; then
        write_step "REVIEWER: Validating completed work..." "35"
        write_status "reviewing" "reviewer" "" "" "Reviewer started"
        
        REVIEWER_PROMPT=$(cat "$PROMPTS_DIR/reviewer.md")
        invoke_claude "$REVIEWER_PROMPT" > /dev/null
        
        write_status "reviewing" "reviewer" "" "" "Reviewer finished"
    fi
    
    # -- CHECK FOR BLOCKED STORIES (runs every iteration regardless) --
    
    BLOCKED_INFO=$(check_blocked_stories || echo "")
        if [ -n "$BLOCKED_INFO" ]; then
            while IFS='|' read -r sid stitle serror snotes; do
                echo ""
                echo -e "\033[31m  +=========================================+\033[0m"
                echo -e "\033[31m  | STORY FAILED 3 TIMES: $sid\033[0m"
                echo -e "\033[31m  | $stitle\033[0m"
                echo -e "\033[31m  | Last error: $serror\033[0m"
                echo -e "\033[31m  +=========================================+\033[0m"
                echo ""
                
                # Rollback to checkpoint
                TAG_NAME="springfield-checkpoint-$sid"
                if git tag -l "$TAG_NAME" | grep -q .; then
                    write_step "Rolling back to checkpoint: $TAG_NAME" "33"
                    git reset --hard "$TAG_NAME" 2>/dev/null || true
                fi
                
                # Ask user what to do
                echo -e "  What would you like to do?"
                echo -e "  [1] Continue to next story (mark this one blocked)"
                echo -e "  [2] Stop the loop to debug"
                echo -n "  Enter 1 or 2: "
                read -r choice
                
                if [ "$choice" = "2" ]; then
                    echo ""
                    write_step "Stopping loop. Debug the issue, then restart the script to resume." "33"
                    write_step "Story $sid has attempts logged."
                    write_step "Review notes: $snotes"
                    exit 0
                else
                    mark_story_blocked "$sid"
                    write_status "blocked" "" "$sid" "" "Story $sid marked as blocked"
                    write_step "Story $sid marked as blocked. Continuing..." "33"
                fi
            done <<< "$BLOCKED_INFO"
        fi
    fi
    
    echo ""
    write_step "Sleeping 3 seconds before next iteration..."
    sleep 3
done

# --- PHASE 4: COMPLETION ---------------------------------------------

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
DURATION_MIN=$((DURATION / 60))
DURATION_SEC=$((DURATION % 60))

read -r total passed reviewed blocked remaining <<< "$(get_story_count)"

echo ""
echo -e "\033[32m+----------------------------------------------+\033[0m"
echo -e "\033[32m|           SPRINGFIELD - COMPLETE             |\033[0m"
echo -e "\033[32m+----------------------------------------------+\033[0m"
echo -e "\033[32m|  Stories Total    : $(printf '%4s' "$total")\033[0m"
echo -e "\033[32m|  Passed           : $(printf '%4s' "$passed")\033[0m"
echo -e "\033[32m|  Reviewed         : $(printf '%4s' "$reviewed")\033[0m"
echo -e "\033[32m|  Blocked          : $(printf '%4s' "$blocked")\033[0m"
echo -e "\033[32m|  Duration         : ${DURATION_MIN}m ${DURATION_SEC}s\033[0m"
echo -e "\033[32m+----------------------------------------------+\033[0m"
echo ""
echo -e "\033[37m  Check commits  : git log --oneline -20\033[0m"
echo -e "\033[37m  Check progress : cat scripts/springfield/progress.txt\033[0m"
echo -e "\033[37m  Check stories  : cat scripts/springfield/prd.json\033[0m"
echo ""

if [ "$blocked" -gt 0 ]; then
    echo -e "\033[33m  WARNING: $blocked stories were blocked. Review them manually.\033[0m"
fi

if [ "$remaining" -gt 0 ]; then
    echo ""
    echo -e "\033[33m  Max iterations reached with $remaining stories remaining.\033[0m"
    echo -e "\033[33m  Run the script again to continue.\033[0m"
    exit 1
fi

write_status "complete" "" "" "" "Springfield finished"
echo -e "\033[37m  Dashboard will close in 30 seconds (or press Ctrl+C)...\033[0m"
sleep 30
exit 0
