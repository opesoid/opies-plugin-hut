# Opie Plugin Library

RuneLite plugins with a Windows setup window that installs or removes the set you choose.

Each plugin is its own jar. The client loads them from your local plugin folder the next time it starts. The jars in `dist/` are already built, so installing does not require a JDK.

| Plugin | Version | Minimum client | Jar |
| --- | --- | --- | --- |
| [OPIE] Bank Sorter | 2.3.1 | 2.0.7 | `dist/OpiesBankSorterPlugin.jar` |
| [OPIE] Sand Buyer | 1.0.3 | 1.9.6 | `dist/OpiesSandBuyerPlugin.jar` |
| [OPIE] Molten Glass | 1.0.2 | 1.9.6 | `dist/OpiesMoltenGlassPlugin.jar` |
| [OPIE] Eclipse Red | 1.2.3 | 1.9.6 | `dist/OpiesEclipseRedPlugin.jar` |

The red `[OPIE]` prefix is how these plugins show up in the client plugin list.

## Requirements

- Windows
- A RuneLite-based client that has been launched at least once, so `%USERPROFILE%\.runelite` exists
- Membership where a plugin says it needs it

Building from source also needs a network connection the first time. Gradle downloads a Java 11 toolchain and the current client jar. A newer JDK already installed on the machine is fine. The plugins are compiled for Java 11.

## Install

1. Close the game client. The setup window refuses to copy jars while the client is running, because Windows will not replace a jar that is still open.
2. Double-click `installer\OpiesPluginLibrary-Setup.bat`. The window opens on its own. The command window does not stay on screen.
3. The window title is **[OPIE] Plugin Library**. Every plugin in `dist\library.txt` is listed with a checkbox, a short description, and whether it is already installed. All available plugins start checked.
4. Uncheck anything you want to leave alone. **Select all** and **Clear** sit above the list.
5. Click **Install selected**.
6. Start the client again.
7. Open the plugin list and enable the `[OPIE]` plugins you want. They are off until you enable them.

Install does three things, and only for the plugins that are checked:

1. Reads the checked names from `dist\library.txt`.
2. Deletes any previous copy of those jar names from the client's sideload plugin folders under `%USERPROFILE%\.runelite`.
3. Copies those jars from `dist\` into the client's plugin folder, creating that folder if it is missing.

Unchecked plugins are not copied and are not deleted. Other jars in those folders are left alone.

The window stays open after Install or Uninstall and refreshes each card. The activity log at the bottom records each file it removed or copied.

## Uninstall

1. Close the game client.
2. Double-click `installer\OpiesPluginLibrary-Setup.bat`.
3. Leave checked only the plugins you want removed. Click **Uninstall selected**.

Uninstall deletes the checked jar names from the client plugin folders. Unchecked library plugins stay installed. Client settings and any other sideloaded jar stay where they are. If none of the checked plugins are installed, the window says so.

There is no separate command-line installer. The `.bat` file only opens the window, then exits so a command prompt is not left beside it.

## After you install

Restart the client before expecting a new or replaced jar to appear. Enabling a plugin in a client that was already open does not load a jar that was copied while that client was closed.

If a plugin is missing from the list:

- Confirm the jar is in the client's plugin folder and the file name matches `dist\library.txt`.
- Confirm you fully quit the client before installing. A jar copy that failed because the file was locked will show an error in the setup log.
- Confirm the client is at least the minimum version in the table above.

## Plugins

### [OPIE] Bank Sorter

Organizes an ironman-style bank into eight tabs, then sorts each category as one contiguous block. Empty placeholder slots move with the real item, so a later deposit fills the hole in the right tab.

Open the bank and use the buttons drawn on the bank interface:

- **Organize** runs the full bank.
- **Sort Tab** reorders only the tab you have open.
- **Stop** cancels between drags.

The script turns placeholders and Insert mode on. RuneLite cannot rename bank tabs. The first Organize on a large bank takes several minutes, because every move is a real drag.

Disable any other bank sorter plugin while this one is enabled. Two sorters will stack two sets of buttons.

#### Tabs

| Tab | Contents |
| --- | --- |
| Main | Coins, platinum tokens, bonds, and clues when Clues is set to Main tab |
| 1 Supplies | Teleports, potions by dose, cooked food, and drinks when they have their own block |
| 2 Combat | Weapons, armour, ammo, sets |
| 3 Gathering | Raw fish and meat, ores, logs, uncut gems, bones, hides |
| 4 Production | Skilling tools, moulds, bars, planks, leather, glass, textiles |
| 5 Runes | Runes, pouches, essence, non-teleport tablets |
| 6 Farming | Herbs, seeds, saplings, secondaries, farming supplies |
| 7 Clues | Clues when Clues is set to Clues tab, plus non-combat uniques and holiday rares |
| 8 Junk | Quest items and anything that did not match another tab |

#### Layout settings

These are in the plugin config, under Layout. Changing one takes effect on the next Organize.

| Setting | Default | Choices |
| --- | --- | --- |
| Layout | Iron 8-tab | Iron 8-tab, or Tight iron. Tight iron groups each tab by family (weapon, patch, fish, nails, and so on) and pulls leftovers such as tomato, unfinished potions, dyes, marks of grace, and sawmill coupons into a real tab. |
| Clues | Main tab | Main tab, or Clues tab. Scrolls, scroll boxes, caskets, key halves, and clue hunter gear stay together. |
| Teleport jewellery | Supplies | Supplies or Combat. Supplies also picks up passage necklaces, explorer's rings, and lyres. Chronicle stays on Supplies either way. |
| Drinks | With food | With food, or their own block on Supplies after the food. Ale and tea follow that choice. Wine of zamorak stays with herblore. |

#### Other settings

| Setting | Default | What it does |
| --- | --- | --- |
| Min move delay (ms) | 350 | Shortest wait after a successful drag. |
| Max move delay (ms) | 600 | Longest wait after a successful drag. |
| Create missing tabs | on | Creates tabs 1 through 8 only when the bank has fewer than 8 real tabs. It does not add extra tabs to a bank that already has 8. |
| Sort main tab | on | After routing, sorts leftover currency on the main tab. |
| Verbose debug logs | on | Logs every snapshot item, mismatch, and drag. |
| Capture tab screenshots | on | After Organize, saves a screenshot of each tab into the dump folder. |

#### Debug dumps

After Organize, a dump is written to:

- `%USERPROFILE%\.runelite\opie-bank-sorter\<timestamp>\`

Each run includes `layout.txt`, `layout.json`, `mismatches.txt`, `run.log`, and `tab-N-*.png` when screenshots are on. A second Organize on a bank that is already in order logs `IDEMPOTENT: 0 misplaced`.

### [OPIE] Sand Buyer

Buys 10 buckets of sand and 10 soda ash per world from the Catherby Trader Crewmember, deposits at the nearby deposit box, hops, and repeats.

Start near the Catherby charter ship, around `2796, 3414`, with coins in your inventory. Each item costs 5 coins, so one round is 100 coins. The script does not withdraw coins or open the bank for you.

Hops wait until you are idle after the deposit. It then picks a normal members world with no skill-total or other requirement. A busy hop reject retries the same world. Worlds you just left are skipped until the cooldown expires.

| Setting | Default | What it does |
| --- | --- | --- |
| Sand target (total) | 0 | Stop after this many buckets of sand. 0 means no cap. |
| Soda ash target (total) | 0 | Stop after this many soda ash. 0 means no cap. |
| Avoid empty worlds | on | Skip worlds with a very low population. |
| Avoid overcrowded worlds | on | Skip worlds with a very high population. |
| World cooldown (seconds) | 90 | Do not hop back to a world until this many seconds have passed. |
| Hide overlay | off | Hides the stats overlay. |

### [OPIE] Molten Glass

Smelts molten glass at the Edgeville furnace. Each trip withdraws 14 buckets of sand and 14 soda ash from the bank, clicks Smelt on the furnace from the bank, then deposits everything and repeats.

Start at or near Edgeville bank. Keep at least 14 sand and 14 soda ash in the bank for each trip.

| Place | Coordinates |
| --- | --- |
| Bank | `3096, 3494, 0` |
| Furnace | `3109, 3499, 0` |

The furnace is clicked from the bank. The script does not web-walk onto the furnace tile. If the bank is short of a full batch, it stops.

| Setting | Default | What it does |
| --- | --- | --- |
| Stop after molten glass | 0 | Session cap, counted when molten glass is deposited. 0 means no cap. |
| Bank PIN | empty | Four-digit PIN. Leave empty if the bank has no PIN. The field is hidden in the config panel. |
| Hide overlay | off | Hides the stats overlay. |

### [OPIE] Eclipse Red

Collects the Eclipse red spawn on the top floor of Guildmaster Apatura's quarters in the Hunter Guild, hopping safe members worlds between loots. When the inventory reaches the wine threshold, it deposits at the Hunter Guild bank.

You need membership and Hunter Guild access. Start near the guild.

| Place | Coordinates |
| --- | --- |
| Spawn tile | `1555, 3035, 2` |
| Hunter Guild bank | `1542, 3041, 0` |

The script walks to the spawn, picks up Eclipse red (item 29415) when it is on the tile, then hops. It skips PvP, high-risk, bounty, skill-total, LMS, deadman, arena, tournament, seasonal, beta, and fresh-start worlds. Worlds visited recently are skipped for the cooldown so the spawn has time to come back.

| Setting | Default | What it does |
| --- | --- | --- |
| Wine threshold | 28 | Bank when the inventory holds this many Eclipse reds. |
| Stop goal | WINES | Stop on a wine count, or on a gold target. |
| Stop after wines | 0 | Used when Stop goal is WINES. Session total. 0 means no wine cap. |
| Stop after gp (in k) | 0 | Used when Stop goal is GP. Enter thousands: 100 is 100k, 1000 is 1m. Each wine counts as 700 gp, so 100k is 143 wines. 0 means no gold cap. |
| After banking | RESUME | RESUME goes back to collecting. STOP ends the script after the deposit. |
| World cooldown (seconds) | 90 | Do not hop back to a world until this many seconds have passed. |
| Avoid empty worlds | on | Skip worlds with a very low population. |
| Avoid overcrowded worlds | on | Skip worlds with a very high population. |
| Max wait for wine (ms) | 1500 | How long to wait on the spawn tile before hopping. |
| Bank PIN | empty | Four-digit PIN. Leave empty if the bank has no PIN. The field is hidden in the config panel. |
| Hide overlay | off | Hides the stats overlay. |

## Repository layout

```
opies-plugin-hut/
  installer/OpiesPluginLibrary-Setup.bat    opens the window, then exits
  installer/OpiesPluginLibrary-Setup.vbs    hidden launcher used by the bat
  installer/OpiesPluginLibrary-Setup.ps1    the window itself
  dist/                                     built jars and library.txt
  src/main/java/.../opiebanksorter/
  src/main/java/.../opiesandbuyer/
  src/main/java/.../opiesmoltenglass/
  src/main/java/.../opieseclipsered/
  src/main/resources/.../<plugin>/docs/
  src/test/java/.../opiebanksorter/
```

Gradle treats every plugin folder that contains a `*Plugin.java` file as one plugin. Each plugin gets its own compile task and its own jar in `dist/`. `PluginConstants.java` is compiled into every jar so the `[OPIE]` name is a compile-time constant. The client jar is used to compile against and is not packed inside the plugin jars.

Keep new plugins next to the existing ones. Do not rename the package path. The client requires it.

`gradlew build` writes:

- `dist/OpiesBankSorterPlugin.jar`
- `dist/OpiesEclipseRedPlugin.jar`
- `dist/OpiesMoltenGlassPlugin.jar`
- `dist/OpiesSandBuyerPlugin.jar`
- `dist/library.txt`

Jar names are unversioned on purpose. Install replaces the file that is already in the client plugin folder.

## Build from source

From the repository root, on Windows:

```bat
gradlew.bat build
```

On macOS or Linux the same command is `./gradlew build`. The setup window is Windows-only. The jars it installs can still be copied by hand into the client plugin folder on another system.

Useful variants:

```bat
gradlew.bat test
gradlew.bat build -PpluginList=OpiesBankSorterPlugin
gradlew.bat build -PclientVersion=2.6.24
gradlew.bat build -PclientPath=C:\path\to\client.jar
```

- `test` runs the Bank Sorter classifier and tab-mover tests.
- `-PpluginList` limits the build to one plugin class name, or several names separated by commas.
- `-PclientVersion` pins the client jar. The default asks the public version endpoint for the current client and falls back to 2.6.9 if that lookup fails.
- `-PclientPath` compiles against a local client jar instead of downloading one.

The first build downloads Gradle, a Java 11 toolchain (Adoptium), and the current client jar. Later builds reuse those.

## Add a plugin

1. Create a new folder next to the existing plugin packages. The folder name is the source set name. Example: `opieexample`.
2. Add a class whose file name ends in `Plugin.java` and extends `net.runelite.client.plugins.Plugin`. The file name becomes the jar name. `OpiesExamplePlugin.java` produces `dist/OpiesExamplePlugin.jar`.
3. Put the display name together with `PluginConstants.OPIE` so the plugin list shows the red `[OPIE]` prefix.

```java
@PluginDescriptor(
        name = PluginConstants.OPIE + "Example",
        description = "What the plugin does, in one line.",
        tags = {"opie"},
        authors = {"Opie"},
        version = OpiesExamplePlugin.version,
        minClientVersion = "2.0.7",
        enabledByDefault = PluginConstants.DEFAULT_ENABLED,
        isExternal = PluginConstants.IS_EXTERNAL
)
public class OpiesExamplePlugin extends Plugin {
    public static final String version = "1.0.0";
}
```

`name`, `version`, and `minClientVersion` are required. Keep `version` as a `public static final String` on the plugin class. Bump that string on every change.

4. Add config, script, and overlay classes in the same package when the plugin needs them. Use a `Script` for the work, a `Config` interface for the panel, and an `Overlay` for the on-screen stats.
5. Put player-facing notes in that plugin's `docs/README.md` under resources. Docs are not packed into the jar.
6. If the plugin needs a library that is not already inside the client, add a `dependencies.txt` next to those docs with one Maven coordinate per line. Those coordinates are shaded into that plugin's jar only.

```
com.google.guava:guava:33.2.0-jre
```

7. Run `gradlew.bat build`. The new jar is added to `dist/` and to `dist/library.txt`. The setup window lists it automatically, checked by default. Install copies only the plugins that stay checked.

A plugin that should leave the library is removed by deleting its package and its resources, then running `gradlew.bat build` again. The build deletes `dist` jars that are no longer discovered, and rewrites `library.txt`. Uninstall on a machine that still has the old jar only removes names still listed in `library.txt`. Delete a retired jar from the client plugin folder by hand, or uninstall once before removing it from the list.

## Tests

Bank Sorter's routing and tab-move rules have unit tests next to the Bank Sorter package.

```bat
gradlew.bat test
```

Test classes share the plugin packages, so they can call package-visible helpers. They compile against the same client jar as the plugins.

## Troubleshooting

**The setup window will not install.** Close the game client, including one sitting in the tray, then click Install again. The log names the file if Windows still has it locked.

**Install says a jar is missing from dist.** `dist\library.txt` lists a file that is not next to it. Run `gradlew.bat build`, or restore the `dist` jars from the repository.

**The plugin does not appear after Install.** Restart the client. Check that the jar landed in the client plugin folder and that the client version is at least the minimum in the table at the top.

**Bank Sorter and another bank plugin both draw buttons.** Disable the other sorter. This library's sorter is the one named `[OPIE] Bank Sorter`.

**A script hops or banks and then does nothing.** Read the plugin section above for the start tile and the inventory it expects. Sand Buyer needs coins already in the inventory. Molten Glass needs 14 sand and 14 soda ash in the Edgeville bank. Eclipse Red needs you near the Hunter Guild, on a members world, with Guild access. Bank Sorter needs the bank interface open.

**Build fails looking up the client.** Pass a known version or a local jar:

```bat
gradlew.bat build -PclientVersion=2.6.24
gradlew.bat build -PclientPath=C:\path\to\client.jar
```
