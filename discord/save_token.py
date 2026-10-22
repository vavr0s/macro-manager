#!/usr/bin/env python3
"""Asks for the Discord bot token (hidden input) and stores it for update_discord.py in
%APPDATA%\\ComboCrownDiscord\\token.txt (your Windows profile only, never in the repository)."""
import getpass, os
d = os.path.join(os.environ['APPDATA'], 'ComboCrownDiscord')
os.makedirs(d, exist_ok=True)
t = getpass.getpass('Discord bot token (input is hidden): ').strip()
if not t:
    raise SystemExit('nothing entered, nothing saved')
open(os.path.join(d, 'token.txt'), 'w', encoding='utf-8').write(t)
print('saved to', os.path.join(d, 'token.txt'))
