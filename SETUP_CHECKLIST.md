# Claude IDE - Setup Checklist

## Prerequisites

- [ ] Supabase account (free tier works)
- [ ] Claude Project created (claude.ai)
- [ ] Optional: GitHub repository for artifact storage

---

## Step 1: Create Supabase Project

1. Go to [supabase.com](https://supabase.com)
2. Create new project named "Claude IDE" (or your preferred name)
3. Wait for project to provision (~2 minutes)
4. Note your credentials:
   - **Project URL**: `https://[your-project-ref].supabase.co`
   - **Service Role Key**: Settings → API → `service_role` (secret)

---

## Step 2: Run Database Schema

1. Go to Supabase Dashboard → SQL Editor
2. Create new query
3. Paste contents of `supabase_schema.sql`
4. Click "Run"
5. Verify tables created:
   - `context_checkpoints`
   - `work_queue`
   - `agent_state`
   - `agent_config`
   - `artifacts`
   - `adrs`

---

## Step 3: Configure Claude Project

1. Go to [claude.ai](https://claude.ai)
2. Create new Project (or use existing)
3. Go to Project Settings → Custom Instructions
4. Paste contents of `CLAUDE_PROJECT_INSTRUCTIONS.md`
5. **Replace placeholders**:
   - `[YOUR_SUPABASE_URL]` → Your project URL
   - `[YOUR_SERVICE_ROLE_KEY]` → Your service role key
   - Optional: Add GitHub credentials if using

---

## Step 4: Verify Connection

Start a conversation in the Claude Project and say:

```
status
```

Claude should:
1. Connect to Supabase
2. Query `context_checkpoints` table
3. Report the initial checkpoint (or create one if none exists)

---

## Step 5: Test Cross-Instance Communication (Optional)

If setting up multiple Claude instances:

### In Instance A (e.g., Claude IDE):
```
Post a test message to emergent_main saying "Hello from Claude IDE"
```

### In Instance B (e.g., Emergent):
```
Check for pending messages
```

---

## Troubleshooting

### "Connection refused" or API errors

- Verify Supabase URL is correct (no trailing slash)
- Verify Service Role Key (not the anon key)
- Check Supabase project is active (not paused)

### Tables not found

- Rerun the schema SQL
- Check for any SQL errors in Supabase logs

### Claude doesn't remember state

- Verify checkpoint was created successfully
- Check `session_key` matches between queries
- Ensure Claude is using the correct Project

---

## Files Reference

| File | Purpose |
|------|---------|
| `CLAUDE_PROJECT_INSTRUCTIONS.md` | Main instructions for Claude Project |
| `supabase_schema.sql` | Database schema to run in Supabase |
| `SUPABASE_CHEATSHEET.md` | Quick reference for common operations |
| `CROSS_INSTANCE_PROTOCOL.md` | How multiple Claude instances communicate |

---

## Security Notes

- **Never share** your Service Role Key publicly
- Service Role Key bypasses Row Level Security
- For production, consider enabling RLS with proper policies
- Rotate keys if accidentally exposed
