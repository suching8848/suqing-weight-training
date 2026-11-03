# Artwork

`masters/training-belt-master.png` and `masters/cover-master.png` are generated with the built-in imagegen tool. The cover follows the user's original silver-haired dragon character reference and approved previous cover style. The original references are retained locally under `references/`, excluded from the public Git candidate.

`category-training-belt.svg` is an original code-authored vector glyph. Textured generated drafts were rejected because they were unclear at tiny UI sizes. `tools/export_artwork.ps1` rasterizes this SVG geometry and exports images at their intended sizes without cropping.

- Inventory: `SuQingWeightTraining/42/media/textures/Item_SQWT_TrainingBelt.png`, 128 square with transparency.
- Crafting category: `SuQingWeightTraining/42/media/ui/CategoryIcon/SuQingTrainingBelt.png`, 128 square with transparency. Automatically used by Neat Crafting when present; the vanilla category remains text-only.
- Mod icon: `SuQingWeightTraining/42/icon.png`, 128 square.
- Mod poster: `SuQingWeightTraining/42/poster.png`, 512 square.
- Workshop preview: `publishing/preview.png`, 256 square.
- Large promotional image: `publishing/cover-1024.png`, 1024 square.

The cover contains no game or mod version number. These images do not add a worn character texture, mesh or ground model. See `prompts.json` for the final prompts. New artwork still requires visual acceptance in the game UI.
