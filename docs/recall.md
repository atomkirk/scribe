# Recall.ai Setup

Recall.ai provides the meeting bot that joins calls and captures transcripts.

## Get API Key

1. Create account at [recall.ai](https://www.recall.ai/)
2. Go to your dashboard
3. Copy your API key

## Get Your Region

**This is critical and easy to miss.**

Your Recall.ai account is tied to a specific region. Using the wrong region will cause API calls to fail silently or return errors.

Check your dashboard URL or settings for your region:
- `us-west-2` (US West)
- `eu-west-1` (EU)
- Other regions as available

## Environment Variables

```bash
export RECALL_API_KEY=your-api-key
export RECALL_REGION=us-west-2  # MUST match your account region
```

## How It Works

1. User toggles "Record Meeting" on a calendar event
2. App extracts meeting link (Zoom/Google Meet) from event
3. Recall bot joins meeting at configured time before start
4. After meeting, app polls for transcript
5. Transcript is processed by AI for follow-up content

## Docs

- [Recall.ai Quickstart](https://docs.recall.ai/docs/quickstart)
- [Bot API Reference](https://docs.recall.ai/reference)
