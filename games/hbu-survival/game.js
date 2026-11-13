(() => {
  "use strict";

  const canvas = document.getElementById("game");
  const ctx = canvas.getContext("2d");
  const W = canvas.width;
  const H = canvas.height;
  const TILE = 48;
  const WORLD_W = 2400;
  const WORLD_H = 1800;

  const ui = {
    day: document.getElementById("dayLabel"),
    health: document.getElementById("healthValue"),
    hunger: document.getElementById("hungerValue"),
    stamina: document.getElementById("staminaValue"),
    healthBar: document.getElementById("healthBar"),
    hungerBar: document.getElementById("hungerBar"),
    staminaBar: document.getElementById("staminaBar"),
    wood: document.getElementById("woodCount"),
    stone: document.getElementById("stoneCount"),
    berries: document.getElementById("berryCount"),
    itemCount: document.getElementById("itemCount"),
    coordinates: document.getElementById("coordinates"),
    objective: document.getElementById("objectiveText"),
    toast: document.getElementById("toast"),
    start: document.getElementById("startOverlay"),
    pause: document.getElementById("pauseOverlay"),
    gameOver: document.getElementById("gameOverOverlay"),
    finalStats: document.getElementById("finalStats"),
    eat: document.getElementById("eatButton"),
    clock: document.getElementById("clock")
  };

  const images = {};
  const imagePaths = {
    player: "assets/player.png",
    bush: "assets/bush.png",
    rock: "assets/rock.png",
    tree: "assets/tree.png"
  };

  const state = {
    started: false,
    paused: false,
    over: false,
    sound: false,
    lastTime: 0,
    elapsed: 0,
    day: 1,
    toastTimer: 0,
    player: { x: WORLD_W / 2, y: WORLD_H / 2, speed: 190, stamina: 100, hunger: 100, health: 100 },
    inventory: { wood: 0, stone: 0, berries: 0 },
    keys: Object.create(null),
    resources: [],
    camera: { x: 0, y: 0 }
  };

  function loadImage(key, src) {
    return new Promise((resolve) => {
      const img = new Image();
      img.onload = () => { images[key] = img; resolve(); };
      img.onerror = () => resolve();
      img.src = src;
    });
  }

  function seededRandom(seed) {
    let value = seed >>> 0;
    return () => {
      value = (value * 1664525 + 1013904223) >>> 0;
      return value / 4294967296;
    };
  }

  function createWorld() {
    const random = seededRandom(918273);
    state.resources = [];
    const kinds = ["tree", "tree", "tree", "bush", "bush", "rock"];
    for (let i = 0; i < 115; i++) {
      const kind = kinds[Math.floor(random() * kinds.length)];
      let x = 70 + random() * (WORLD_W - 140);
      let y = 70 + random() * (WORLD_H - 140);
      if (Math.hypot(x - state.player.x, y - state.player.y) < 180) {
        x += x < WORLD_W / 2 ? -230 : 230;
        y += y < WORLD_H / 2 ? -180 : 180;
      }
      state.resources.push({ id: i, kind, x, y, collected: false, size: kind === "tree" ? 66 : kind === "bush" ? 42 : 37 });
    }
  }

  function showToast(message) {
    ui.toast.textContent = message;
    ui.toast.classList.add("show");
    state.toastTimer = 1.7;
  }

  function updateUI() {
    const p = state.player;
    const inv = state.inventory;
    ui.day.textContent = `DAY ${state.day}`;
    ui.health.textContent = `${Math.round(p.health)}%`;
    ui.hunger.textContent = `${Math.round(p.hunger)}%`;
    ui.stamina.textContent = `${Math.round(p.stamina)}%`;
    ui.healthBar.style.width = `${p.health}%`;
    ui.hungerBar.style.width = `${p.hunger}%`;
    ui.staminaBar.style.width = `${p.stamina}%`;
    ui.wood.textContent = inv.wood;
    ui.stone.textContent = inv.stone;
    ui.berries.textContent = inv.berries;
    ui.itemCount.textContent = `${inv.wood + inv.stone + inv.berries} ITEMS`;
    ui.eat.disabled = inv.berries <= 0 || p.hunger >= 100 || state.over;
    ui.coordinates.textContent = `X: ${Math.round(p.x)} · Y: ${Math.round(p.y)}`;
    ui.clock.textContent = formatTime(state.elapsed);
    if (p.hunger < 25) ui.objective.textContent = "Hunger is low — find berries!";
    else if (inv.wood + inv.stone < 5) ui.objective.textContent = "Gather wood and stone";
    else ui.objective.textContent = "Keep exploring and survive";
  }

  function formatTime(seconds) {
    const total = Math.floor(seconds);
    return `${String(Math.floor(total / 60)).padStart(2, "0")}:${String(total % 60).padStart(2, "0")}`;
  }

  function drawGround() {
    ctx.fillStyle = "#315d39";
    ctx.fillRect(0, 0, W, H);
    const startX = Math.floor(state.camera.x / TILE) * TILE;
    const startY = Math.floor(state.camera.y / TILE) * TILE;
    for (let y = startY; y < state.camera.y + H + TILE; y += TILE) {
      for (let x = startX; x < state.camera.x + W + TILE; x += TILE) {
        const gx = Math.floor(x / TILE);
        const gy = Math.floor(y / TILE);
        const hash = Math.abs((gx * 73856093) ^ (gy * 19349663)) % 100;
        ctx.fillStyle = hash < 12 ? "#35633d" : hash < 19 ? "#2e5836" : "#315d39";
        ctx.fillRect(x - state.camera.x, y - state.camera.y, TILE, TILE);
        if (hash < 8) {
          ctx.fillStyle = "#6b9852";
          ctx.fillRect(x - state.camera.x + 12, y - state.camera.y + 17, 3, 3);
          ctx.fillRect(x - state.camera.x + 29, y - state.camera.y + 33, 2, 2);
        }
      }
    }
  }

  function drawResource(resource) {
    if (resource.collected) return;
    const img = images[resource.kind];
    const x = resource.x - state.camera.x;
    const y = resource.y - state.camera.y;
    if (x < -100 || y < -100 || x > W + 100 || y > H + 100) return;
    if (img) {
      const size = resource.kind === "tree" ? 86 : resource.kind === "bush" ? 62 : 58;
      ctx.drawImage(img, x - size / 2, y - size / 2, size, size);
    }
  }

  function drawPlayer() {
    const p = state.player;
    const img = images.player;
    const x = p.x - state.camera.x;
    const y = p.y - state.camera.y;
    ctx.fillStyle = "#10231666";
    ctx.beginPath();
    ctx.ellipse(x, y + 17, 13, 6, 0, 0, Math.PI * 2);
    ctx.fill();
    if (img) ctx.drawImage(img, x - 24, y - 34, 48, 48);
    else {
      ctx.fillStyle = "#f0c17b";
      ctx.fillRect(x - 10, y - 18, 20, 20);
      ctx.fillStyle = "#163bce";
      ctx.fillRect(x - 10, y + 2, 20, 20);
    }
  }

  function drawNight() {
    const phase = (state.elapsed % 150) / 150;
    const darkness = phase < .48 ? 0 : Math.min(.62, (phase - .48) * 1.2);
    if (darkness > 0) {
      ctx.fillStyle = `rgba(5, 12, 25, ${darkness})`;
      ctx.fillRect(0, 0, W, H);
    }
  }

  function render() {
    const p = state.player;
    state.camera.x = Math.max(0, Math.min(WORLD_W - W, p.x - W / 2));
    state.camera.y = Math.max(0, Math.min(WORLD_H - H, p.y - H / 2));
    drawGround();
    const visible = state.resources.filter(r => !r.collected);
    visible.sort((a, b) => a.y - b.y);
    for (const resource of visible) drawResource(resource);
    drawPlayer();
    drawNight();
  }

  function nearestResource() {
    const p = state.player;
    let nearest = null;
    let distance = Infinity;
    for (const resource of state.resources) {
      if (resource.collected) continue;
      const d = Math.hypot(resource.x - p.x, resource.y - p.y);
      if (d < distance) {
        distance = d;
        nearest = resource;
      }
    }
    return distance <= 78 ? nearest : null;
  }

  function gather() {
    if (!state.started || state.paused || state.over) return;
    const resource = nearestResource();
    if (!resource) {
      showToast("Nothing nearby to gather");
      return;
    }
    resource.collected = true;
    if (resource.kind === "tree") {
      const amount = 2 + Math.floor(Math.random() * 3);
      state.inventory.wood += amount;
      showToast(`Collected ${amount} wood`);
    } else if (resource.kind === "rock") {
      const amount = 1 + Math.floor(Math.random() * 3);
      state.inventory.stone += amount;
      showToast(`Collected ${amount} stone`);
    } else {
      const amount = 2 + Math.floor(Math.random() * 3);
      state.inventory.berries += amount;
      showToast(`Collected ${amount} berries`);
    }
    updateUI();
  }

  function eatBerries() {
    if (state.inventory.berries <= 0) {
      showToast("You don't have any berries");
      return;
    }
    if (state.player.hunger >= 100) {
      showToast("You're not hungry right now");
      return;
    }
    state.inventory.berries--;
    state.player.hunger = Math.min(100, state.player.hunger + 25);
    showToast("Ate berries · +25 hunger");
    updateUI();
  }

  function endGame() {
    state.over = true;
    state.paused = false;
    ui.pause.classList.add("hidden");
    ui.gameOver.classList.remove("hidden");
    const days = Math.max(1, state.day);
    ui.finalStats.textContent = `You survived ${days} ${days === 1 ? "day" : "days"} and collected ${state.inventory.wood + state.inventory.stone + state.inventory.berries} items.`;
    updateUI();
  }

  function update(delta) {
    if (!state.started || state.paused || state.over) return;
    const p = state.player;
    const keys = state.keys;
    let dx = 0;
    let dy = 0;
    if (keys.w || keys.ArrowUp) dy -= 1;
    if (keys.s || keys.ArrowDown) dy += 1;
    if (keys.a || keys.ArrowLeft) dx -= 1;
    if (keys.d || keys.ArrowRight) dx += 1;
    const moving = dx !== 0 || dy !== 0;
    const running = moving && keys.Shift && p.stamina > 1;
    if (moving) {
      const length = Math.hypot(dx, dy);
      dx /= length;
      dy /= length;
      const speed = running ? p.speed * 1.65 : p.speed;
      p.x = Math.max(30, Math.min(WORLD_W - 30, p.x + dx * speed * delta));
      p.y = Math.max(30, Math.min(WORLD_H - 30, p.y + dy * speed * delta));
    }
    if (running) p.stamina = Math.max(0, p.stamina - 28 * delta);
    else p.stamina = Math.min(100, p.stamina + 17 * delta);

    p.hunger = Math.max(0, p.hunger - .42 * delta);
    if (p.hunger <= 0) p.health = Math.max(0, p.health - 4 * delta);
    else p.health = Math.min(100, p.health + .12 * delta);

    state.elapsed += delta;
    state.day = Math.floor(state.elapsed / 75) + 1;
    if (p.health <= 0) endGame();
    if (state.toastTimer > 0) {
      state.toastTimer -= delta;
      if (state.toastTimer <= 0) ui.toast.classList.remove("show");
    }
    updateUI();
  }

  function frame(timestamp) {
    const delta = Math.min(.05, (timestamp - (state.lastTime || timestamp)) / 1000);
    state.lastTime = timestamp;
    update(delta);
    render();
    requestAnimationFrame(frame);
  }

  function startGame() {
    state.started = true;
    state.paused = false;
    ui.start.classList.add("hidden");
    ui.pause.classList.add("hidden");
    updateUI();
  }

  function togglePause() {
    if (!state.started || state.over) return;
    state.paused = !state.paused;
    ui.pause.classList.toggle("hidden", !state.paused);
    document.getElementById("pauseButton").textContent = state.paused ? "▶" : "Ⅱ";
  }

  function restart() {
    state.started = false;
    state.paused = false;
    state.over = false;
    state.elapsed = 0;
    state.day = 1;
    state.player = { x: WORLD_W / 2, y: WORLD_H / 2, speed: 190, stamina: 100, hunger: 100, health: 100 };
    state.inventory = { wood: 0, stone: 0, berries: 0 };
    state.keys = Object.create(null);
    createWorld();
    ui.gameOver.classList.add("hidden");
    ui.pause.classList.add("hidden");
    ui.start.classList.remove("hidden");
    document.getElementById("pauseButton").textContent = "Ⅱ";
    updateUI();
    render();
  }

  window.addEventListener("keydown", (event) => {
    const key = event.key.length === 1 ? event.key.toLowerCase() : event.key;
    if (["ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight", " "].includes(event.key)) event.preventDefault();
    state.keys[key] = true;
    if (event.repeat) return;
    if (key === "e") gather();
    if (key === "f") eatBerries();
    if (key === "Escape") togglePause();
  });
  window.addEventListener("keyup", (event) => {
    const key = event.key.length === 1 ? event.key.toLowerCase() : event.key;
    state.keys[key] = false;
  });
  window.addEventListener("blur", () => { state.keys = Object.create(null); });
  document.getElementById("startButton").addEventListener("click", startGame);
  document.getElementById("resumeButton").addEventListener("click", togglePause);
  document.getElementById("pauseButton").addEventListener("click", togglePause);
  document.getElementById("restartButton").addEventListener("click", restart);
  document.getElementById("eatButton").addEventListener("click", eatBerries);
  document.getElementById("soundButton").addEventListener("click", () => {
    state.sound = !state.sound;
    document.getElementById("soundButton").textContent = state.sound ? "♫" : "♪";
    showToast(state.sound ? "Sound setting enabled" : "Sound setting disabled");
  });

  Promise.all(Object.entries(imagePaths).map(([key, path]) => loadImage(key, path))).then(() => {
    createWorld();
    updateUI();
    render();
    requestAnimationFrame(frame);
  });
})();
