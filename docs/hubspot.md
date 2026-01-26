# HubSpot Integration Setup

## Important: We Use Legacy Apps

HubSpot has two app types:
- **Public Apps** (new) - more complex setup, requires marketplace listing
- **Legacy Apps** - simpler OAuth, what we use

**You must create a Legacy App, not a Public App.**

## Create Legacy App

1. Go to [HubSpot Developer Portal](https://app.hubspot.com/developer)
2. Click **Create app**
3. Select **Legacy app** (not Public app)
4. Fill in app name and description

## Configure OAuth

1. In your app settings, go to **Auth**
2. Add redirect URL: `http://localhost:4000/auth/hubspot/callback`
3. Copy **Client ID** and **Client Secret**

## Required Scopes

**You must enable these scopes in your HubSpot app settings:**

1. In your app settings, go to **Auth** tab
2. Under **Scopes**, enable:
   - `crm.objects.contacts.read` - read contact data
   - `crm.objects.contacts.write` - update contacts  
   - `oauth` - basic OAuth
3. Save changes

These scopes are configured in `lib/ueberauth/strategy/hubspot.ex` and `config/config.exs`.

> **Note:** If you get a "scope mismatch" error, ensure the scopes enabled in HubSpot match exactly what's in the code.

## Environment Variables

```bash
export HUBSPOT_CLIENT_ID=your-client-id
export HUBSPOT_CLIENT_SECRET=your-client-secret
```

## Token Refresh

HubSpot tokens expire. The app automatically refreshes them via `HubspotTokenRefresher` Oban worker that runs every 5 minutes.

## Common Issues

**"Invalid client" error**
- You created a Public App instead of Legacy App
- Client ID/Secret mismatch

**Scopes error**
- Make sure your app has the required scopes enabled in HubSpot developer portal
