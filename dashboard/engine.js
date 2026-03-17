// ============================================================
// SPRINGFIELD VISUAL DASHBOARD ENGINE
// ============================================================

const CONFIG = {
    canvas: { width: 1376, height: 768 },
    pollInterval: 2000,
    statusUrl: '../scripts/springfield/status.json',
    animFPS: 4,
    moveSpeed: 150,

    desks: {
        decomposer: { x: 325, y: 430 },
        architect:   { x: 1005, y: 427 },
        builder:     { x: 325, y: 615 },
        reviewer:    { x: 1005, y: 615 }
    },

    whiteboard: { x: 510, y: 210 },

    corkboard: {
        x: 475, y: 100,
        cols: 5, rows: 3,
        noteSize: 22, gap: 4
    },

    agentColors: {
        decomposer: 'red',
        architect: 'green',
        builder: 'orange',
        reviewer: 'blue'
    },

    sprites: {
        idle:      { cols: 4, rows: 2, xStart: 347, xStride: 215, frameW: 215, yStart: 0,   yStride: 512, frameH: 512 },
        typing:    { cols: 6, rows: 1, xStart: 56,  xStride: 247, frameW: 235, yStart: 271, yStride: 366, frameH: 366 },
        walking:   { cols: 6, rows: 4, xStart: 113, xStride: 171, frameW: 171, yStart: 0,   yStride: 210, frameH: 210 },
        postit:    { cols: 6, rows: 1, xStart: 39,  xStride: 205, frameW: 200, yStart: 210, yStride: 314, frameH: 314 },
        celebrate: { cols: 6, rows: 1, xStart: 133, xStride: 174, frameW: 174, yStart: 75,  yStride: 219, frameH: 219 },
        error:     { cols: 6, rows: 1, xStart: 113, xStride: 275, frameW: 234, yStart: 137, yStride: 357, frameH: 357 }
    },

    displayHeight: {
        idle:      215,
        typing:    112,
        walking:   130,
        postit:    112,
        celebrate: 113,
        error:     112
    }
};

// ============================================================
// ASSET LOADER
// ============================================================

class AssetLoader {
    constructor() {
        this.images = {};
        this.total = 0;
        this.loaded = 0;
    }

    load(key, src) {
        this.total++;
        return new Promise((resolve) => {
            const img = new Image();
            img.onload = () => {
                this.images[key] = img;
                this.loaded++;
                resolve(img);
            };
            img.onerror = () => {
                console.warn('Failed to load:', src);
                this.loaded++;
                resolve(null);
            };
            img.src = src;
        });
    }

    get(key) { return this.images[key] || null; }
    get progress() { return this.total > 0 ? this.loaded / this.total : 0; }
}

// ============================================================
// SPRITE ANIMATOR
// ============================================================

class SpriteAnimator {
    constructor(image, spriteConfig, debugLabel) {
        this.image = image;
        this.cols = spriteConfig.cols;
        this.rows = spriteConfig.rows;
        this.xStart = spriteConfig.xStart || 0;
        this.xStride = spriteConfig.xStride || (image.width / spriteConfig.cols);
        this.frameW = spriteConfig.frameW || this.xStride;
        this.yStart = spriteConfig.yStart || 0;
        this.yStride = spriteConfig.yStride || (image.height / spriteConfig.rows);
        this.frameH = spriteConfig.frameH || this.yStride;
        this.frame = 0;
        this.row = 0;
        this.maxFrames = spriteConfig.cols;
        this.timer = 0;
        this.frameDuration = 1000 / CONFIG.animFPS;
        if (debugLabel) {
            console.log(`[Sprite] ${debugLabel}: img=${image.width}x${image.height} xStart=${this.xStart} xStride=${this.xStride} frameW=${Math.round(this.frameW)} yStride=${Math.round(this.yStride)} frameH=${Math.round(this.frameH)}`);
        }
    }

    setRow(row) {
        if (this.row !== row) {
            this.row = Math.min(row, this.rows - 1);
            this.frame = 0;
            this.timer = 0;
        }
    }

    update(dt) {
        this.timer += dt;
        while (this.timer >= this.frameDuration) {
            this.timer -= this.frameDuration;
            this.frame = (this.frame + 1) % this.maxFrames;
        }
    }

    draw(ctx, x, y, displayH) {
        const displayW = (this.frameW / this.frameH) * displayH;
        const sx = this.xStart + this.frame * this.xStride;
        const sy = this.yStart + this.row * this.yStride;

        ctx.drawImage(
            this.image,
            sx, sy, this.frameW, this.frameH,
            Math.round(x - displayW / 2),
            Math.round(y - displayH),
            Math.round(displayW),
            Math.round(displayH)
        );
    }
}

// ============================================================
// AGENT
// ============================================================

class Agent {
    constructor(name, assets) {
        this.name = name;
        this.color = CONFIG.agentColors[name];
        this.deskPos = { ...CONFIG.desks[name] };
        this.pos = { ...this.deskPos };
        this.targetPos = null;
        this.walkCallback = null;
        this.state = 'idle_front';
        this.timedAnim = null;

        this.animators = {};
        const types = ['idle', 'typing', 'walking', 'postit', 'celebrate', 'error'];
        for (const type of types) {
            const img = assets.get(`${name}_${type}`);
            if (img) {
                const cfg = CONFIG.sprites[type];
                this.animators[type] = new SpriteAnimator(img, cfg, `${name}/${type}`);
            }
        }
    }

    setState(newState) {
        if (this.state === newState) return;
        this.state = newState;
        const anim = this._activeAnimator();
        if (anim) {
            anim.frame = 0;
            anim.timer = 0;
        }
    }

    walkTo(target, callback) {
        this.targetPos = { ...target };
        this.walkCallback = callback || null;
        this.setState('walking');
    }

    walkToDesk(callback) {
        this.walkTo(this.deskPos, callback);
    }

    playTimed(state, durationMs, callback) {
        this.setState(state);
        this.timedAnim = { remaining: durationMs, callback: callback || null };
    }

    _activeAnimator() {
        const map = {
            idle_front: 'idle', idle_back: 'idle',
            typing: 'typing', walking: 'walking',
            postit: 'postit', celebrate: 'celebrate', error: 'error'
        };
        return this.animators[map[this.state]] || this.animators.idle;
    }

    _activeRow() {
        switch (this.state) {
            case 'idle_front': return 0;
            case 'idle_back':  return 1;
            case 'typing':     return 0;
            case 'postit':     return 0;
            case 'celebrate':  return 0;
            case 'error':      return 0;
            case 'walking': {
                if (!this.targetPos) return 3;
                const dx = this.targetPos.x - this.pos.x;
                const dy = this.targetPos.y - this.pos.y;
                if (Math.abs(dx) > Math.abs(dy)) {
                    return dx > 0 ? 0 : 1;
                }
                return dy < 0 ? 2 : 3;
            }
            default: return 0;
        }
    }

    _displayHeight() {
        const map = {
            idle_front: 'idle', idle_back: 'idle',
            typing: 'typing', walking: 'walking',
            postit: 'postit', celebrate: 'celebrate', error: 'error'
        };
        const type = map[this.state] || 'idle';
        return CONFIG.displayHeight[type];
    }

    update(dt) {
        if (this.targetPos) {
            const dx = this.targetPos.x - this.pos.x;
            const dy = this.targetPos.y - this.pos.y;
            const dist = Math.sqrt(dx * dx + dy * dy);
            const step = CONFIG.moveSpeed * (dt / 1000);

            if (dist <= step) {
                this.pos.x = this.targetPos.x;
                this.pos.y = this.targetPos.y;
                this.targetPos = null;
                const cb = this.walkCallback;
                this.walkCallback = null;
                if (cb) cb();
            } else {
                this.pos.x += (dx / dist) * step;
                this.pos.y += (dy / dist) * step;
            }
        }

        if (this.timedAnim) {
            this.timedAnim.remaining -= dt;
            if (this.timedAnim.remaining <= 0) {
                const cb = this.timedAnim.callback;
                this.timedAnim = null;
                if (cb) cb();
            }
        }

        const anim = this._activeAnimator();
        if (anim) {
            anim.setRow(this._activeRow());
            anim.update(dt);
        }
    }

    draw(ctx) {
        const anim = this._activeAnimator();
        if (anim) {
            anim.draw(ctx, this.pos.x, this.pos.y, this._displayHeight());
        }
    }
}

// ============================================================
// STICKY NOTE MANAGER
// ============================================================

class StickyNoteManager {
    constructor(assets) {
        this.notes = [];
        this.imgs = {
            pending:  assets.get('sticky_yellow'),
            active:   assets.get('sticky_blue'),
            passed:   assets.get('sticky_green'),
            reviewed: assets.get('sticky_green'),
            blocked:  assets.get('sticky_red')
        };
    }

    updateFromStories(stories) {
        if (!stories || !Array.isArray(stories)) return;
        const cfg = CONFIG.corkboard;
        this.notes = stories.map((s, i) => {
            const col = i % cfg.cols;
            const row = Math.floor(i / cfg.cols);
            let status = 'pending';
            if (s.blocked) status = 'blocked';
            else if (s.reviewed) status = 'reviewed';
            else if (s.passes) status = 'passed';
            else if (s.active) status = 'active';
            return {
                id: s.id || `US-${i + 1}`,
                status,
                x: cfg.x + col * (cfg.noteSize + cfg.gap),
                y: cfg.y + row * (cfg.noteSize + cfg.gap)
            };
        });
    }

    draw(ctx) {
        for (const note of this.notes) {
            const img = this.imgs[note.status];
            if (img) {
                ctx.drawImage(img, note.x, note.y, CONFIG.corkboard.noteSize, CONFIG.corkboard.noteSize);
            }
        }
    }
}

// ============================================================
// DASHBOARD CONTROLLER
// ============================================================

class Dashboard {
    constructor() {
        this.canvas = document.getElementById('scene');
        this.ctx = this.canvas.getContext('2d');
        this.canvas.width = CONFIG.canvas.width;
        this.canvas.height = CONFIG.canvas.height;

        this.assets = new AssetLoader();
        this.agents = {};
        this.stickyNotes = null;
        this.bgImage = null;
        this.lastTime = 0;
        this.prevStatus = null;
        this.fontLoaded = false;

        this.demoMode = false;
        this.demoTimer = 0;
        this.demoStep = 0;
        this.debugBoxes = false;

        this.init();
    }

    async init() {
        await this.loadAssets();

        document.getElementById('loading-screen').classList.add('hidden');
        document.getElementById('dashboard').classList.remove('hidden');

        this.bgImage = this.assets.get('background');
        this.setupAgents();
        this.stickyNotes = new StickyNoteManager(this.assets);
        this.resizeCanvas();

        window.addEventListener('resize', () => this.resizeCanvas());
        document.addEventListener('keydown', (e) => {
            if (e.key === 'd' || e.key === 'D') {
                this.demoMode = !this.demoMode;
                this.demoTimer = 0;
                this.demoStep = 0;
                if (this.demoMode) this.startDemoPhase();
            }
            if (e.key === 'b' || e.key === 'B') {
                this.debugBoxes = !this.debugBoxes;
                console.log('Debug boxes:', this.debugBoxes);
            }
        });

        this.lastTime = performance.now();
        requestAnimationFrame((t) => this.loop(t));
        this.pollStatus();
    }

    async loadAssets() {
        const promises = [];
        const loadingFill = document.getElementById('loading-bar-fill');

        promises.push(this.assets.load('background', 'background.png'));

        const agentNames = ['decomposer', 'architect', 'builder', 'reviewer'];
        const types = ['idle', 'typing', 'walking', 'postit', 'celebrate', 'error'];
        for (const agent of agentNames) {
            for (const type of types) {
                const color = CONFIG.agentColors[agent];
                const file = `assets/${agent}/${type}_${color}.png`;
                promises.push(this.assets.load(`${agent}_${type}`, file));
            }
        }

        const stickyColors = ['yellow', 'green', 'blue', 'red'];
        for (const c of stickyColors) {
            promises.push(this.assets.load(`sticky_${c}`, `assets/ui/${c}.png`));
        }

        const updateProgress = setInterval(() => {
            loadingFill.style.width = (this.assets.progress * 100) + '%';
        }, 100);

        await Promise.all(promises);
        clearInterval(updateProgress);
        loadingFill.style.width = '100%';
        await new Promise(r => setTimeout(r, 300));
    }

    setupAgents() {
        for (const name of ['decomposer', 'architect', 'builder', 'reviewer']) {
            this.agents[name] = new Agent(name, this.assets);
        }
    }

    resizeCanvas() {
        const container = document.getElementById('canvas-container');
        const cw = container.clientWidth - 16;
        const ch = container.clientHeight - 16;
        const aspect = CONFIG.canvas.width / CONFIG.canvas.height;
        let w, h;
        if (cw / ch > aspect) {
            h = ch;
            w = h * aspect;
        } else {
            w = cw;
            h = w / aspect;
        }
        this.canvas.style.width = Math.round(w) + 'px';
        this.canvas.style.height = Math.round(h) + 'px';
    }

    // ---- Status Polling ----

    async pollStatus() {
        if (!this.demoMode) {
            try {
                const resp = await fetch(CONFIG.statusUrl + '?t=' + Date.now());
                if (resp.ok) {
                    const status = await resp.json();
                    this.onStatusUpdate(status);
                }
            } catch (_) {
                // status.json not yet available
            }
        }
        setTimeout(() => this.pollStatus(), CONFIG.pollInterval);
    }

    onStatusUpdate(status) {
        const prev = this.prevStatus;

        this.updateUI(status);

        if (status.storyDetails) {
            this.stickyNotes.updateFromStories(status.storyDetails);
        }

        const phaseChanged = !prev || prev.phase !== status.phase || prev.activeAgent !== status.activeAgent;
        if (phaseChanged) {
            this.applyPhase(status);
        }

        if (prev && status.stories && prev.stories) {
            if (status.stories.passed > prev.stories.passed) {
                this.triggerBuilderComplete();
            }
            if (status.stories.reviewed > prev.stories.reviewed) {
                this.triggerReviewWhiteboard();
            }
        }

        const newStory = status.currentStory && prev && prev.currentStory &&
            status.currentStory.id !== prev.currentStory.id && status.activeAgent === 'builder';
        const firstStory = status.currentStory && !prev && status.activeAgent === 'builder';
        const firstStoryForBuilder = status.currentStory && prev && !prev.currentStory && status.activeAgent === 'builder';
        if (newStory || firstStory || firstStoryForBuilder) {
            this.triggerBuilderStart();
        }

        const phaseJustChanged = !prev || prev.phase !== status.phase;
        if (phaseJustChanged) {
            if (status.phase === 'decomposing') {
                this.triggerAgentWhiteboard('decomposer');
            } else if (status.phase === 'architecting') {
                this.triggerAgentWhiteboard('architect');
            }
        }

        this.prevStatus = JSON.parse(JSON.stringify(status));
    }

    applyPhase(status) {
        for (const agent of Object.values(this.agents)) {
            if (!agent.targetPos && !agent.timedAnim) {
                agent.pos = { ...agent.deskPos };
                agent.setState('idle_front');
            }
        }

        if (status.phase === 'complete') {
            for (const agent of Object.values(this.agents)) {
                agent.targetPos = null;
                agent.timedAnim = null;
                agent.pos = { ...agent.deskPos };
                agent.setState('celebrate');
            }
            return;
        }

        if (status.activeAgent && this.agents[status.activeAgent]) {
            const agent = this.agents[status.activeAgent];
            if (!agent.targetPos && !agent.timedAnim) {
                agent.setState('typing');
            }
        }
    }

    triggerReviewWhiteboard() {
        const reviewer = this.agents.reviewer;
        if (reviewer && !reviewer.targetPos && !reviewer.timedAnim) {
            reviewer.walkTo(CONFIG.whiteboard, () => {
                reviewer.playTimed('celebrate', 2500, () => {
                    reviewer.walkToDesk(() => {
                        reviewer.setState('idle_front');
                    });
                });
            });
        }
    }

    triggerBuilderStart() {
        const builder = this.agents.builder;
        if (builder && !builder.targetPos && !builder.timedAnim) {
            builder.walkTo(CONFIG.whiteboard, () => {
                builder.playTimed('postit', 1200, () => {
                    builder.walkToDesk(() => {
                        builder.setState('typing');
                    });
                });
            });
        }
    }

    triggerBuilderComplete() {
        const builder = this.agents.builder;
        if (builder && !builder.targetPos && !builder.timedAnim) {
            builder.walkTo(CONFIG.whiteboard, () => {
                builder.playTimed('postit', 1800, () => {
                    builder.playTimed('celebrate', 1500, () => {
                        builder.walkToDesk(() => {
                            builder.setState('idle_front');
                        });
                    });
                });
            });
        }
    }

    triggerAgentWhiteboard(agentName) {
        const agent = this.agents[agentName];
        if (agent && !agent.targetPos && !agent.timedAnim) {
            agent.walkTo(CONFIG.whiteboard, () => {
                agent.playTimed('postit', 1500, () => {
                    agent.walkToDesk(() => {
                        agent.setState('typing');
                    });
                });
            });
        }
    }

    // ---- UI Updates ----

    updateUI(status) {
        document.getElementById('project-name').textContent = status.projectName || '';
        document.getElementById('iteration-counter').textContent =
            status.iteration ? `Iteration ${status.iteration} / ${status.maxIterations || 40}` : '';

        const phaseNames = {
            input:        'WAITING FOR INPUT',
            decomposing:  'DECOMPOSER RESEARCHING',
            architecting: 'ARCHITECT PLANNING',
            building:     'BUILDER IMPLEMENTING',
            reviewing:    'REVIEWER CHECKING',
            complete:     'ALL STORIES COMPLETE!',
            blocked:      'STORY BLOCKED',
            error:        'ERROR ENCOUNTERED'
        };

        let phaseText = phaseNames[status.phase] || status.phase || 'Waiting for Springfield...';
        if (status.currentStory && status.currentStory.id) {
            phaseText += '  -  ' + status.currentStory.id;
            if (status.currentStory.title) {
                phaseText += ': ' + status.currentStory.title;
            }
        }
        document.getElementById('phase-label').textContent = phaseText;

        if (status.stories) {
            const total = status.stories.total || 1;
            const done = status.stories.reviewed || 0;
            const pct = Math.min(100, Math.round((done / total) * 100));
            document.getElementById('progress-bar-fill').style.width = pct + '%';
            document.getElementById('progress-text').textContent = `${done} / ${total} stories`;
            document.getElementById('story-stats').textContent =
                `Passed: ${status.stories.passed || 0}  |  ` +
                `Reviewed: ${status.stories.reviewed || 0}  |  ` +
                `Blocked: ${status.stories.blocked || 0}  |  ` +
                `Remaining: ${status.stories.remaining || 0}`;
        }

        if (status.eventLog && status.eventLog.length > 0) {
            const logEl = document.getElementById('event-log');
            logEl.innerHTML = status.eventLog
                .slice(-12)
                .reverse()
                .map(e => `<div class="event-entry"><span class="event-time">${e.time || ''}</span>${e.event || ''}</div>`)
                .join('');
        }
    }

    // ---- Demo Mode ----

    startDemoPhase() {
        const phases = [
            { phase: 'decomposing', agent: 'decomposer' },
            { phase: 'architecting', agent: 'architect' },
            { phase: 'building', agent: 'builder' },
            { phase: 'reviewing', agent: 'reviewer' }
        ];
        const p = phases[this.demoStep % phases.length];

        const demoStories = [];
        for (let i = 0; i < 8; i++) {
            const passed = i < this.demoStep;
            const reviewed = i < Math.max(0, this.demoStep - 1);
            const active = i === this.demoStep;
            demoStories.push({
                id: `US-00${i + 1}`,
                title: `Demo Story ${i + 1}`,
                passes: passed,
                reviewed: reviewed,
                blocked: false,
                active: active
            });
        }

        this.applyPhase({ phase: p.phase, activeAgent: p.agent });
        const status = {
            phase: p.phase,
            activeAgent: p.agent,
            projectName: 'Demo Project',
            iteration: this.demoStep + 1,
            maxIterations: 40,
            stories: { total: 8, passed: this.demoStep, reviewed: Math.max(0, this.demoStep - 1), blocked: 0, remaining: 8 - this.demoStep },
            currentStory: { id: `US-00${(this.demoStep % 8) + 1}`, title: 'Demo Story' },
            storyDetails: demoStories,
            eventLog: [
                { time: '00:00', event: 'Demo mode active - press D to exit' },
                { time: '00:01', event: `${p.agent} started ${p.phase}` }
            ]
        };
        if (this.stickyNotes) {
            this.stickyNotes.updateFromStories(status.storyDetails);
        }
        this.updateUI(status);
    }

    updateDemo(dt) {
        this.demoTimer += dt;
        if (this.demoTimer >= 5000) {
            this.demoTimer = 0;

            const currentPhase = ['decomposing', 'architecting', 'building', 'reviewing'][this.demoStep % 4];

            if (currentPhase === 'decomposing') {
                this.triggerAgentWhiteboard('decomposer');
            }
            if (currentPhase === 'architecting') {
                this.triggerAgentWhiteboard('architect');
            }
            if (currentPhase === 'building') {
                this.triggerBuilderComplete();
            }
            if (currentPhase === 'reviewing') {
                this.triggerReviewWhiteboard();
            }

            this.demoStep = (this.demoStep + 1) % 8;
            this.startDemoPhase();
        }
    }

    // ---- Main Loop ----

    loop(timestamp) {
        const dt = Math.min(timestamp - this.lastTime, 100);
        this.lastTime = timestamp;

        for (const agent of Object.values(this.agents)) {
            agent.update(dt);
        }

        if (this.demoMode) {
            this.updateDemo(dt);
        }

        this.render();
        requestAnimationFrame((t) => this.loop(t));
    }

    render() {
        const ctx = this.ctx;
        ctx.clearRect(0, 0, CONFIG.canvas.width, CONFIG.canvas.height);

        if (this.bgImage) {
            ctx.drawImage(this.bgImage, 0, 0, CONFIG.canvas.width, CONFIG.canvas.height);
        }

        if (this.stickyNotes) {
            this.stickyNotes.draw(ctx);
        }

        const sorted = Object.values(this.agents).sort((a, b) => a.pos.y - b.pos.y);
        for (const agent of sorted) {
            agent.draw(ctx);
        }

        this.drawAgentLabels(ctx);

        if (this.debugBoxes) {
            this.drawDebugOverlay(ctx);
        }
    }

    drawDebugOverlay(ctx) {
        ctx.strokeStyle = '#ff0000';
        ctx.lineWidth = 1;
        for (const [name, agent] of Object.entries(this.agents)) {
            const anim = agent._activeAnimator();
            if (!anim) continue;
            const dh = agent._displayHeight();
            const dw = (anim.frameW / anim.frameH) * dh;
            const dx = Math.round(agent.pos.x - dw / 2);
            const dy = Math.round(agent.pos.y - dh);
            ctx.strokeRect(dx, dy, Math.round(dw), Math.round(dh));

            ctx.fillStyle = '#ff0000';
            ctx.fillRect(agent.pos.x - 3, agent.pos.y - 3, 6, 6);

            ctx.font = '8px monospace';
            ctx.textAlign = 'left';
            ctx.fillText(`${name} (${Math.round(agent.pos.x)},${Math.round(agent.pos.y)})`, dx, dy - 4);
            const srcX = anim.xStart + anim.frame * anim.xStride;
            const srcY = anim.yStart + anim.row * anim.yStride;
            ctx.fillText(`frame:${anim.frame} row:${anim.row} src:${Math.round(srcX)},${Math.round(srcY)} ${Math.round(anim.frameW)}x${Math.round(anim.frameH)}`, dx, dy - 14);
        }

        ctx.strokeStyle = '#00ff00';
        for (const [name, pos] of Object.entries(CONFIG.desks)) {
            ctx.beginPath();
            ctx.moveTo(pos.x - 10, pos.y);
            ctx.lineTo(pos.x + 10, pos.y);
            ctx.moveTo(pos.x, pos.y - 10);
            ctx.lineTo(pos.x, pos.y + 10);
            ctx.stroke();
            ctx.fillStyle = '#00ff00';
            ctx.font = '8px monospace';
            ctx.textAlign = 'center';
            ctx.fillText(name, pos.x, pos.y + 18);
        }
    }

    drawAgentLabels(ctx) {
        const labelColors = {
            decomposer: '#ff6666',
            architect:  '#66ff88',
            builder:    '#ffbb66',
            reviewer:   '#66aaff'
        };

        ctx.textAlign = 'center';
        ctx.textBaseline = 'top';

        for (const [name, agent] of Object.entries(this.agents)) {
            const label = name.charAt(0).toUpperCase() + name.slice(1);
            const x = agent.pos.x;
            const y = agent.pos.y + 4;

            ctx.font = '10px "Press Start 2P", monospace';
            ctx.fillStyle = '#000000';
            ctx.fillText(label, x + 1, y + 1);
            ctx.fillStyle = labelColors[name];
            ctx.fillText(label, x, y);
        }
    }
}

// ============================================================
// INIT
// ============================================================

window.addEventListener('load', () => {
    document.fonts.ready.then(() => {
        new Dashboard();
    });
});
