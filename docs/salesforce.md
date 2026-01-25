# Salesforce Integration Setup

Salesforce OAuth setup is more involved than other providers. Follow these steps exactly.

## Create Connected App

1. Log into your Salesforce org (or create a [Developer Edition](https://developer.salesforce.com/signup))
2. Go to **Setup** (gear icon)
3. Search for **App Manager** in Quick Find
4. Click **New Connected App** (top right)

## Basic Info

- Connected App Name: `Social Scribe` (or your choice)
- API Name: auto-fills
- Contact Email: your email

## API (Enable OAuth Settings)

Check **Enable OAuth Settings**, then:

1. **Callback URL**: `http://localhost:4000/auth/salesforce/callback`

2. **Selected OAuth Scopes** - add these:
   - `api` (Access the identity URL service)
   - `refresh_token` (Perform requests at any time)
   - `offline_access` (Perform requests at any time)

3. **Require Proof Key for Code Exchange (PKCE)**: **UNCHECK THIS**
   - Our OAuth flow doesn't use PKCE
   - Leaving it checked will cause auth failures

## Save and Wait

1. Click **Save**
2. Click **Continue**
3. **Wait 2-10 minutes** for Salesforce to propagate settings

## Get Credentials

1. Go back to **App Manager**
2. Find your app, click dropdown arrow > **View**
3. Under **API (Enable OAuth Settings)**:
   - Click **Manage Consumer Details**
   - Verify your identity
   - Copy **Consumer Key** (this is your Client ID)
   - Copy **Consumer Secret**

## Environment Variables

```bash
export SALESFORCE_CLIENT_ID=your-consumer-key
export SALESFORCE_CLIENT_SECRET=your-consumer-secret
```

## Required Scopes Summary

| Scope | Why |
|-------|-----|
| `api` | Access Salesforce REST API |
| `refresh_token` | Get refresh tokens for long-lived access |
| `offline_access` | Same as refresh_token (Salesforce wants both) |

## Common Issues

**"invalid_client_id" or "invalid_client" error**
- Wait a few minutes after creating the app
- Double-check Consumer Key is copied correctly

**"invalid_grant" error**
- PKCE is enabled - go disable it
- Callback URL mismatch

**"insufficient_scope" error**
- Missing required scopes - add `api`, `refresh_token`, `offline_access`

**"INVALID_SESSION_ID" on API calls**
- Token expired - app should auto-refresh via `SalesforceTokenRefresher`

## Alternative: External Client App Manager

If you can't find App Manager, Salesforce may route you to:
- **Setup > Platform Tools > Apps > External Client App Manager**

The steps are similar - create new app, enable OAuth, configure scopes, disable PKCE.
