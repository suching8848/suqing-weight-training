# SuQing's Weight Training

## 42.22.2 offline compatibility candidate

`0.3.3-rc.1` is a local candidate for B42.21–42.22 single-player. Preserves the training belt item ID, worn slot, and existing training records. In-game testing on 42.22.2 is pending. The release notes below cover the published version.

Published publicly on 2026-11-03: [Workshop 3832881857](https://steamcommunity.com/sharedfiles/filedetails/?id=3832881857) · [Git source](https://github.com/suching8848/suqing-weight-training). Native submit and public query checks passed; publication, local installation and gameplay acceptance are separate. The user confirmed the personal 0.3.1 training behavior; the new 0.3.2 artwork remains unaccepted in game and the personal installation is retained.

Wear a handmade Training Belt and train all six physical skills during everyday on-foot movement.

The published release is **0.3.2**, for Project Zomboid **42.21 single-player**. Mod ID: `SuQingWeightTraining`. This update adds artwork and release materials while retaining the tested training behavior. The Workshop publication is recorded above; the personal runtime was not deployed in this batch.

[中文说明](README.md)

## Crafting and encumbrance

Craft in the **Training Belt** category using **2 clean Ripped Sheets + 1 Stone + 2 Planks**. No additional tools or skill levels are required. The native Stone item ID is `Base.Stone2`.

The belt's base weight is **10**. Native rules handle worn-item encumbrance, bag weight reduction and movement penalties. With the current default worn coefficient of 0.3, the equipped belt accounts for approximately **3** encumbrance. Total encumbrance and carrying capacity determine whether the character is overloaded or slowed; this mod adds no fixed slowdown and changes neither the global worn coefficient nor carrying capacity.

The item ID remains `SuQingWeightTraining.TrainingBelt`. Its separate body slot allows regular belts and chest rigs to remain equipped. Existing belts receive a targeted weight migration that preserves their item instance and other data, without scanning all world items.

## Movement training

Wear the belt and actually move on foot to train **Fitness, Strength, Sprinting, Sneaking, Nimble and Lightfooted**. Nearby zombies and each skill's corresponding movement stance are not required.

Each accumulated **in-game minute** of valid movement awards XP separately to all six skills. The sandbox **Training XP Multiplier** defaults to **1** and accepts decimals from **0.1 to 20**.

| Valid movement game time | Default multiplier 1: base XP per skill |
| --- | ---: |
| 1 minute | 5 |
| 10 minutes | 50 |
| 1 hour | 300 |

**Base XP per skill = valid movement game minutes × 5 × training multiplier.**

For example, a multiplier of 0.1 generates 0.5 base XP per skill per minute. These amounts enter native XP calculation, which applies global/per-skill settings, character traits, nutrition and other applicable rules. The native relationship between per-skill settings and the global setting is preserved; this mod does not apply those multipliers twice. A separate compatible protein-drink boost can still affect Strength and Fitness. That drink mod is neither included nor required.

Standing still, blocked movement without displacement, vehicles, sleep, death and detected abnormal position jumps do not count. Training uses **game time spent actually moving**, rather than distance traveled. Fast-forward follows the game clock and paused time does not count. Sub-minute progress survives save/load, with no offline XP awards. Each award uses the multiplier and applicable effects active at that time. Skills already at level 10 are skipped, and native nutrition restrictions remain effective.

## Training status panel

The panel starts hidden whenever a save is entered. Right-click an actual Training Belt and choose **Show Weight Training Status** to open it; use the same option to close it. Visibility is remembered only for the current game session.

The panel shows the current multiplier, training or pause state, movement game seconds remaining until the next award and the latest actual XP changes for all six skills. Level caps and native restrictions are identified separately when gains are zero. The panel reads state without awarding XP or advancing training; UI failure does not block training callbacks.

## Icons and cover

Version 0.3.2 adds a dedicated belt inventory icon, crafting category icon and mod cover. The category image is intended for **Neat Crafting**, which supports category artwork. The native crafting UI can still use the Training Belt text category; Neat Crafting is optional.

The cover retains SuQing's silver-white long hair, pale violet eyes, light dragon horns, pale violet wings and white scaled tail, with a weight-training theme. It does not display the game version. The new artwork does not change the character's worn appearance or the ground model.

## Compatibility and installation

The runtime uses Lua and native item, recipe and sandbox scripts. It includes **no bundled Java/JAR/DLL and no ZombieBuddy dependency**. This project targets single-player; multiplayer compatibility is not claimed.

For a local installation, place the release's `SuQingWeightTraining/` directory in the game user-data `mods/` directory, then enable `SuQingWeightTraining` in game. Exit the game normally before replacing an active local mod and retain a recoverable previous runtime package. Do not mix in the former Java implementation.

Disabling the mod stops training; XP already awarded through the native system is not removed. An upgrade does not require a world rollback or rewriting saved sandbox settings. Since 0.3.0, the baseline is 5 XP per minute rather than the 0.2.0 baseline of 1, so the same configured multiplier produces five times the former rate.

## Source and validation

| Directory | Purpose |
| --- | --- |
| `SuQingWeightTraining/` | Current runtime mod source |
| `tests/`, `tools/` | Lua behavior tests, native metadata checks and packaging tools |
| `docs/release/` | Chinese/English Workshop text, release notes and upload checklists |
| `art/`, `publishing/` | Artwork masters, prompts and Workshop materials |

Behavior checks cover Lua 5.1 and the game's Kahlua VM. Metadata and packaging checks are recorded separately from in-game acceptance. The Java metadata probe is an offline development tool and is not loaded by the mod. Packaging checks reject Java metadata and JAR/Class/DLL remnants in the runtime.

The user reported **no issues with the 0.3.1 gameplay build**. **The new 0.3.2 icons and cover still require an in-game visual check**; prior acceptance does not establish that the artwork has loaded or been published. After updating, check the item icon, crafting category, right-click panel toggle and XP awards for a skill below level 10.

See [CHANGELOG.md](CHANGELOG.md) for version history. Verify Git commits/pushes, Workshop uploads and local deployment separately.
