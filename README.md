# DragonUI Rage Fixes

Small standalone fixes for things about [DragonUI](https://github.com) (or
the underlying Blizzard 3.3.5a UI it skins) that got annoying enough to
fix, for Project Ascension (WoW 3.3.5a).

Kept as its own addon rather than direct edits to DragonUI's files, so a
DragonUI update never silently wipes a fix out. It works by hooking/
overriding global functions from the outside, the same way any other
addon layers on top of Blizzard's UI or another addon.

## Install

Copy the `DragonUIRageFixes` folder into `Interface/AddOns/`. Works
alongside DragonUI; not required to have DragonUI installed for the fixes
that don't specifically touch its UI, but written with DragonUI's setup
in mind.

## Commands

- `/duf` -- open the options panel (checkboxes for every fix).
- `/duf status` -- show current fix states.
- `/duf detailsreset [on|off]` -- auto-clear Details! overall data when you
  enter a new dungeon/raid. `/duf cleardetails` does it right now.
  `/duf detailsgrace <minutes>` sets how long you can step out of an
  instance before returning counts as a new run (default 10).
- `/duf tracktokens [on|off]` -- toggle Bazaar Token tracking.
- `/duf partytooltip [on|off]` -- toggle (or set) the party-frame
  buff/debuff hover tooltip. See CHANGELOG.md.
- `/duf roleicons [on|off]` -- role icons on nameplates (works alongside
  TurboPlates). `/duf rolesize <6-40>` and `/duf roleoffset <x> <y>` tune
  them; `/duf roleart [on|off]` switches to custom `Artwork\` icons.
- **Right-click the gold in your bags** to delete individual characters
  from DragonUI's Alt Gold list, or reset all of it.
- Hovering the gold in your bags also lists each character's **Bazaar
  Token** count (item `975001`, bank included).
- `/duf goldlist` -- list DragonUI's stored Alt Gold entries.
- `/duf tokens` -- show tracked item counts on this character.
- `/duf trackitem <itemID>` -- track an additional item per character.
- `/duf resetgold` -- wipe DragonUI's Alt Gold data so it re-captures.
  `/duf resetgold keep` keeps the current character; `/duf resetgold <name>`
  removes just one.

## Fixes

See [CHANGELOG.md](CHANGELOG.md) for the running, dated list of
individual fixes and their toggle commands.
