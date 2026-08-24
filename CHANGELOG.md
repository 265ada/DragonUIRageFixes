# Changelog

Running list of individual fixes, in the order they were added. Each fix
is self-contained in `DragonUIRageFixes.lua` and gated behind its own
saved-variable toggle, off by default unless noted.

## Unreleased

- **Quick re-entry no longer prompts.** Returning to the same instance
  within 2 minutes is now assumed to be the same run and passes silently --
  no prompt, no reset. Stepping out to repair, taking a summon, or a slow
  zone-in all land well inside that, and nobody finishes a dungeon and
  restarts it that fast, so there's nothing genuinely ambiguous to ask
  about.

  Past that window it stays ambiguous and still asks. `/duf reentrywindow
  <seconds>` tunes it (default 120).

- **Instance re-entry now asks instead of guessing.** Replaces the
  time-window heuristic, which was wrong often enough in both directions.

  Entering a *different* instance still clears automatically and silently --
  that stays the default behaviour and never prompts. Only the genuinely
  ambiguous case asks: you left an instance and came back to the same one,
  which could be a repair trip / summon / reconnect mid-run, or a fresh run
  of the same dungeon. A dialog offers "Clear (new run)" or "Keep (same
  run)", and nothing is cleared unless you choose to.

  A `/reload` or zoning inside the instance is not a re-entry and stays
  silent. Turn the prompt off with the "Ask when re-entering the same
  instance" option, in which case re-entry never clears anything.

  The `/duf detailsgrace` command is gone with the heuristic it configured.

- **Fixed: leaving and re-entering an instance no longer wipes your data
  mid-run.** The first version forgot which instance you were in the moment
  you left, so hearthing out to repair, getting summoned back, or
  reconnecting all looked like entering a brand-new instance and cleared
  Details' overall data halfway through the dungeon.

  3.3.5 exposes no unique per-instance id, so re-entry is judged on time:
  returning to the same instance within a grace window (default 10 minutes)
  continues the same run, while a longer absence -- or a different instance
  -- counts as new. State is persisted with epoch `time()` rather than
  `GetTime()`, so a /reload or relog inside the instance isn't mistaken for
  a fresh entry either.

  `/duf detailsgrace <minutes>` tunes the window. Known tradeoff: two
  back-to-back runs of the *same* dungeon started inside the window won't
  auto-reset -- use `/duf cleardetails` for those.

- **Auto-clear Details! overall data on entering a new instance.** Details'
  overall segment otherwise accumulates forever, so yesterday's raid keeps
  inflating today's dungeon numbers.

  Uses `Details:ResetSegmentOverallData()` -- the documented API for the
  overall segment only, so your per-fight segment history is kept
  (`ResetSegmentData()` would wipe that too). A "new instance" is a change
  in instance name + difficulty, so re-running the same dungeon counts as
  new while zoning inside one instance does not. The reset is deferred a
  couple of seconds after zone-in (Details may still be initialising) and
  deferred again while you're in combat, so it can never discard a fight in
  progress.

  On by default. `/duf detailsreset on|off`, or the options panel.
  `/duf cleardetails` resets it immediately by hand.

- **Every feature is now toggleable.** Bazaar Token tracking gained a
  toggle, and all features are listed in the `/duf` options panel with a
  generic `/duf status` readout. New fixes get a slash toggle automatically
  rather than needing bespoke command handling.

- **Fixed: nothing attached to DragonUI's bags.** The right-click menu and
  token lines targeted the stock Blizzard bag money buttons
  (`ContainerFrame*MoneyFrame*`), but DragonUI replaces the bag UI entirely
  -- its money display is a custom frame named `DragonUI_BagsterMoney<N>`
  (or `DragonUI_CombuctorMoney<N>`), so none of the hooks ever landed.
  Both are now swept, along with the stock frames, on a slow timer as well
  as on bag events -- those frames aren't created until the bag UI is first
  opened, and no event announces it.

  The token tooltip also opens standalone when nothing else owns it, since
  Combuctor (unlike Bagster) never registers with DragonUI's alt-money
  module and so has no gold tooltip to append to.

  Added `/duf moneyframes` to report which money displays got hooked.

- **Bazaar Tokens tracked per character.** DragonUI's Alt Gold tooltip only
  knew about gold; hovering the gold in your bags now also lists each
  character's Bazaar Token count, with a total.

  Bazaar Tokens are a normal *item* (id `975001`), not a currency, so the
  count comes from `GetItemCount` including the bank. Counts are stored in
  this addon's own SavedVariables rather than DragonUI's, and refresh on
  bag/bank changes.

  The tooltip lines are appended a frame after the money button's OnEnter,
  because DragonUI's own handler calls `GameTooltip:SetOwner`, which wipes
  anything added before it -- deferring makes the append independent of
  which addon hooked first.

  `/duf tokens` shows the current character's tracked counts;
  `/duf trackitem <itemID>` tracks an additional item. Deleting a character
  (right-click menu or `/duf resetgold`) now clears its tokens too.

- **Reset DragonUI's Alt Gold data.** DragonUI remembers every character's
  gold in `DragonUIDB.global.characterMoney` and offers no way to clear it,
  so renamed / deleted / transferred characters linger in the bag tooltip
  with stale amounts forever. Adds:
  `/duf goldlist` (see what's stored), `/duf resetgold` (wipe all),
  `/duf resetgold keep` (wipe all but the current character), and
  `/duf resetgold <name>` (remove one).
  The current character is re-recorded immediately; alts refresh on their
  next login. The store is wiped in place rather than replaced, because
  DragonUI's altmoney module holds a live reference to that same table.

  **Right-click the gold in your bags** to manage it where it's actually
  shown: the menu lists every recorded character (with their gold) so you
  can delete them individually, plus a confirm-gated "Reset all". On by
  default. Left-click coin pickup is untouched -- OnClick is hooked, not
  replaced, and everything but RightButton is ignored.

- **Role icons on nameplates.** Shows a small tank / healer / support icon
  beside group members' nameplates. Coexists with TurboPlates rather than
  replacing it -- it draws its own texture on the nameplate frame (anchored
  left, since TurboPlates' healer mark anchors above) and never touches
  TurboPlates' internals. Off by default.
  `/duf roleicons on|off`, or toggle from the options panel.
  `/duf roleart on|off` switches between the stock LFG role icons and
  custom `Artwork\role_tank.tga` / `role_healer.tga` / `role_support.tga`.

  Roles come from `UnitGroupRolesAssigned` (which returns
  `isTank, isHealer, isDamager` booleans on this server, not retail's role
  string). Two known limits: players **outside your group** get no icon,
  because no API on this server exposes a stranger's spec or role; and
  "support" is only detectable for your own character, since the role API
  has no support concept.

- **Slash command renamed to `/duf`.** Was `/duirf`, briefly `/duif`.
- **Options panel.** Plain `/duf` (or `/duf options`) now opens a
  checkbox panel listing every fix, built from a single options table so
  new fixes automatically get a checkbox. Closes with Escape or its own
  close button.
- **Party frame buff/debuff hover tooltip.** Hovering a party frame no
  longer pops the Blizzard buff/debuff icon tooltip when enabled --
  useful when mouseover heal/buff macros keep getting visually stepped on
  by it mid-combat. Off by default.
  `/duf partytooltip on|off`, or toggle from the options panel.
