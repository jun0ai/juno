import { Telegraf, Markup } from "telegraf";
import { createOpencodeClient } from "@opencode-ai/sdk";

// --- Config ---
const BOT_TOKEN = process.env.TELEGRAM_BOT_TOKEN!;
const OC_URL = process.env.OPENCODE_URL || "http://127.0.0.1:4096";
const ALLOWED = (process.env.ALLOWED_USERS || "*").split(",");

// --- State ---
const chatSessions = new Map<number, string>(); // chatId -> sessionId
const pendingPermissions = new Map<string, { chatId: number; resolve: (v: boolean) => void }>();
const lastBotMessage = new Map<number, number>(); // chatId -> last bot messageId (for reaction tracking)

// --- OpenCode Client ---
// Uses the existing opencode serve (no auth needed locally)
const oc = createOpencodeClient({
  baseUrl: OC_URL,
});

// --- Bot ---
const bot = new Telegraf(BOT_TOKEN);

// Auth middleware
bot.use(async (ctx, next) => {
  const uid = ctx.from?.id;
  if (!uid || (ALLOWED[0] !== "*" && !ALLOWED.includes(String(uid)))) {
    await ctx.reply("Unauthorized.");
    return;
  }
  await next();
});

// --- Helpers ---
async function ensureSession(chatId: number): Promise<string> {
  let sid = chatSessions.get(chatId);
  if (sid) return sid;

  const name = `tg-${chatId}`;
  const res = await oc.session.create({ body: { title: name } });
  sid = res.data!.id;
  chatSessions.set(chatId, sid);
  return sid;
}

function truncate(text: string, max: number): string {
  if (text.length <= max) return text;
  return text.slice(0, max - 3) + "...";
}

function formatMessage(text: string): string {
  if (text.length > 4000) text = text.slice(0, 3950) + "\n\n... (truncated)";
  return text;
}

// Reply helper — tracks last message per chat for reaction routing
async function reply(ctx: any, text: string) {
  const msg = await ctx.reply(text);
  lastBotMessage.set(ctx.chat.id, msg.message_id);
  return msg;
}

function formatMessage(text: string): string {
  // Escape Telegram MarkdownV2 special chars: _ * [ ] ( ) ~ ` > # + - = | { } . !
  if (text.length > 4000) text = text.slice(0, 3950) + "\n\n... (truncated)";
  return text;
}

// --- Handlers ---

// /start
bot.start((ctx) => ctx.reply("Juno online. /ask to talk, /help for commands."));

// /help
bot.help((ctx) =>
  ctx.reply(
    [
      "*/ask* `<prompt>` — Ask Juno anything",
      "*/undo* — Undo last change",
      "*/redo* — Redo",
      "*/status* — Current session status",
      "*/session list* — List sessions",
      "*/session new* — New session",
      "*/session switch `<id>`* — Switch session",
      "",
      "Just send a message without /ask to chat casually.",
    ].join("\n"),
  ),
);

// /status
bot.command("status", async (ctx) => {
  const sid = chatSessions.get(ctx.chat.id);
  if (!sid) return ctx.reply("No active session. Send /ask to start.");
  const s = await oc.session.get({ path: { id: sid } });
  ctx.reply(`Session: \`${sid.slice(0, 8)}...\`\nTitle: ${s.data?.title || "untitled"}`);
});

// /undo
bot.command("undo", async (ctx) => {
  const sid = chatSessions.get(ctx.chat.id);
  if (!sid) return ctx.reply("No active session.");
  const msgs = await oc.session.messages({ path: { id: sid } });
  const lastAssistant = msgs.data?.findLast((m: any) => m.info.role === "assistant");
  if (!lastAssistant) return ctx.reply("Nothing to undo.");
  await oc.session.revert({ path: { id: sid }, body: { messageID: lastAssistant.info.id } });
  ctx.reply("Undone.");
});

// /redo
bot.command("redo", async (ctx) => {
  const sid = chatSessions.get(ctx.chat.id);
  if (!sid) return ctx.reply("No active session.");
  await oc.session.unrevert({ path: { id: sid } });
  ctx.reply("Redone.");
});

// /session
bot.command("session", async (ctx) => {
  const arg = (ctx.message as any)?.text?.split(" ").slice(1).join(" ") || "list";

  if (arg === "list" || !arg) {
    const sessions = await oc.session.list();
    const lines = sessions.data?.slice(0, 10).map((s: any) => `\`${s.id.slice(0, 8)}\` — ${s.title || "untitled"}`).join("\n") || "No sessions.";
    return ctx.reply(lines);
  }

  if (arg === "new") {
    chatSessions.delete(ctx.chat.id);
    const sid = await ensureSession(ctx.chat.id);
    return ctx.reply(`New session: \`${sid.slice(0, 8)}...\``);
  }

  if (arg.startsWith("switch ")) {
    const id = arg.slice(7).trim();
    chatSessions.set(ctx.chat.id, id);
    return ctx.reply(`Switched to \`${id.slice(0, 8)}...\``);
  }

  ctx.reply("Usage: /session [list|new|switch <id>]");
});

// /ask command — explicit prompt
bot.command("ask", handlePrompt);

// Handle regular messages as prompts too
bot.on("text", async (ctx, next) => {
  // Skip if it's a command
  if ((ctx.message as any)?.text?.startsWith("/")) return next();
  await handlePrompt(ctx);
});

async function handlePrompt(ctx: any) {
  let text = (ctx.message as any)?.text || "";
  if (text.startsWith("/ask")) text = text.slice(5).trim();
  if (!text) return reply(ctx, "What do you want to ask?");

  const chatId = ctx.chat.id;
  const sid = await ensureSession(chatId);

  // Typing loop: Telegram typing indicator expires after ~5s, keep refreshing
  let typing = true;
  const keepTyping = (async () => {
    while (typing) {
      await ctx.sendChatAction("typing").catch(() => {});
      await new Promise((r) => setTimeout(r, 4000));
    }
  })();

  try {
    const before = await oc.session.messages({ path: { id: sid } });
    const beforeCount = before.data?.length || 0;
    const seenTool = new Set<string>();

    // Send async prompt
    const url = `${OC_URL}/session/${sid}/prompt_async`;
    const res = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ parts: [{ type: "text", text }] }),
    });

    if (!res.ok) {
      typing = false;
      return reply(ctx, `Fail: ${res.status}`);
    }

    // Poll for progress + response (max 5 min)
    const maxWait = 5 * 60 * 1000;
    const start = Date.now();
    let responseText = "";

    while (Date.now() - start < maxWait) {
      await new Promise((r) => setTimeout(r, 1500));

      const msgs = await oc.session.messages({ path: { id: sid } });
      const all = msgs.data || [];

      // Scan new parts for tool uses → report as progress
      for (let i = beforeCount; i < all.length; i++) {
        for (const p of all[i].parts || []) {
          if (p.type === "tool_use" && !seenTool.has(p.name)) {
            seenTool.add(p.name);
            await ctx.reply(`…${p.name}…`).catch(() => {});
          }
        }
      }

      // Collect all new assistant text
      responseText = "";
      for (let i = beforeCount; i < all.length; i++) {
        if (all[i].info.role === "assistant") {
          for (const p of all[i].parts || []) {
            if (p.type === "text") responseText += p.text;
          }
        }
      }
      if (responseText.trim()) break;
    }

    typing = false;

    if (responseText.trim()) {
      await reply(ctx, formatMessage(responseText));
    } else {
      await reply(ctx, "(timeout — still working, try /status)");
    }
  } catch (err: any) {
    typing = false;
    reply(ctx, `Error: ${err.message}`);
  }
}

// --- Reaction handling ---
bot.on("message_reaction", async (ctx, next) => {
  const chatId = ctx.chat?.id;
  if (!chatId) return;

  const reaction = ctx.messageReaction;
  if (!reaction || reaction.new_reaction?.length === 0) return;

  const emoji = reaction.new_reaction[0]?.emoji;
  const lastId = lastBotMessage.get(chatId);
  if (reaction.message_id !== lastId) return next();

  switch (emoji) {
    case "👎": {
      const sid = chatSessions.get(chatId);
      if (!sid) return reply(ctx, "No active session.");
      const msgs = await oc.session.messages({ path: { id: sid } });
      const last = msgs.data?.findLast((m: any) => m.info.role === "assistant");
      if (!last) return reply(ctx, "Nothing to undo.");
      await oc.session.revert({ path: { id: sid }, body: { messageID: last.info.id } });
      return reply(ctx, "Undone. 👌");
    }
    case "🔄": {
      const sid = chatSessions.get(chatId);
      if (!sid) return reply(ctx, "No active session.");
      await oc.session.unrevert({ path: { id: sid } });
      return reply(ctx, "Redone.");
    }
    case "👍":
    case "❤️":
    case "🔥":
    case "👏":
      return; // acknowledged, no action needed
  }
  return next();
});

// --- Start ---
console.log("Juno Bridge starting...");

// Prevent crashes from unhandled rejections
process.on("unhandledRejection", (reason) => {
  console.error("Unhandled rejection:", (reason as any)?.message || reason);
});

bot.launch(() => console.log("Telegram bot online. @jun0aibot"));
process.once("SIGINT", () => bot.stop("SIGINT"));
process.once("SIGTERM", () => bot.stop("SIGTERM"));
