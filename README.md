# Qwenventory

Chat with your own notes on your Mac and iPhone. Local models, no internet, private.

An AI agent fills `data/` with notes. The Mac app reads them with Ollama. The iPhone app gets a copy over USB and reads them with a model running on the phone. `data/` is git-ignored, so your notes never reach GitHub.

## Start

Open this folder in Claude Code (or any coding agent) and say "set it up". The agent follows `AGENTS.md`.

By hand:

```
tools/doctor.sh            # what's missing
cp -R data.example data    # then fill in data/brain.json and data/notes/
tools/install-mac.sh
tools/install-phone.sh     # don't open the app yet
tools/copy-model.sh        # model to the phone over USB
```

Update notes: edit `data/notes/`, then run `tools/push.sh`.

Want another one (new trip, new topic)? Make a fresh copy of this repo. Each copy has its own name, icon and data, and they all share the models. See `AGENTS.md`.

Needs: Apple silicon Mac, Xcode, a paid Apple Developer account, a recent iPhone Pro.

## License

GPL-3.0. Use it, change it, share it. If you share a changed version, share its code too.
