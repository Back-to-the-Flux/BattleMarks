<img src="assets/icon.png" alt="BattleMarks icon" width="96" align="right">

# BattleMarks

A raid-marker addon for **Azeroth Survivors** co-op (WoW 1.12.1 client, benilla).

When a co-op match loads, every hero in the party gets a raid marker, you included, so you can
find each other in the horde. Bosses get the skull, and the party is told who has what.

## Features

- **Markers for the whole party**: set when the match loads, and for anyone who joins later. You
  choose your own marker and each teammate's, by party slot. Markers you change by hand stay
  until the next match.
- **Markers for bosses and guardians** (skull and cross unless you pick others): the top one
  gets number 1, the next one number 2, and so on. Any more wait unmarked, and when a marked one
  dies the others move up.
- **Priority**: the final boss ranks first, then the other bosses in the order they came, and awake
  guardians get the markers when no boss is up. Switch to *Guardians first* to flip that, and turn
  on *Fill empty markers* to give markers left over to the other kind, like a guardian beside a lone
  boss. Bosses and guardians can each be turned off. Elites are never marked.
- **Solo too**: boss and guardian markers also work when you play alone (a setting).
- 1.12 can only mark an enemy someone targets or hovers over, so a marker goes up as soon as anyone
  in the party targets that enemy. The game only tells a guardian from an elite for your own target,
  so a guardian is marked once you target it.
- **Numbered markers**: one row of the eight markers for the party and one for the bosses. Click a
  marker to give it the next free number, click a numbered one to let it go. For the party, 1 is
  you and 2 to 5 are your teammates in party order (star, then circle, diamond, triangle and
  square by default); for the bosses, 1 goes to the top one, 2 to the next, up to all eight. A
  number left empty marks no one, so use BattleMarks for bosses only, the party only, or both. A
  marker used by one row can't be picked in the other.
- **Self when solo**: puts your own marker on you when you play alone too (off by default).
- **Party chat**: one line at the start, e.g. `Markers: Eric = Star, Bob = Circle.`, and with Boss
  Markers on, `Skull = top boss or guardian, Cross = second.` Both can be reworded: `{markers}`
  becomes the list of heroes, and `{first}`, `{second}` and `{kind}` the bosses' markers and who
  gets them.
- **Plays well with itself**: if several heroes run BattleMarks, one of them sets the markers (the
  party leader, else the first by name) and everyone's chosen marker is honoured.
- Minimap button and a settings window.

## Install

1. Download `BattleMarks-vX.Y.Z.zip` from [Releases](../../releases/latest).
2. Put the `BattleMarks` folder into `benilla-config/AddOns/`.
3. Restart the game.

Or add this repository in [SurvivorsForge](https://github.com/Rezondes/SurvivorsForge) (*Add repo*)
to install and update it from there.

## Use

Left-click the skull on the minimap for the settings, right-click to turn BattleMarks on or off,
drag to move it.

| Command | Does |
|---|---|
| `/bmarks` | open or close the settings |
| `/bmarks me star` | your marker: star, circle, diamond, triangle, moon, square (or 1 to 6) |
| `/bmarks now` | set the markers right away |
| `/bmarks clear` | take every hero's marker off |
| `/bmarks on` / `off` | turn it on or off |
| `/bmarks status` | your settings, and who sets the markers in this party |
| `/bmarks button` | show or hide the minimap button |

## License

MIT. Azeroth Survivors is a fan game by Aethus. This addon is not affiliated with Blizzard
Entertainment.
