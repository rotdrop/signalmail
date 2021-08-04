# signalmail

signalmail is a Python script adapted from signalbot using DBus but with a more specific focus: forwarding Signal messages via Email. It's relying on signal-cli (https://github.com/AsamK/signal-cli) in daemon mode to fetch the actual messages. Configuration is done in by copying config_default.ini to $HOME/.local/share/signalmail/config.ini and modifying it.

## CLI arguments

You may pass the following arguments to signalbot.py to overwrite defaults set in config.ini:

- `--no-sendmail` override config and do not send mail
- `--debug` override config and switch on debug mode
- `--keepattachments` override config and keep attachments after processing
- `--autoreply` text of a reply to each incoming Signal message
- `--autoattach` path to file to send as attachment with autoreply

## Known issues

- users are untrusted if they reinstall Signal and therefore messages 
  don't come through. See https://github.com/AsamK/signal-cli/wiki/Manage-trusted-keys 

  As a workaround using signal-cli:
	- If you don't care about security, you can manually trust the new key   
   `signal-cli -u yourNumber trust -a untrustedNumber`
	- Better is to verify it with the remote number's SAFETY_NUMBER  
   `signal-cli -u yourNumber trust -v SAFETY_NUMBER -a untrustedNumber`


## ToDos

- add possibility to choose between multiple groups to be forwarded to different recipients
- get System DBus connection working

