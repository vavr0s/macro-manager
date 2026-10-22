# Discord server tools

The bot keeps the ComboCrown Discord server up to date (Discord REST API, Python standard library only).

- `texts.md` - texts of the bot's messages per channel (`## channel`, `---` = next message, max 2000 characters,
  `<#channel>` becomes a link). A forum channel gets the text as the bot's own post.
- `py save_token.py` - asks for the bot token (hidden) and stores it in `%APPDATA%\ComboCrownDiscord\token.txt`;
  the token is never put into the repository.
- `py update_discord.py` - preview; `py update_discord.py --apply` - renames leftovers of the old name
  (server, channels, roles, webhooks; webhooks get `icon.png`) and rewrites the bot's messages in place.
  Roles managed by an integration (a bot's own role) can't be renamed through the API.
