# 🧠 Claude IDE

### Give your AI a memory. Watch it remember.

---

**Claude IDE** is an open-source coordination system that transforms Claude from a stateless chatbot into a persistent, collaborative development partner. Built on Supabase, it enables multiple AI instances—Claude.ai, your vibe coding agent, or any AI tool—to share memory, coordinate tasks, and pick up exactly where they left off.

No more "as an AI, I don't have memory of previous conversations."

Now it does.

---

## 🎯 The Problem

Every Claude conversation starts from zero. You explain your project. Again. You re-establish context. Again. You watch Claude forget everything the moment you close the tab.

Worse: if you're using multiple AI tools—Claude.ai for planning, your vibe coding agent for execution—they can't talk to each other. Each lives in its own silo, unaware of what the others have done.

This creates **drift**: the gradual accumulation of context errors, misunderstandings, and inconsistencies that compound over time. The more you work with AI, the more you fight against drift.

## 💡 The Solution

**Externalize the brain.**

Claude IDE stores all state in a Supabase database that persists across sessions:

```
┌─────────────────────────────────────────────────────────────┐
│                       SUPABASE                              │
│                                                             │
│   📍 Checkpoints    📋 Work Queue    🗄️ State Store        │
│   "What happened"   "What's next"    "What we know"        │
│                                                             │
└─────────────────────────────────────────────────────────────┘
        ↑                   ↑                   ↑
        │                   │                   │
   ┌────┴────┐        ┌────┴────┐        ┌────┴────┐
   │ Claude  │        │  Vibe   │        │ Another │
   │   .ai   │◄──────►│  Agent  │◄──────►│  Agent  │
   └─────────┘        └─────────┘        └─────────┘
```

Every AI instance reads from and writes to the same database. They share:
- **Checkpoints**: Snapshots of progress ("Completed auth flow, starting frontend")
- **Work Queue**: Tasks and messages ("Vibe Agent: please implement this spec")
- **State**: Configuration, decisions, context ("We're using PostgreSQL, not MongoDB")

The database is the brain. The AIs are the hands.

---

## ✨ Features

### 🔄 Persistent Memory
Close your browser. Come back tomorrow. Say "continue" and Claude picks up exactly where you left off—no re-explanation needed.

### 🤝 Cross-Instance Coordination
Post a task from Claude.ai. Your vibe coding agent picks it up, executes it, reports back. Seamless handoffs between any AI tools that can make HTTP requests.

### 🛡️ Anti-Drift Architecture
Single source of truth prevents the context degradation that plagues long-running AI projects. Every decision is recorded. Every state change is checkpointed.

### 📊 Full Audit Trail
Every checkpoint, every task, every state change is logged with timestamps. Roll back to any previous state if something goes wrong.

### 🔌 Universal Compatibility
Works with anything that can call a REST API: Claude.ai, Claude Projects, Claude Code, your vibe coding agent, custom scripts, or your own AI orchestration system.

### 🧬 Self-Improvement
When Claude discovers a better way to do something—a workaround, an optimization, an error pattern—it records it to the database. Future sessions load these learnings and apply them. Claude literally gets better over time.

---

## 🚀 Quick Start

### 1. Create a Supabase Project (2 minutes)

Go to [supabase.com](https://supabase.com) → New Project → Name it anything you like.

Copy your **Project URL** and **Service Role Key** from Settings → API.

### 2. Run the Schema (30 seconds)

Go to SQL Editor in Supabase, paste the contents of [`supabase_schema.sql`](./supabase_schema.sql), click Run.

### 3. Configure Claude (1 minute)

Create a Claude Project at [claude.ai](https://claude.ai). Paste [`CLAUDE_PROJECT_INSTRUCTIONS.md`](./CLAUDE_PROJECT_INSTRUCTIONS.md) into Custom Instructions. Replace the credential placeholders.

### 4. Bootstrap

Start a conversation and send:

```
Bootstrap: This is a new Claude IDE project. Initialize the system:

1. Connect to Supabase and verify the schema is set up
2. Create the initial checkpoint (checkpoint #1)
3. Report what tables exist and confirm the system is operational
4. List any pending work in the queue

Session key: claude_ide_main
```

**That's it.** You now have a Claude with persistent memory.

---

## 📁 What's in the Box

| File | What It Does |
|------|--------------|
| [`StartHereReadMe.md`](./StartHereReadMe.md) | Quick start checklist |
| [`CLAUDE_PROJECT_INSTRUCTIONS.md`](./CLAUDE_PROJECT_INSTRUCTIONS.md) | Drop-in custom instructions for Claude Projects |
| [`CLAUDE_CODE_INSTRUCTIONS.md`](./CLAUDE_CODE_INSTRUCTIONS.md) | Integration guide for Claude Code as execution agent |
| [`supabase_schema.sql`](./supabase_schema.sql) | Complete database schema with tables and functions |
| [`HOW_IT_WORKS.md`](./HOW_IT_WORKS.md) | Deep dive into the architecture |
| [`CREDENTIALS_GUIDE.md`](./CREDENTIALS_GUIDE.md) | All the API keys and tokens you might need |
| [`CROSS_INSTANCE_PROTOCOL.md`](./CROSS_INSTANCE_PROTOCOL.md) | How multiple AIs talk to each other |
| [`SUPABASE_CHEATSHEET.md`](./SUPABASE_CHEATSHEET.md) | Copy-paste curl commands for common operations |
| [`SETUP_CHECKLIST.md`](./SETUP_CHECKLIST.md) | Step-by-step with checkboxes |

---

## 🎮 Usage

Once bootstrapped, your Claude understands these commands:

| Command | What Happens |
|---------|--------------|
| `continue` | Reads last checkpoint, executes next pending work |
| `status` | Reports current state without doing anything |
| `checkpoint` | Saves current progress to database |
| `sync` | Checks for messages from other AI instances |

But honestly, you can just talk normally. Claude will checkpoint automatically after completing work and check for pending tasks on session start.

---

## 🏗️ Architecture

### The Database Schema

```
context_checkpoints     Snapshots of "where we are"
        │
        ├── checkpoint_number (auto-incrementing)
        ├── session_key (which AI instance)
        ├── description (human-readable summary)
        ├── state_snapshot (JSON blob with full state)
        └── verification_status (human-verified or not)

work_queue              Tasks and inter-instance messages
        │
        ├── source_session (who created it)
        ├── target_session (who should do it)
        ├── task_type (request/response/handoff)
        ├── payload (the actual work)
        └── status (pending → claimed → completed)

agent_state             Versioned key-value storage
        │
        ├── state_key (unique identifier)
        ├── state_value (JSON data)
        └── version (increments on each update)
```

### The Anti-Drift Protocol

Claude IDE enforces strict patterns to prevent context degradation:

**🚫 Forbidden:**
- "Should I..." / "Would you like me to..."
- Vague quantifiers ("several", "various", "some")
- Asking humans to verify what Claude can verify itself

**✅ Required:**
- Execute first, report after
- Create checkpoints after completing work
- Enumerate everything explicitly
- Use past tense for completed actions

This isn't about being rigid—it's about preventing the slow accumulation of uncertainty that makes AI assistants less useful over time.

---

## 🌐 Multi-Agent Workflows

The real magic happens when multiple AI instances coordinate:

```
┌─────────────┐                              ┌─────────────┐
│  Claude.ai  │                              │    Vibe     │
│  (Planning) │                              │   Agent     │
└──────┬──────┘                              └──────┬──────┘
       │                                            │
       │ 1. POST task to work_queue                 │
       │────────────────────────────────────────────│
       │                                            │
       │                     2. Poll, claim, execute│
       │                                            │
       │ 3. Check completed work                    │
       │◄───────────────────────────────────────────│
       │                                            │
       ▼                                            ▼
   Continue                                    Next task
```

**Example: Delegating to Your Vibe Agent**

In Claude.ai:
> "Have my vibe agent implement a login form based on our auth spec"

Claude posts to `work_queue`:
```json
{
  "source_session": "claude_ide_main",
  "target_session": "vibe_agent_main",
  "payload": {
    "action": "implement",
    "spec": "Login form with email/password, validation, OAuth option"
  }
}
```

Your vibe agent picks it up, builds it, marks complete. Next time you say "sync" in Claude.ai, it sees the finished work and continues from there.

---

## 🔐 Security

- **Service Role Key** has full database access—treat it like a password
- Store credentials only in Claude Project instructions (Anthropic-secured) or environment variables
- Never commit credentials to version control
- Consider enabling Row Level Security for production deployments

See [`CREDENTIALS_GUIDE.md`](./CREDENTIALS_GUIDE.md) for detailed security guidance.

---

## 🤔 FAQ

**Q: Does this work with the free tier of Supabase?**  
A: Yes! The free tier is more than sufficient for personal use.

**Q: Can I use this with my vibe coding agent?**  
A: If it can make HTTP requests to a REST API, it can participate. You'll need to add instructions telling it how to interact with the Supabase endpoints.

**Q: What happens if two AI instances try to claim the same task?**  
A: The `claim_work()` function uses PostgreSQL's `FOR UPDATE SKIP LOCKED` to ensure atomic claiming. Only one instance gets the task.

**Q: Can I see what's in the database?**  
A: Yes! Supabase has a built-in table viewer. Go to your project dashboard → Table Editor.

**Q: Is my data private?**  
A: Your Supabase project is yours. Data stays in your database. Neither Anthropic nor anyone else has access unless you share your credentials.

---

## 🛣️ Roadmap

- [ ] Web dashboard for visualizing checkpoints and work queue
- [ ] Pre-built integrations for popular AI coding tools
- [ ] Webhook support for real-time notifications
- [ ] Checkpoint diffing and rollback UI
- [ ] Multi-user support with authentication

---

## 🙏 Contributing

Found a bug? Have an idea? PRs welcome.

1. Fork the repo
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## 📜 License

MIT License - do whatever you want with it. See [`LICENSE`](./LICENSE) for details.

---

## 🌟 Star History

If this helps you build better AI workflows, consider giving it a star. It helps others find it.

---

<div align="center">

**Built for the vibe coding era.**

*Stop re-explaining. Start building.*

[Get Started](./StartHereReadMe.md) · [How It Works](./HOW_IT_WORKS.md) · [Report Bug](https://github.com/KatariAi/claude-ide/issues)

</div>
