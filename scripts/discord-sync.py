#!/usr/bin/env python3
"""
Discord message sync to SQLite.

Fetches messages from all configured Discord channels and stores them in SQLite.
Designed to run via cron every 5 minutes.

Usage:
    discord-sync.py [--db PATH] [--token-file PATH] [--guild-id ID] [--full]

Config:
    Token:    ~/.config/motley-crew/discord-token (or --token-file or DISCORD_BOT_TOKEN env)
    Guild ID: ~/.config/motley-crew/guild-id (or --guild-id or DISCORD_GUILD_ID env)
    DB:       ~/.config/motley-crew/discord.db (or --db)
"""

import argparse
import json
import os
import sqlite3
import sys
import urllib.request
from datetime import datetime, timezone

DEFAULT_DB = os.path.expanduser("~/.config/motley-crew/discord.db")
DEFAULT_TOKEN_FILE = os.path.expanduser("~/.config/motley-crew/discord-token")
DEFAULT_GUILD_FILE = os.path.expanduser("~/.config/motley-crew/guild-id")

API_BASE = "https://discord.com/api/v10"


def load_token(token_file):
    """Load bot token from file or env."""
    token = os.environ.get("DISCORD_BOT_TOKEN", "")
    if not token and os.path.isfile(token_file):
        token = open(token_file).read().strip()
    if not token:
        print(f"ERROR: No token found. Set DISCORD_BOT_TOKEN or create {token_file}", file=sys.stderr)
        sys.exit(1)
    return token


def load_guild_id(guild_file):
    """Load guild ID from file or env."""
    gid = os.environ.get("DISCORD_GUILD_ID", "")
    if not gid and os.path.isfile(guild_file):
        gid = open(guild_file).read().strip()
    if not gid:
        print(f"ERROR: No guild ID. Set DISCORD_GUILD_ID or create {guild_file}", file=sys.stderr)
        sys.exit(1)
    return gid


def api_get(token, endpoint):
    """Make a GET request to the Discord API."""
    req = urllib.request.Request(
        f"{API_BASE}{endpoint}",
        headers={
            "Authorization": f"Bot {token}",
            "User-Agent": "MotleyCrewSync/1.0 (https://github.com/johnnylambada/motley-crew)"
        }
    )
    try:
        resp = urllib.request.urlopen(req)
        return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        print(f"API error {e.code}: {e.read().decode()}", file=sys.stderr)
        return None


def init_db(db_path):
    """Initialize SQLite database."""
    os.makedirs(os.path.dirname(db_path), exist_ok=True)
    conn = sqlite3.connect(db_path)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS messages (
            id TEXT PRIMARY KEY,
            date TEXT NOT NULL,
            channel_id TEXT NOT NULL,
            channel_name TEXT,
            from_name TEXT,
            from_id TEXT,
            text TEXT,
            raw JSON
        )
    """)
    conn.execute("CREATE INDEX IF NOT EXISTS idx_date ON messages(date)")
    conn.execute("CREATE INDEX IF NOT EXISTS idx_channel ON messages(channel_id)")
    conn.execute("CREATE INDEX IF NOT EXISTS idx_channel_date ON messages(channel_id, date)")
    conn.commit()
    return conn


def get_channels(token, guild_id):
    """Get all text channels in the guild."""
    channels = api_get(token, f"/guilds/{guild_id}/channels")
    if not channels:
        return []
    # type 0 = text channel
    return [(c["id"], c["name"]) for c in channels if c.get("type") == 0]


def get_latest_message_id(conn, channel_id):
    """Get the most recent message ID we have for a channel."""
    row = conn.execute(
        "SELECT id FROM messages WHERE channel_id = ? ORDER BY date DESC LIMIT 1",
        (channel_id,)
    ).fetchone()
    return row[0] if row else None


def fetch_messages(token, channel_id, after=None, limit=100):
    """Fetch messages from a channel, optionally after a specific message ID."""
    params = f"?limit={limit}"
    if after:
        params += f"&after={after}"
    return api_get(token, f"/channels/{channel_id}/messages{params}") or []


def sync_channel(conn, token, channel_id, channel_name, full=False):
    """Sync messages for a single channel."""
    after = None if full else get_latest_message_id(conn, channel_id)
    
    total = 0
    while True:
        messages = fetch_messages(token, channel_id, after=after)
        if not messages:
            break
        
        # Messages come newest-first; reverse for chronological insert
        messages.sort(key=lambda m: m["id"])
        
        for msg in messages:
            # Parse timestamp
            ts = msg.get("timestamp", "")
            
            # Author info
            author = msg.get("author", {})
            from_name = author.get("global_name") or author.get("username", "Unknown")
            from_id = author.get("id", "")
            
            # Message content
            text = msg.get("content", "")
            
            # Include embeds and attachments in text
            for embed in msg.get("embeds", []):
                if embed.get("description"):
                    text += f"\n[embed: {embed['description'][:200]}]"
            for att in msg.get("attachments", []):
                text += f"\n[attachment: {att.get('filename', 'file')}]"
            
            conn.execute("""
                INSERT OR REPLACE INTO messages (id, date, channel_id, channel_name, from_name, from_id, text, raw)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                msg["id"],
                ts,
                channel_id,
                channel_name,
                from_name,
                from_id,
                text,
                json.dumps(msg)
            ))
            total += 1
        
        # If we got a full page, there might be more
        if len(messages) >= 100:
            after = messages[-1]["id"]
        else:
            break
    
    conn.commit()
    return total


def main():
    parser = argparse.ArgumentParser(description="Sync Discord messages to SQLite")
    parser.add_argument("--db", default=DEFAULT_DB, help="SQLite database path")
    parser.add_argument("--token-file", default=DEFAULT_TOKEN_FILE, help="Bot token file")
    parser.add_argument("--guild-id", default=None, help="Discord guild ID")
    parser.add_argument("--full", action="store_true", help="Full sync (not just new messages)")
    parser.add_argument("--quiet", action="store_true", help="Suppress output")
    args = parser.parse_args()
    
    token = load_token(args.token_file)
    guild_id = args.guild_id or load_guild_id(DEFAULT_GUILD_FILE)
    conn = init_db(args.db)
    
    channels = get_channels(token, guild_id)
    if not channels:
        print("No text channels found.", file=sys.stderr)
        sys.exit(1)
    
    total = 0
    for channel_id, channel_name in channels:
        count = sync_channel(conn, token, channel_id, channel_name, full=args.full)
        total += count
        if not args.quiet and count > 0:
            print(f"#{channel_name}: {count} new messages")
    
    if not args.quiet:
        row = conn.execute("SELECT COUNT(*) FROM messages").fetchone()
        print(f"Total messages in DB: {row[0]} ({total} new)")
    
    conn.close()


if __name__ == "__main__":
    main()
