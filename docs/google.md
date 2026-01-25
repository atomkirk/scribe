# Google OAuth Setup

## Create OAuth Client

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select existing
3. Go to **APIs & Services > Credentials**
4. Click **Create Credentials > OAuth client ID**
5. Select **Web application**
6. Add authorized redirect URI: `http://localhost:4000/auth/google/callback`
7. Copy **Client ID** and **Client Secret** to your `.env`

## Enable Required APIs

**This step is easy to miss and causes cryptic errors.**

1. Go to **APIs & Services > Library**
2. Search and enable:
   - **Google Calendar API** (required for calendar sync)
   - Google People API is already enabled by default

## Configure OAuth Consent Screen

1. Go to **APIs & Services > OAuth consent screen**
2. Select **External** user type
3. Fill in required fields (app name, support email)
4. Add scopes:
   - `openid`
   - `email`
   - `profile`
   - `https://www.googleapis.com/auth/calendar.readonly`
5. Add test users (while in "Testing" status)

## Environment Variables

```bash
export GOOGLE_CLIENT_ID=your-client-id.apps.googleusercontent.com
export GOOGLE_CLIENT_SECRET=your-client-secret
export GOOGLE_REDIRECT_URI=http://localhost:4000/auth/google/callback
```

## Common Issues

**"Access blocked: This app's request is invalid"**
- Redirect URI mismatch - must be exactly `http://localhost:4000/auth/google/callback`

**Calendar events not syncing**
- You didn't enable the Google Calendar API (step above)

**"Access denied" for test users**
- Add the Google account email as a test user in OAuth consent screen
