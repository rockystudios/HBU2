(() => {
  "use strict";

  const SUPABASE_URL = "https://xvkjvuxhawlljakfkllu.supabase.co";
  const SUPABASE_KEY = "sb_publishable_uyxd5lS77wdXpD56QF_lgg_zaujLjZZ";
  const TILE = 32;
  const WORLD_TILES = 72;
  const WORLD_SIZE = TILE * WORLD_TILES;
  const COLORS = ["#f4d35e", "#8ecae6", "#ff8fab", "#cdb4db", "#b7e4c7", "#f4a261"];
  const $ = id => document.getElementById(id);

  let client = null;
  let channel = null;
  let running = false;
  let animationFrame = 0;
  let lastFrame = 0;
  let lastBroadcast = 0;
  let currentRoom = "";
  let username = "Guest";
  let playerId = "";
  let playerColor = COLORS[0];
  let canvas, ctx;
  let width = 800, height = 500;
  let player = { x: WORLD_SIZE / 2, y: WORLD_SIZE / 2, speed: 175, wood: 0, stone: 0, berries: 0, health: 100 };
  let remotePlayers = new Map();
  let resources = [];
  let keys = new Set();
  let lastInteract = 0;
  let statusTimer = 0;
  let gameStarted = false;
  let touchVector = { x: 0, y: 0 };

  function setStatus(message, bad = false) {
    const el = $("hbu-survival-status");
    if (!el) return;
    el.textContent = message;
    el.classList.toggle("is-error", bad);
  }

  function roomCode() {
    return Math.random().toString(36).slice(2, 8).toUpperCase();
  }

  function seededRandom(seed) {
    let value = seed >>> 0;
    return () => {
      value = (value * 1664525 + 1013904223) >>> 0;
      return value / 4294967296;
    };
  }

  function generateWorld(seedText) {
    let seed = 0;
    for (const char of seedText) seed = (seed * 31 + char.charCodeAt(0)) >>> 0;
    const random = seededRandom(seed || 1);
    resources = [];
    for (let i = 0; i < 330; i += 1) {
      const x = Math.floor(random() * WORLD_TILES) * TILE + TILE / 2;
      const y = Math.floor(random() * WORLD_TILES) * TILE + TILE / 2;
      if (Math.hypot(x - WORLD_SIZE / 2, y - WORLD_SIZE / 2) < 110) continue;
      const roll = random();
      resources.push({
        id: `${seed}-${i}`,
        x, y,
        type: roll < 0.52 ? "tree" : roll < 0.82 ? "rock" : "berry",
        amount: roll < 0.52 ? 3 : roll < 0.82 ? 2 : 2,
        alive: true
      });
    }
  }

  function resizeCanvas() {
    if (!canvas) return;
    const rect = canvas.getBoundingClientRect();
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    width = Math.max(320, rect.width);
    height = Math.max(260, rect.height);
    canvas.width = Math.floor(width * dpr);
    canvas.height = Math.floor(height * dpr);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  }

  function drawTile(x, y, sx, sy, color) {
    ctx.fillStyle = color;
    ctx.fillRect(sx, sy, TILE + 1, TILE + 1);
    const shade = ((x * 17 + y * 29) % 7) * 2;
    ctx.fillStyle = `rgba(255,255,255,${shade / 255})`;
    ctx.fillRect(sx + 3, sy + 4, 3, 3);
  }

  function drawWorld(cameraX, cameraY) {
    const startX = Math.max(0, Math.floor(cameraX / TILE));
    const startY = Math.max(0, Math.floor(cameraY / TILE));
    const endX = Math.min(WORLD_TILES, Math.ceil((cameraX + width) / TILE) + 1);
    const endY = Math.min(WORLD_TILES, Math.ceil((cameraY + height) / TILE) + 1);
    for (let y = startY; y < endY; y += 1) {
      for (let x = startX; x < endX; x += 1) {
        const n = (x * 37 + y * 71 + x * y * 13) % 19;
        const color = n < 3 ? "#72a94f" : n < 6 ? "#79b653" : n < 9 ? "#75ad50" : "#80b95a";
        drawTile(x, y, x * TILE - cameraX, y * TILE - cameraY, color);
      }
    }
    ctx.fillStyle = "#4d9fc5";
    ctx.fillRect(-cameraX, -cameraY, WORLD_SIZE, 10);
    ctx.fillRect(-cameraX, WORLD_SIZE - cameraY - 10, WORLD_SIZE, 10);
    ctx.fillRect(-cameraX, -cameraY, 10, WORLD_SIZE);
    ctx.fillRect(WORLD_SIZE - cameraX - 10, -cameraY, 10, WORLD_SIZE);
  }

  function drawResource(item, cameraX, cameraY) {
    if (!item.alive) return;
    const x = item.x - cameraX;
    const y = item.y - cameraY;
    if (x < -40 || y < -50 || x > width + 40 || y > height + 50) return;
    ctx.save();
    ctx.translate(Math.round(x), Math.round(y));
    if (item.type === "tree") {
      ctx.fillStyle = "#79513a";
      ctx.fillRect(-4, 1, 8, 17);
      ctx.fillStyle = "#285d38";
      ctx.fillRect(-13, -14, 26, 19);
      ctx.fillStyle = "#347849";
      ctx.fillRect(-10, -20, 20, 13);
      ctx.fillStyle = "#4b9853";
      ctx.fillRect(-5, -23, 9, 7);
    } else if (item.type === "rock") {
      ctx.fillStyle = "#737d86";
      ctx.fillRect(-10, -6, 20, 13);
      ctx.fillStyle = "#aab4ba";
      ctx.fillRect(-6, -10, 10, 6);
      ctx.fillStyle = "#56616b";
      ctx.fillRect(2, 2, 7, 4);
    } else {
      ctx.fillStyle = "#347849";
      ctx.fillRect(-7, -4, 14, 9);
      ctx.fillStyle = "#d94f70";
      ctx.fillRect(-7, -8, 5, 5);
      ctx.fillRect(3, -9, 5, 5);
      ctx.fillStyle = "#ffe3a3";
      ctx.fillRect(-1, -4, 4, 4);
    }
    ctx.restore();
  }

  function drawCharacter(x, y, color, name, cameraX, cameraY, isLocal = false) {
    const sx = Math.round(x - cameraX);
    const sy = Math.round(y - cameraY);
    ctx.fillStyle = "rgba(22,35,25,.28)";
    ctx.fillRect(sx - 9, sy + 8, 18, 5);
    ctx.fillStyle = "#3d2a25";
    ctx.fillRect(sx - 7, sy + 4, 5, 8);
    ctx.fillRect(sx + 2, sy + 4, 5, 8);
    ctx.fillStyle = color;
    ctx.fillRect(sx - 9, sy - 8, 18, 15);
    ctx.fillStyle = "#f1c49a";
    ctx.fillRect(sx - 7, sy - 17, 14, 11);
    ctx.fillStyle = "#51352d";
    ctx.fillRect(sx - 8, sy - 19, 16, 5);
    ctx.fillRect(sx - 8, sy - 15, 3, 4);
    ctx.fillStyle = "#30251f";
    ctx.fillRect(sx - 4, sy - 12, 2, 2);
    ctx.fillRect(sx + 3, sy - 12, 2, 2);
    ctx.font = "11px system-ui";
    ctx.textAlign = "center";
    const label = name + (isLocal ? " (you)" : "");
    const labelWidth = ctx.measureText(label).width + 10;
    ctx.fillStyle = "rgba(18,22,17,.78)";
    ctx.fillRect(sx - labelWidth / 2, sy - 34, labelWidth, 15);
    ctx.fillStyle = "#fff";
    ctx.fillText(label, sx, sy - 23);
  }

  function render() {
    if (!running || !ctx) return;
    const cameraX = Math.max(0, Math.min(WORLD_SIZE - width, player.x - width / 2));
    const cameraY = Math.max(0, Math.min(WORLD_SIZE - height, player.y - height / 2));
    ctx.clearRect(0, 0, width, height);
    drawWorld(cameraX, cameraY);
    for (const item of resources) drawResource(item, cameraX, cameraY);
    for (const remote of remotePlayers.values()) {
      if (remote.id !== playerId) drawCharacter(remote.x, remote.y, remote.color || COLORS[1], remote.username || "Player", cameraX, cameraY);
    }
    drawCharacter(player.x, player.y, playerColor, username, cameraX, cameraY, true);
    const near = resources.find(item => item.alive && Math.hypot(item.x - player.x, item.y - player.y) < 43);
    if (near) {
      ctx.fillStyle = "rgba(17,25,17,.8)";
      ctx.fillRect(width / 2 - 91, height - 45, 182, 28);
      ctx.fillStyle = "#fff";
      ctx.font = "12px system-ui";
      ctx.textAlign = "center";
      ctx.fillText(`E  Collect ${near.type}`, width / 2, height - 27);
    }
  }

  function updateHud() {
    $("hbu-survival-wood").textContent = player.wood;
    $("hbu-survival-stone").textContent = player.stone;
    $("hbu-survival-berries").textContent = player.berries;
    $("hbu-survival-health").textContent = `${player.health}%`;
    $("hbu-survival-online").textContent = String(remotePlayers.size + 1);
  }

  function collectResource() {
    const now = performance.now();
    if (now - lastInteract < 250) return;
    lastInteract = now;
    const item = resources.find(resource => resource.alive && Math.hypot(resource.x - player.x, resource.y - player.y) < 43);
    if (!item) return;
    item.amount -= 1;
    if (item.type === "tree") player.wood += 1;
    if (item.type === "rock") player.stone += 1;
    if (item.type === "berry") player.berries += 1;
    if (item.amount <= 0) item.alive = false;
    if (channel) {
      void channel.send({ type: "broadcast", event: "collect", payload: { id: playerId, resourceId: item.id, amount: item.amount } }).catch(() => {});
    }
    updateHud();
  }

  function movePlayer(delta) {
    let dx = (keys.has("d") || keys.has("arrowright") ? 1 : 0) - (keys.has("a") || keys.has("arrowleft") ? 1 : 0) + touchVector.x;
    let dy = (keys.has("s") || keys.has("arrowdown") ? 1 : 0) - (keys.has("w") || keys.has("arrowup") ? 1 : 0) + touchVector.y;
    const length = Math.hypot(dx, dy);
    if (length > 0) {
      dx /= length;
      dy /= length;
      const nextX = Math.max(24, Math.min(WORLD_SIZE - 24, player.x + dx * player.speed * delta));
      const nextY = Math.max(24, Math.min(WORLD_SIZE - 24, player.y + dy * player.speed * delta));
      const blocked = resources.some(item => item.alive && Math.hypot(item.x - nextX, item.y - nextY) < (item.type === "tree" ? 23 : 17));
      if (!blocked) {
        player.x = nextX;
        player.y = nextY;
      }
    }
  }

  async function connectRoom(room) {
    if (!window.supabase?.createClient) throw new Error("The multiplayer library did not load. Refresh HBU2 and try again.");
    if (!client) client = window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false, autoRefreshToken: false } });
    if (channel) {
      await channel.untrack().catch(() => {});
      await client.removeChannel(channel);
      channel = null;
    }
    currentRoom = room.trim().toUpperCase();
    remotePlayers.clear();
    channel = client.channel(`hbu-survival-${currentRoom}`, {
      config: { presence: { key: playerId }, broadcast: { self: false } }
    });
    channel.on("presence", { event: "sync" }, () => {
      const state = channel.presenceState();
      remotePlayers.clear();
      for (const [id, entries] of Object.entries(state)) {
        const entry = entries?.[entries.length - 1];
        if (entry && id !== playerId) remotePlayers.set(id, { id, ...entry });
      }
      updateHud();
    });
    channel.on("broadcast", { event: "move" }, ({ payload }) => {
      if (!payload || payload.id === playerId || typeof payload.x !== "number" || typeof payload.y !== "number") return;
      const existing = remotePlayers.get(payload.id) || {};
      remotePlayers.set(payload.id, { ...existing, ...payload });
      updateHud();
    });
    channel.on("broadcast", { event: "collect" }, ({ payload }) => {
      if (!payload || typeof payload.resourceId !== "string") return;
      const item = resources.find(resource => resource.id === payload.resourceId);
      if (!item) return;
      item.amount = Math.max(0, Number(payload.amount) || 0);
      item.alive = item.amount > 0;
    });
    const result = await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error("Multiplayer connection timed out.")), 12000);
      channel.subscribe(async state => {
        if (state === "SUBSCRIBED") {
          clearTimeout(timeout);
          try {
            await channel.track({ id: playerId, username, x: player.x, y: player.y, color: playerColor });
            resolve();
          } catch (error) { reject(error); }
        } else if (state === "CHANNEL_ERROR" || state === "TIMED_OUT" || state === "CLOSED") {
          clearTimeout(timeout);
          reject(new Error(`Multiplayer connection failed (${state}).`));
        }
      });
    });
    return result;
  }

  async function broadcastPosition(now) {
    if (!channel || now - lastBroadcast < 100) return;
    lastBroadcast = now;
    const payload = { id: playerId, username, x: Math.round(player.x), y: Math.round(player.y), color: playerColor };
    await channel.send({ type: "broadcast", event: "move", payload }).catch(() => {});
    if (Math.floor(now / 2000) !== Math.floor((now - 100) / 2000)) {
      await channel.track(payload).catch(() => {});
    }
  }

  function frame(now) {
    if (!running) return;
    const delta = Math.min((now - (lastFrame || now)) / 1000, 0.05);
    lastFrame = now;
    movePlayer(delta);
    render();
    void broadcastPosition(now);
    animationFrame = requestAnimationFrame(frame);
  }

  function startGame(room) {
    if (gameStarted) return;
    gameStarted = true;
    generateWorld(room);
    player.x = WORLD_SIZE / 2;
    player.y = WORLD_SIZE / 2;
    player.wood = 0;
    player.stone = 0;
    player.berries = 0;
    remotePlayers.clear();
    $("hbu-survival-lobby").hidden = true;
    $("hbu-survival-game").hidden = false;
    canvas = $("hbu-survival-canvas");
    ctx = canvas.getContext("2d");
    resizeCanvas();
    updateHud();
    running = true;
    lastFrame = 0;
    animationFrame = requestAnimationFrame(frame);
    setStatus(`Connected to world ${room}. Share this room code with friends: ${room}`);
  }

  async function joinRoom(room) {
    const normalized = room.trim().toUpperCase();
    if (!/^[A-Z0-9]{4,10}$/.test(normalized)) {
      setStatus("Room codes must be 4–10 letters or numbers.", true);
      return;
    }
    setStatus("Connecting to multiplayer…");
    $("hbu-survival-create").disabled = true;
    $("hbu-survival-join").disabled = true;
    try {
      await connectRoom(normalized);
      startGame(normalized);
    } catch (error) {
      setStatus(error.message || "Could not connect to this world.", true);
      if (channel && client) await client.removeChannel(channel).catch(() => {});
      channel = null;
    } finally {
      $("hbu-survival-create").disabled = false;
      $("hbu-survival-join").disabled = false;
    }
  }

  function bindControls() {
    const input = $("hbu-survival-room-code");
    $("hbu-survival-create").addEventListener("click", () => {
      const code = roomCode();
      input.value = code;
      void joinRoom(code);
    });
    $("hbu-survival-join").addEventListener("click", () => void joinRoom(input.value));
    $("hbu-survival-collect").addEventListener("click", collectResource);
    $("hbu-survival-leave").addEventListener("click", () => stopGame(true));
    window.addEventListener("resize", resizeCanvas);
    window.addEventListener("keydown", event => {
      if (!running) return;
      const key = event.key.toLowerCase();
      if (["w", "a", "s", "d", "arrowup", "arrowdown", "arrowleft", "arrowright", "e", " "].includes(key)) event.preventDefault();
      keys.add(key);
      if (key === "e") collectResource();
    });
    window.addEventListener("keyup", event => keys.delete(event.key.toLowerCase()));
    window.addEventListener("blur", () => keys.clear());
    document.querySelectorAll("[data-hbu-survival-dir]").forEach(button => {
      const direction = button.dataset.hbuSurvivalDir;
      const vectors = { up: [0, -1], down: [0, 1], left: [-1, 0], right: [1, 0] };
      const begin = event => { event.preventDefault(); touchVector = { x: vectors[direction][0], y: vectors[direction][1] }; };
      const end = event => { event.preventDefault(); touchVector = { x: 0, y: 0 }; };
      button.addEventListener("pointerdown", begin);
      button.addEventListener("pointerup", end);
      button.addEventListener("pointercancel", end);
      button.addEventListener("pointerleave", end);
    });
  }

  async function stopGame(returnToLobby) {
    running = false;
    gameStarted = false;
    cancelAnimationFrame(animationFrame);
    keys.clear();
    touchVector = { x: 0, y: 0 };
    if (channel && client) {
      await channel.untrack().catch(() => {});
      await client.removeChannel(channel).catch(() => {});
    }
    channel = null;
    remotePlayers.clear();
    updateHud();
    if (returnToLobby) {
      $("hbu-survival-game").hidden = true;
      $("hbu-survival-lobby").hidden = false;
      setStatus("You left the world. Create a new room or join a friend's room.");
    }
  }

  function open(account) {
    if (!$("hbu-survival-root")) return;
    if (!playerId) {
      username = account?.username || `Guest${Math.floor(1000 + Math.random() * 9000)}`;
      playerId = `${username.toLowerCase().replace(/[^a-z0-9]/g, "").slice(0, 18) || "guest"}-${Math.random().toString(36).slice(2, 8)}`;
      playerColor = COLORS[Math.floor(Math.random() * COLORS.length)];
      $("hbu-survival-player-name").textContent = username;
      bindControls();
    }
  }

  function close() {
    if (gameStarted || channel) void stopGame(true);
  }

  window.HBUSurvival = { open, close };
})();
