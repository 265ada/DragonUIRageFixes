# Changelog

Running list of individual fixes, in the order they were added. Each fix
is self-contained in `DragonUIRageFixes.lua` and gated behind its own
saved-variable toggle, off by default unless noted.

## Unreleased

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
