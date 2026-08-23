# Changelog

Running list of individual fixes, in the order they were added. Each fix
is self-contained in `DragonUIRageFixes.lua` and gated behind its own
saved-variable toggle, off by default unless noted.

## Unreleased

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
