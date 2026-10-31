# Qwenventory: agent guide

Private chat with your own notes. Mac app + iPhone app, both run local models,
no internet. You (the agent) write the notes into `data/`. `data/` is
git-ignored and never leaves the user's machines.

If the user says "set it up", work through the sections below in order. Run
`tools/doctor.sh` first and after each fix. It checks everything and changes
nothing.

## How it works

- `data/notes/*.md`: the notes. `data/files/` + `data/files.json`: files to
  show (tickets, PDFs). `data/brain.json`: settings.
- **Mac app** (`mac/`): reads `data/` live. Sends all notes to Ollama
  (default `qwen3.8:27b`) with a 32k context.
- **iPhone app** (`ios/`): runs Qwen3.5 4B on the phone with MLX.
  `tools/build_kb.py` turns the notes into a SQLite search index
  (`Brain.db`). Each question gets the `00-index` note, today's and
  tomorrow's schedule, and the 6 best matching sections (9000 chars max).
- **Sync**: `tools/push.sh` copies the index, prompt and files to the phone
  over USB or local Wi-Fi with `devicectl`. No cloud.

## 1. Mac setup (once)

Needs an Apple silicon Mac. For `qwen3.8:27b` you need about 32 GB of RAM
(the model is ~17 GB). On a smaller Mac, pull a smaller Ollama model and set
`mac_model` in `data/brain.json`.

1. **Xcode** from the App Store (tested with Xcode 26.6). Open it once and
   let it install its extra parts. Then:
   ```
   sudo xcodebuild -license accept
   xcodebuild -runFirstLaunch
   xcodebuild -downloadPlatform iOS
   xcodebuild -downloadComponent MetalToolchain   # MLX needs it to build
   ```
   If `xcode-select -p` shows `/Library/Developer/CommandLineTools`, that's
   fine. The scripts set `DEVELOPER_DIR` to Xcode themselves. For your own
   commands, `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
2. **Tools**:
   ```
   brew install xcodegen
   brew install --cask ollama        # then open Ollama once
   brew install pipx && pipx install huggingface_hub   # gives the `hf` command
   ollama pull qwen3.8:27b
   ```
3. **Optional**, to test the phone's model on the Mac:
   ```
   python3 -m venv build/lmenv && build/lmenv/bin/pip install mlx-lm
   ```

## 2. Apple account (once, the user has to do this)

- A **paid Apple Developer account** ($99/year). The app uses two
  capabilities, App Groups and Increased Memory Limit, that need it. We only
  tested with a paid account. Free accounts also make apps expire after 7
  days.
- **Sign in to Xcode**: Xcode > Settings > Apple Accounts > Add Apple
  Account. You can't do this step from the terminal. Ask the user.
- **Xcode 26 gotcha**: even when signed in, `xcodebuild` may still say `No
  Accounts` and `Provisioning profile ... doesn't include the App Groups
  capability`. It can't see the new Apple Accounts login. A build inside
  Xcode makes the profile, and after that the command line works.
  `tools/install-phone.sh` does this by itself: it opens the project in
  Xcode and builds it with AppleScript. Don't ask the user to sign in again
  if Settings > Apple Accounts already shows their team.
- **Team ID**: developer.apple.com/account > Membership details. 10
  characters, like `AB12CD34EF`. Goes in `data/brain.json`.
- The build passes `-allowProvisioningUpdates`, so Xcode registers the bundle
  ID, the App Group and the profile by itself once the account is signed in.

## 3. iPhone setup (once)

Tested on an iPhone 17 Pro (12 GB RAM). The 4B 8-bit model needs a recent Pro
phone. The 4B 4-bit model uses less memory. The 9B model runs out of memory
on load, even on the 17 Pro.

1. Plug the phone into the Mac with a cable. Unlock it, tap **Trust**, and
   enter the passcode.
2. Turn on **Developer Mode**: Settings > Privacy & Security > Developer Mode
   > on. The phone restarts. Confirm after the restart. If the switch isn't
   there, open Xcode with the phone plugged in (Window > Devices and
   Simulators). Then it shows up.
3. Get the phone's ID:
   ```
   /Applications/Xcode.app/Contents/Developer/usr/bin/devicectl list devices
   ```
   Copy the Identifier (like `1A2B3C4D-...`) into `phone_udid` in
   `data/brain.json`.
4. After the first cable connection the phone also works over the same
   Wi-Fi. It shows as `available` in the list above.
5. The phone must be **unlocked** for installs and copies.
6. If the app says "Untrusted Developer" when you open it: Settings > General
   > VPN & Device Management > your account > Trust.

## 4. Fill in data/

```
cp -R data.example data
```

`data/brain.json`:

| key | what |
|---|---|
| `name` | App name (home screen, window title) |
| `subtitle` | Small line under the name on the phone |
| `timezone` | Where the schedule happens, like `Asia/Kolkata`. Schedule times use it |
| `home_timezone` | Optional second clock, like `America/Denver`. `""` for none |
| `examples` | Tap-to-ask questions on the empty chat screen |
| `bundle_id` | Your own, like `com.alex.qwenventory` |
| `team_id` | From step 2 |
| `app_group` | `group.<your prefix>.models`. Apps with the same team + group share model files |
| `phone_udid` | From step 3 |
| `mac_model` | Ollama model for the Mac app |
| `test_now` | Fake "now" for the tests, in `timezone` |
| `icon` | `{"symbol": "airplane", "colors": ["#F2A33A", "#C2410C"]}`. See Icon below |

Edit `data/prompt-phone.txt` and `data/prompt-mac.txt`: change "Qwenventory"
and who it's for. Keep the `{now}`, `{upcoming}`, `{notes}`, `{files}`
placeholders.

**Writing the notes** (this is your main job):

- Gather facts from wherever the user points you (email, calendar, docs).
  Write short plain notes. Facts only. Copy numbers, codes, times and
  addresses exactly.
- One topic per file. Name files `00-index.md`, `01-...`, `02-...`.
- `00-index.md` always goes to the phone model. Keep it to a few lines that
  say what's in the notes.
- Every `## ` heading starts a search section on the phone. Each section has
  to make sense alone, and should use the words people will ask with.
- Schedule: one `## Tue Nov 3 ...` heading per day (exact format: short day,
  short month, day number), then one line per item starting with the time
  (`9:00 AM ...` or `14:30 ...`). The apps use this for "today", "what's next"
  and "am I free".
- Files: put them in `data/files/` and list them in `data/files.json` with a
  title and keywords. Matching files show as tap-to-open chips.
- Keep all notes under ~100 KB. The Mac app sends all of them every time and
  has a 32k context.
- Add a test to `data/tests.json` for each important fact: a question, the
  text the answer must contain, and an optional `now`.

**Icon**: every Qwenventory gets its own icon that fits its data. Pick one:

- Set `icon` in `data/brain.json`: an SF Symbol name that fits the notes
  (`airplane`, `tent`, `cross.case`, `house`, `graduationcap`,
  `fork.knife`...) and two hex colors, top and bottom of the gradient. Pick
  colors that fit the place or topic. Check the symbol exists: `swift
  tools/make-icon.swift /tmp/t.png 256 <symbol>` fails if it doesn't. Open
  the PNG and look at it.
- Or put any 1024x1024 image at `data/icon.png` (made by an image tool, or
  a photo). It wins over `icon`.

`tools/icon.sh` builds the icons. The install scripts run it, so a new icon
just needs a rebuild of both apps.

## 5. Build and install

Order matters. The phone must never download a model itself (5 GB over
cellular, and the user hates it). The app waits for the copy and only
downloads if the user taps Download.

1. **Mac app**: `tools/install-mac.sh`. Puts it in `/Applications`. The repo
   path is baked in, so don't move the repo after this (or rebuild).
2. **iPhone app**: `tools/install-phone.sh`. The first build takes ~20 min
   (MLX). Tell the user **not to open the app yet**.
3. **Model to the phone**: `tools/copy-model.sh`. Downloads the model to the
   Mac's Hugging Face cache once, then copies it into the App Group folder
   over USB. ~5 GB, a few minutes. The App Group folder only exists after
   step 2, so it has to come after the install.
4. Now open the app on the phone. If the app was already open, switch away
   and back. It picks up the model when it comes to the front.

Other models: `tools/copy-model.sh mlx-community/Qwen3.5-4B-MLX-4bit`. To
offer a new one in the app, add it to `ios/App/LLM/BrainCatalog.swift`, copy
it, then rebuild.

## 6. Updating notes

1. Edit `data/notes/` (and files).
2. Mac app: nothing to do. It reads `data/` live.
3. Phone: `tools/push.sh`. No rebuild. It refuses if the phone is loading a
   model.
4. Check: `python3 tools/eval.py` (Mac model, all tests).
   `build/lmenv/bin/python tools/ask.py --tests` (phone model and phone
   search, run on the Mac). Both should pass before you tell the user it's
   done.

Rebuild the phone app (`tools/install-phone.sh`) only for code changes, a
new model in the catalog, or a new `name`.

## Making another Qwenventory

Each copy of this repo is one Qwenventory: its own name, icon, notes and
app. Make as many as you want (a trip, a house manual, medical info). They
sit side by side on the Mac and the phone and share one copy of the models.

1. Get a fresh copy. The repo is a GitHub template, so use "Use this
   template", or just clone it to a new folder:
   `git clone <repo url> ~/qwenventory-lisbon`. `data/` is never in git, so
   every copy starts with no data.
2. `cp -R data.example data`, then in `data/brain.json` set a new **name**,
   a new **bundle_id** (each copy must be different, like
   `com.alex.qwenventory.lisbon`) and a new **icon**. Keep the same
   **team_id** and **app_group** as your other copies. That's what makes them
   share models.
3. Fill in the notes, then build and install (section 5).
   `tools/copy-model.sh` sees the model is already on the phone and skips
   the copy.

Ollama models on the Mac are shared too: all copies use the same Ollama.

## Debugging

- Phone log: `tools/pulllog.sh`.
- Test a question on the phone with no tapping:
  `devicectl device process launch --device <udid> --environment-variables '{"BRAIN_ASK":"what is next"}' <bundle_id>`,
  then read the log.
- Simulator: no GPU, so it uses a fake model that lists the matching notes.
  Good for checking search and UI.
- Wrong answer on the phone: run `tools/ask.py --show "<question>"` to see
  exactly what the model got. Usually the right section didn't match the
  search. Fix the note's wording or heading.

## Rules

- **Never commit `data/`**. Before any commit, check that `git status` shows
  nothing under `data/`. Never paste note contents into issues, PRs or chat
  logs.
- Never make the phone download a model. Use `tools/copy-model.sh`.
- Don't install or push while the phone is loading a model (it can kill the
  load). `push.sh` checks this. For installs, ask the user first.
- Copy a model to the phone before installing a build that switches to it.
  The user tends to open the app right away.
- `devicectl` lives at `/Applications/Xcode.app/Contents/Developer/usr/bin`.
- In an App Group folder, writes only work under `Library/`.
- Changing `bundle_id` makes a new app. Changing `app_group` means copying
  the models again.
- Greedy decoding (temperature 0) and thinking off, on purpose. Sampling
  garbles codes and numbers.

## Files

```
data.example/        example data (copy to data/)
ios/App/             iPhone app (SwiftUI + MLX)
  LLM/KB.swift       search + time logic (mirrored in tools/ask.py)
  LLM/BrainCatalog.swift  phone models
mac/App/             Mac app (SwiftUI + Ollama)
tools/doctor.sh      check setup
tools/icon.sh        data/ -> app icons
tools/install-mac.sh, install-phone.sh, copy-model.sh, push.sh, pulllog.sh
tools/build_kb.py    data/ -> ios/Resources/Brain.db
tools/ask.py         phone model + search, on the Mac
tools/eval.py        Mac model tests
```
