# Claude IDE - Authorization & Credentials Guide

This document outlines all the API keys, tokens, and authorizations required to set up the Claude IDE system with Supabase-backed coordination.

---

## Required Credentials

### 1. Supabase (REQUIRED)

Supabase provides the persistent database that stores all state, checkpoints, and enables cross-instance communication.

#### What You Need

| Credential | Where to Find | Purpose |
|------------|---------------|---------|
| **Project URL** | Supabase Dashboard → Settings → API | Base URL for all API calls |
| **Service Role Key** | Supabase Dashboard → Settings → API → `service_role` | Full database access (bypasses RLS) |
| **Anon Key** (optional) | Supabase Dashboard → Settings → API → `anon` | Public/limited access (if using RLS) |

#### How to Get Them

1. Go to [supabase.com](https://supabase.com) and sign in (or create account)
2. Click "New Project"
3. Fill in:
   - **Name**: `Claude IDE` (or your preferred name)
   - **Database Password**: Generate a strong password (save this!)
   - **Region**: Choose closest to you
4. Wait ~2 minutes for provisioning
5. Go to **Settings** → **API**
6. Copy:
   - **Project URL**: `https://[your-ref].supabase.co`
   - **Service Role Key**: The `service_role` secret (click "Reveal")

#### Format
```
URL: https://abcdefghijklmnop.supabase.co
Service Role Key: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFiY2RlZmdoaWprbG1ub3AiLCJyb2xlIjoic2VydmljZV9yb2xlIiwiaWF0IjoxNjk5MDAwMDAwLCJleHAiOjIwMTQ1NzYwMDB9.xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

#### Security Notes
- **Service Role Key** has FULL access to your database - treat it like a password
- Never commit to public repositories
- Never expose in frontend/client-side code
- Store only in Claude Project Instructions (Anthropic-secured)

---

## Optional Credentials

These are not required for basic operation but enable additional features.

### 2. GitHub (OPTIONAL)

Enables Claude to commit code directly to your repository.

#### What You Need

| Credential | Where to Find | Purpose |
|------------|---------------|---------|
| **Personal Access Token (PAT)** | GitHub → Settings → Developer Settings → Personal Access Tokens | Repository read/write access |
| **Repository** | Your GitHub repo | Where code gets committed |

#### How to Get Them

1. Go to [github.com/settings/tokens](https://github.com/settings/tokens)
2. Click "Generate new token" → "Generate new token (classic)"
3. Fill in:
   - **Note**: `Claude IDE Access`
   - **Expiration**: Choose based on your security needs
   - **Scopes**: Select:
     - `repo` (full repository access)
     - `workflow` (if using GitHub Actions)
4. Click "Generate token"
5. **Copy immediately** (you can't see it again!)

#### Format
```
Token: github_pat_11XXXXXXX_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
Repo: YourOrg/your-repo
Branch: main
```

#### Required Scopes
| Scope | Required For |
|-------|--------------|
| `repo` | Read/write code, create commits |
| `workflow` | Trigger GitHub Actions (optional) |
| `read:org` | Access org repositories (if applicable) |

---

### 3. Anthropic API (OPTIONAL)

Only needed if Claude instances need to call Claude API directly (e.g., for sub-agents).

#### What You Need

| Credential | Where to Find | Purpose |
|------------|---------------|---------|
| **API Key** | [console.anthropic.com](https://console.anthropic.com) → API Keys | Call Claude API programmatically |

#### How to Get It

1. Go to [console.anthropic.com](https://console.anthropic.com)
2. Sign in or create account
3. Go to **API Keys**
4. Click "Create Key"
5. Name it (e.g., `Claude IDE`)
6. Copy the key

#### Format
```
API Key: sk-ant-api03-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

#### Pricing Note
API calls are billed separately from Claude Pro subscription. Check [anthropic.com/pricing](https://anthropic.com/pricing) for current rates.

---

### 4. Vercel (OPTIONAL)

For deploying frontend applications.

#### What You Need

| Credential | Where to Find | Purpose |
|------------|---------------|---------|
| **Access Token** | Vercel Dashboard → Settings → Tokens | Deploy and manage projects |
| **Team ID** (if applicable) | Vercel Dashboard → Settings → General | Target specific team |
| **Project ID** | Vercel Dashboard → Project → Settings → General | Target specific project |

#### How to Get Them

1. Go to [vercel.com/account/tokens](https://vercel.com/account/tokens)
2. Click "Create"
3. Fill in:
   - **Name**: `Claude IDE`
   - **Scope**: Full Account (or specific team)
   - **Expiration**: Choose based on needs
4. Click "Create Token"
5. Copy immediately

#### Format
```
Token: xxxxxxxxxxxxxxxxxxxx
Team ID: team_xxxxxxxxxxxxxxxxx (optional)
Project: your-project-name
```

---

### 5. Fly.io (OPTIONAL)

For deploying backend workers/services.

#### What You Need

| Credential | Where to Find | Purpose |
|------------|---------------|---------|
| **API Token** | Fly.io Dashboard → Account → Access Tokens | Deploy and manage apps |

#### How to Get It

1. Go to [fly.io/user/personal_access_tokens](https://fly.io/user/personal_access_tokens)
2. Click "Create Token"
3. Name it (e.g., `Claude IDE`)
4. Copy the token

#### Format
```
Token: FlyV1 fm2_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

---

### 6. Redis (OPTIONAL)

For caching, rate limiting, or queue management.

#### What You Need

| Credential | Where to Find | Purpose |
|------------|---------------|---------|
| **Connection URL** | Redis provider dashboard | Connect to Redis instance |

#### Providers
- **Redis Cloud** (redis.com) - Managed Redis
- **Upstash** (upstash.com) - Serverless Redis
- **Railway** (railway.app) - Simple hosting

#### Format
```
URL: redis://default:password@hostname:port
```

Example (Redis Cloud):
```
redis://default:AbCdEfGhIjKlMnOp@redis-12345.c123.us-east-1-1.ec2.cloud.redislabs.com:12345
```

---

## Credential Placement

### In Claude Project Instructions

Add credentials to your Claude Project's custom instructions:

```markdown
## Credentials

**Supabase:**
```
URL: https://your-project.supabase.co
SERVICE_ROLE_KEY: eyJhbGciOiJIUzI1NiIs...
```

**GitHub:** (optional)
```
TOKEN: github_pat_11XXXXX...
REPO: YourOrg/your-repo
BRANCH: main
```
```

### Security Best Practices

| DO | DON'T |
|----|-------|
| Store in Claude Project Instructions | Commit to public repos |
| Use environment variables in deployed apps | Hardcode in frontend code |
| Rotate keys periodically | Share via unencrypted channels |
| Use minimum required scopes | Grant admin access unnecessarily |
| Set expiration dates on tokens | Create tokens that never expire |

---

## Credential Checklist

### Minimum Setup (Basic Coordination)
- [ ] Supabase Project URL
- [ ] Supabase Service Role Key

### Standard Setup (Code Management)
- [ ] Supabase Project URL
- [ ] Supabase Service Role Key
- [ ] GitHub Personal Access Token
- [ ] GitHub Repository name

### Full Setup (Deployment Pipeline)
- [ ] Supabase Project URL
- [ ] Supabase Service Role Key
- [ ] GitHub Personal Access Token
- [ ] GitHub Repository name
- [ ] Vercel Access Token
- [ ] Fly.io API Token
- [ ] Redis Connection URL
- [ ] Anthropic API Key (for sub-agents)

---

## OAuth vs API Keys

| Auth Type | Used By | When to Use |
|-----------|---------|-------------|
| **API Key** | Supabase, Anthropic, Vercel, Fly.io | Server-to-server, backend operations |
| **Personal Access Token** | GitHub | User-level access, scoped permissions |
| **OAuth** | (Not typically needed) | User-facing apps with login flows |

For Claude IDE, you'll primarily use **API Keys** and **Personal Access Tokens**. OAuth is only needed if you're building user-facing applications that require user login.

---

## Token Expiration & Rotation

### Recommended Expiration Settings

| Service | Recommended Expiration | Rotation Frequency |
|---------|------------------------|-------------------|
| GitHub PAT | 90 days | Quarterly |
| Vercel Token | 1 year | Annually |
| Fly.io Token | No expiration | As needed |
| Supabase Keys | No expiration* | If compromised |
| Anthropic API | No expiration | If compromised |

*Supabase keys can be rotated in Settings → API → "Generate new keys"

### Rotation Checklist

When rotating credentials:
1. Generate new credential
2. Update Claude Project Instructions
3. Test connection works
4. Revoke old credential
5. Update any deployed services using the credential

---

## Troubleshooting Auth Issues

### "Invalid API key" / 401 Unauthorized

- Verify key is copied correctly (no extra spaces)
- Check key hasn't expired
- Confirm key has required scopes/permissions
- Try generating a new key

### "Access denied" / 403 Forbidden

- Check if resource exists and you have access
- Verify team/org permissions
- Confirm key scope includes required permissions

### "Connection refused"

- Verify URL is correct (no typos, correct protocol)
- Check service is online (status pages)
- Confirm network/firewall allows connection

### Supabase-Specific Issues

| Error | Solution |
|-------|----------|
| "Invalid JWT" | Using wrong key (anon vs service_role) |
| "relation does not exist" | Run schema SQL first |
| "permission denied" | Use service_role key, not anon |

---

## Summary Table

| Service | Required? | Credential Type | Where to Store |
|---------|-----------|-----------------|----------------|
| Supabase | ✅ Yes | Service Role Key | Project Instructions |
| GitHub | ⚪ Optional | Personal Access Token | Project Instructions |
| Anthropic | ⚪ Optional | API Key | Project Instructions |
| Vercel | ⚪ Optional | Access Token | Project Instructions |
| Fly.io | ⚪ Optional | API Token | Project Instructions |
| Redis | ⚪ Optional | Connection URL | Project Instructions |

**Minimum to get started**: Just Supabase URL + Service Role Key
