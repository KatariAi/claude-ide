# Claude IDE - Quick Start

## Setup (One-Time)

1. **Create Supabase Project**
   - Go to [supabase.com](https://supabase.com) → New Project → Name it "Claude IDE"
   - Wait for provisioning (~2 min)
   - Copy your **Project URL** and **Service Role Key** from Settings → API

2. **Run Database Schema**
   - Go to Supabase → SQL Editor
   - Paste contents of `supabase_schema.sql`
   - Click Run

3. **Create Claude Project**
   - Go to [claude.ai](https://claude.ai) → New Project
   - Go to Project Settings → Custom Instructions
   - Paste contents of `CLAUDE_PROJECT_INSTRUCTIONS.md`
   - Replace `[YOUR_SUPABASE_URL]` and `[YOUR_SERVICE_ROLE_KEY]` with your actual credentials

---

## First Message (Bootstrap)

Once setup is complete, start a conversation and send this:

```
Bootstrap: This is a new Claude IDE project. Initialize the system:

1. Connect to Supabase and verify the schema is set up
2. Create the initial checkpoint (checkpoint #1)
3. Report what tables exist and confirm the system is operational
4. List any pending work in the queue

Session key: claude_ide_main
```

---

## Ongoing Usage

After bootstrap, you can use these commands:

| Command | What It Does |
|---------|--------------|
| `continue` | Read last checkpoint, execute next pending work |
| `status` | Report current state without executing anything |
| `checkpoint` | Save current state to database |
| `sync` | Check for messages from other Claude instances |

---

## Files in This Package

| File | Purpose |
|------|---------|
| `CLAUDE_PROJECT_INSTRUCTIONS.md` | Custom instructions for Claude Project (paste into settings) |
| `supabase_schema.sql` | Database schema (run in Supabase SQL Editor) |
| `HOW_IT_WORKS.md` | Detailed explanation of the system |
| `CREDENTIALS_GUIDE.md` | All API keys and tokens needed |
| `SETUP_CHECKLIST.md` | Step-by-step setup checklist |
| `SUPABASE_CHEATSHEET.md` | Quick reference for Supabase operations |
| `CROSS_INSTANCE_PROTOCOL.md` | How multiple Claude instances communicate |

---

## Minimum Requirements

- Supabase account (free tier works)
- Claude Pro account (for Projects feature)

That's it. You're ready to go.
