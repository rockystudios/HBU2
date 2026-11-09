    if (action === "login_image") return await loginImage(body);
    const isVoiceAction = typeof action === "string" && ["voice_list", "voice_create", "voice_token"].includes(action);
    const isAdminAction = typeof action === "string" && (action.startsWith("admin_") || action === "app_ai" || action === "delete_message");
    if (typeof username !== "string" || typeof password !== "string" || (!isAdminAction && !isVoiceAction && typeof message !== "string")) {
      throw new UserError("Missing username, password or message.");
    }
    const text = (isAdminAction || isVoiceAction) ? "" : message.trim();
    if (!isAdminAction && !isVoiceAction && (!text || text.length > MAX_LENGTH)) throw new UserError("Message must be 1-500 characters.");

    const loginRes = await fetch(`${SUPABASE_URL}/rest/v1/rpc/hbu_login`, {
      method: "POST",
      headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}`, "Content-Type": "application/json" },
      body: JSON.stringify({ p_username: username, p_password: password }),
    });
    if (!loginRes.ok) throw new UserError("Wrong username or password", 401);
    const realName: string = await loginRes.json();
    recordIp(req, realName);
    if (isVoiceAction) return await handleVoiceAction(action, realName, body);
    if (action === "delete_message") return await deleteOwnMessage(realName, body.id);
    if (action === "edit_message") return await editMessage(realName, body.id, text);
    if (action === "app_ai") return await appAi(realName, body);
    if (isAdminAction) return await handleAdmin(action, realName, body);

    if (COMMAND.test(text)) {
      await spamCheck(realName, text);
      return await handleCommand(realName, text);
    }

    // Run the independent checks at the same time so sending stays fast.
    const wantsDm = typeof receiver === "string" && receiver.toLowerCase() !== "everyone";
    const [accountRows, found, lastRows, muteRows, settings] = await Promise.all([
      db(`accounts?select=banned_until,ban_reason&username=eq.${enc(realName)}`),
      wantsDm ? findAccount(receiver) : Promise.resolve(undefined),
      db(`messages?select=created_at&user=eq.${enc(realName)}&order=created_at.desc&limit=1`),
      db(`accounts?select=muted_until&username=eq.${enc(realName)}`).catch(() => []),
      chatSettings(),
      wordFilter(),
    ]);
    const [account] = accountRows ?? [];
    if (!isAdmin(realName) && account?.banned_until && new Date(account.banned_until) > new Date()) {
      const reason = account.ban_reason ? ` Reason: ${account.ban_reason}` : "";
      throw new UserError(`You are banned from chatting until ${new Date(account.banned_until).toUTCString()}.${reason}`, 403);
    }

    const mutedUntil = muteRows?.[0]?.muted_until;
    let target = "everyone";
    if (wantsDm) {
      if (!found) throw new UserError("That user does not exist.");
      if (found.username === realName) throw new UserError("You cannot DM yourself.");
      target = found.username;
    }

    if (target === "everyone" && !isAdmin(realName) && mutedUntil && new Date(mutedUntil) > new Date()) {
      throw new UserError(`You are muted from the main chat until ${new Date(mutedUntil).toUTCString()}. You can still send DMs.`, 403);
    }

    if (target === "everyone") await spamCheck(realName, text);

    let waitMs = COOLDOWN_MS;
    if (target === "everyone" && (settings.locked || settings.slow > 0) && !isAdmin(realName)) {
      const senderRole = await roleOf(realName);
      if (!(await isStaffRole(senderRole))) {
        if (settings.locked) throw new UserError("The chat is locked right now. Only moderators can talk.", 403);
        waitMs = Math.max(waitMs, settings.slow * 1000);
      }
    }
    const [last] = lastRows ?? [];
    if (last && Date.now() - new Date(last.created_at).getTime() < waitMs) {
      throw new UserError(waitMs > COOLDOWN_MS ? `Slow mode is on. Wait ${Math.ceil(waitMs / 1000)} seconds between messages.` : "Slow down a little before sending another message.", 429);
    }

    const asksBot = target === "everyone" && /@mod-bot\b/i.test(text);
    let botBlocked = false;
    if (target === "everyone" && /@everyone\b/i.test(text) && !(await isStaffRole(await roleOf(realName)))) {
      throw new UserError("Only moderators can use @everyone.", 403);
    }
    if (asksBot && !isAdmin(realName)) {
      const [state] = await db(`accounts?select=bot_banned,bot_strikes&username=eq.${enc(realName)}`).catch(() => []) ?? [];
      botBlocked = state?.bot_banned === true;
      if (!botBlocked) {
        const since = new Date(Date.now() - BOT_COOLDOWN_MS).toISOString();
        const [recent] = await db(
          `messages?select=created_at&user=eq.${enc(realName)}&message=ilike.${enc("*@mod-bot*")}&created_at=gt.${enc(since)}&order=created_at.desc&limit=1`,
        ) ?? [];
        if (recent) {
          const strikes = Number(state?.bot_strikes ?? 0) + 1;
          const wait = Math.max(1, Math.ceil((BOT_COOLDOWN_MS - (Date.now() - new Date(recent.created_at).getTime())) / 60000));
          if (state) {
            await db(`accounts?username=eq.${enc(realName)}`, {
              method: "PATCH",
              headers: { Prefer: "return=minimal" },
              body: JSON.stringify({ bot_strikes: strikes, bot_banned: strikes >= BOT_MAX_STRIKES }),
            }).catch(() => {});
          }
          if (state && strikes >= BOT_MAX_STRIKES) {
            await log({ username: realName, action: "auto-blocked from mod-bot", reason: "Spamming mod-bot" });
            await botPost(`@${realName} you were blocked from talking to mod-bot for abusing it. A moderator can restore access.`);
            throw new UserError("mod-bot blocked you for abusing it. A moderator can restore your access.", 429);
          }
          throw new UserError(`You can ask mod-bot one question every 5 minutes. Try again in about ${wait} min. (Warning ${Math.min(strikes, BOT_MAX_STRIKES - 1)}/${BOT_MAX_STRIKES - 1} before mod-bot blocks you.)`, 429);
        }
        if (state && Number(state.bot_strikes) > 0) {
          await db(`accounts?username=eq.${enc(realName)}`, {
            method: "PATCH",
            headers: { Prefer: "return=minimal" },
            body: JSON.stringify({ bot_strikes: 0 }),
          }).catch(() => {});
        }
      }
    }

    const clean = (await censor(text)).slice(0, MAX_LENGTH);
    if (clean !== text) void log({ username: realName, receiver: target, original: text, edited: clean, action: "filtered" });

    await db("messages", {
      method: "POST",
      headers: { Prefer: "return=minimal" },
      body: JSON.stringify({ user: realName, receiver: target, message: clean }),
    });
    const sentAt = new Date().toISOString();
    if (target === "everyone" && /@mod-bot\b/i.test(clean)) {
      // Answer in the background so sending stays instant.
      const work = botBlocked
        ? botPost(`@${realName} you were blocked from talking to mod-bot for abusing it.`)
        : botReply(realName, clean);
      // deno-lint-ignore no-explicit-any
      const runtime = (globalThis as any).EdgeRuntime;
      if (runtime?.waitUntil) runtime.waitUntil(work); else void work;
    }
    return json({ ok: true, edited: clean !== text, message: clean, user: realName, created_at: sentAt });
  } catch (error) {
    if (error instanceof UserError) return json({ error: error.message }, error.status);
    console.error("send-message failed", error);
    return json({ error: "mod-bot is unavailable right now. Please try again in a moment." }, 503);
  }
}

Deno.serve(handle);
