import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import javax.xml.parsers.DocumentBuilderFactory;
import org.w3c.dom.Document;
import zombie.characters.WornItems.BodyLocationGroup;
import zombie.characters.WornItems.BodyLocations;
import zombie.config.DoubleConfigOption;
import zombie.inventory.InventoryItem;
import zombie.inventory.ItemContainer;
import zombie.inventory.types.Clothing;
import zombie.inventory.types.InventoryContainer;
import zombie.sandbox.CustomDoubleSandboxOption;
import zombie.scripting.ScriptParser;
import zombie.scripting.objects.ItemBodyLocation;
import zombie.scripting.objects.ResourceLocation;

/**
 * Uses the installed game's pure script parser and native slot registry in an
 * isolated JVM. It never boots the game or loads a player/save.
 */
public final class MetadataParserProbe {
    private static int checks;

    private static void check(boolean result, String message) {
        checks++;
        if (!result) throw new AssertionError(message);
    }

    private static ScriptParser.Block parse(Path path) throws Exception {
        String text = Files.readString(path, StandardCharsets.UTF_8);
        return ScriptParser.parse(ScriptParser.stripComments(text));
    }

    private static ScriptParser.Block block(ScriptParser.Block parent, String type, String id) {
        for (ScriptParser.Block child : parent.children) {
            if (type.equals(child.type) && (id == null ? child.id == null : id.equals(child.id))) {
                return child;
            }
        }
        throw new AssertionError("Missing native-parsed block: " + type + " " + id);
    }

    private static String value(ScriptParser.Block block, String key) {
        ScriptParser.Value value = block.getValue(key);
        return value == null ? null : value.getValue().trim();
    }

    private static String normalize(String value) {
        return value.replaceAll("\\s+", "");
    }

    private static String quoted(String text) {
        return "\"" + text.replace("\\", "\\\\").replace("\"", "\\\"")
            .replace("\n", "\\n").replace("\r", "\\r") + "\"";
    }

    public static void main(String[] args) throws Exception {
        if (args.length != 2) throw new IllegalArgumentException("game-root mod-42-root");
        Path game = Path.of(args[0]);
        Path mod = Path.of(args[1]);

        ScriptParser.Block itemRoot = parse(mod.resolve("media/scripts/SuQingWeightTraining_Items.txt"));
        check(itemRoot.children.size() == 1, "Item file has exactly one module");
        ScriptParser.Block itemModule = block(itemRoot, "module", "SuQingWeightTraining");
        ScriptParser.Block item = block(itemModule, "item", "TrainingBelt");
        check("base:clothing".equals(value(item, "ItemType")), "B42 clothing ItemType");
        check("10.0".equals(value(item, "Weight")), "Item native weight is ten");
        String locationId = value(item, "BodyLocation");
        check("suqingweighttraining:suqingtrainingbelt".equals(locationId), "Namespaced custom slot");
        check(value(item, "RunSpeedModifier") == null, "No script-based movement modifier");
        check(value(item, "AttachmentsProvided") == null, "No duplicate normal-belt attachment slots");

        ScriptParser.Block recipeRoot = parse(mod.resolve("media/scripts/SuQingWeightTraining_Recipes.txt"));
        check(recipeRoot.children.size() == 1, "Recipe file has exactly one module");
        ScriptParser.Block recipeModule = block(recipeRoot, "module", "SuQingWeightTraining");
        ScriptParser.Block recipe = block(recipeModule, "craftRecipe", "SuQingWeightTraining_MakeTrainingBelt");
        check("Making".equals(value(recipe, "timedAction")), "Uses native Making action");
        check("60".equals(value(recipe, "time")), "Recipe time parsed correctly");
        check("InHandCraft".equals(value(recipe, "Tags")), "Recipe is craftable in hand");
        check("SuQingTrainingBelt".equals(value(recipe, "category")), "Independent training-belt recipe category");
        check(value(recipe, "SkillRequired") == null, "No skill prerequisite");
        check(value(recipe, "needToBeLearn") == null, "No learned-recipe prerequisite");
        check(value(recipe, "xpAward") == null, "No unsolicited crafting XP reward");
        ScriptParser.Block inputs = block(recipe, "inputs", null);
        check(inputs.values.size() == 3, "Exactly three material inputs and no tool input");
        String[] expected = {
            "item2[Base.RippedSheets]mode:destroyflags[ItemCount]",
            "item1[Base.Stone2]mode:destroyflags[ItemCount]",
            "item2[Base.Plank]mode:destroyflags[ItemCount]"
        };
        List<String> parsedInputs = new ArrayList<>();
        for (int i = 0; i < expected.length; i++) {
            String line = normalize(inputs.values.get(i).string);
            check(expected[i].equals(line), "Exact material/count/destruction semantics for input " + i);
            parsedInputs.add(line);
        }
        ScriptParser.Block outputs = block(recipe, "outputs", null);
        check(outputs.values.size() == 1, "Exactly one product output");
        check("item1SuQingWeightTraining.TrainingBelt".equals(normalize(outputs.values.get(0).string)),
            "Product FullType and quantity");

        ScriptParser.Block sandbox = parse(mod.resolve("media/sandbox-options.txt"));
        check("1".equals(value(sandbox, "VERSION")), "Sandbox format version");
        ScriptParser.Block option = block(sandbox, "option", "SuQingWeightTraining.XPMultiplier");
        check("double".equals(value(option, "type")), "Double multiplier permits fractional values");
        check("0.1".equals(value(option, "min")), "Multiplier minimum");
        check("20".equals(value(option, "max")), "Multiplier maximum");
        check("1".equals(value(option, "default")), "Multiplier default");
        check("SuQingWeightTraining".equals(value(option, "page")), "Sandbox page");

        // Parse only this custom option; never construct the global SandboxOptions
        // singleton or open a save. The game uses DoubleConfigOption for values.
        Method parseDouble = CustomDoubleSandboxOption.class.getDeclaredMethod("parse", ScriptParser.Block.class);
        parseDouble.setAccessible(true);
        CustomDoubleSandboxOption parsedDouble = (CustomDoubleSandboxOption) parseDouble.invoke(null, option);
        check(parsedDouble != null, "Native custom double-option parser accepts the sandbox block");
        check(parsedDouble.min == 0.1 && parsedDouble.max == 20.0, "Native custom-option fractional bounds");
        check(parsedDouble.defaultValue == 1.0, "Native custom-option default remains one");
        DoubleConfigOption savedValue = new DoubleConfigOption("SuQingWeightTraining.XPMultiplier",
            parsedDouble.min, parsedDouble.max, parsedDouble.defaultValue);
        check(savedValue.getValue() == 1.0, "Native double config starts at the new default");
        String[] savedStrings = { "20", "5", "0.1", "0.35" };
        double[] expectedValues = { 20.0, 5.0, 0.1, 0.35 };
        for (int i = 0; i < savedStrings.length; i++) {
            check(savedValue.isValidString(savedStrings[i]), "Native double config accepts saved string " + savedStrings[i]);
            savedValue.parse(savedStrings[i]);
            check(savedValue.getValue() == expectedValues[i], "Native saved numeric value preserved without integer rounding: " + savedStrings[i]);
        }
        check(!savedValue.isValidString("0.01"), "Native double config rejects below-minimum input");
        check(!savedValue.isValidString("20.1"), "Native double config rejects above-maximum input");
        check(!savedValue.isValidString("invalid"), "Native double config rejects non-numeric input");
        savedValue.resetToDefault();
        check(savedValue.getValue() == 1.0, "Native reset returns to one, independently of old saved values");

        Path itemDirectory = game.resolve("media/scripts/generated/items");
        ScriptParser.Block normalModule = block(parse(itemDirectory.resolve("normal.txt")), "module", "Base");
        ScriptParser.Block weaponModule = block(parse(itemDirectory.resolve("weapon.txt")), "module", "Base");
        Map<String, String> materialTypes = new LinkedHashMap<>();
        materialTypes.put("Base.RippedSheets", value(block(normalModule, "item", "RippedSheets"), "ItemType"));
        materialTypes.put("Base.Stone2", value(block(weaponModule, "item", "Stone2"), "ItemType"));
        materialTypes.put("Base.Plank", value(block(weaponModule, "item", "Plank"), "ItemType"));
        check("base:normal".equals(materialTypes.get("Base.RippedSheets")), "Actual RippedSheets exists/type");
        check("base:weapon".equals(materialTypes.get("Base.Stone2")), "Actual stone is Base.Stone2/type");
        check("base:weapon".equals(materialTypes.get("Base.Plank")), "Actual Plank exists/type");

        ScriptParser.Block clothes = block(parse(itemDirectory.resolve("clothing.txt")), "module", "Base");
        ScriptParser.Block originalBelt = block(clothes, "item", "Belt2");
        check("SQWT_TrainingBelt".equals(value(item, "Icon")), "Uses the standalone training-belt inventory icon");
        check(Files.isRegularFile(mod.resolve("media/textures/Item_SQWT_TrainingBelt.png")),
            "Custom inventory icon exists in the runtime package");
        check(value(originalBelt, "ClothingItem").equals(value(item, "ClothingItem")),
            "Reuses the native clothing asset, not a new unverified asset");
        check(("Base." + value(originalBelt, "WorldStaticModel")).equals(value(item, "WorldStaticModel")),
            "Uses the same native ground model, fully qualified");
        ScriptParser.Block models = block(parse(game.resolve("media/scripts/generated/models_items.txt")),
            "module", "Base");
        check(block(models, "model", "Belt_Ground") != null, "Native ground-model definition exists");
        ScriptParser.Block actions = block(parse(game.resolve("media/scripts/generated/timedactions.txt")),
            "module", "Base");
        check(block(actions, "timedAction", "Making") != null, "Native Making timed action exists");

        Path clothingXml = game.resolve("media/clothing/clothingItems/Belt.xml");
        Document document = DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(clothingXml.toFile());
        check("clothingItem".equals(document.getDocumentElement().getTagName()), "Native clothing XML loads");
        check("emptytexture".equals(document.getElementsByTagName("m_BaseTextures").item(0).getTextContent()),
            "Stock belt uses its existing empty texture; no new visible mesh is claimed");

        ResourceLocation resource = ResourceLocation.of(locationId);
        ItemBodyLocation custom = ItemBodyLocation.get(resource);
        if (custom == null) custom = ItemBodyLocation.register(locationId);
        check(custom == ItemBodyLocation.get(resource), "Native custom slot registry identity");
        BodyLocationGroup group = BodyLocations.getGroup("SuQingWeightTraining_IsolatedMetadataTest");
        Object baseBelt = group.getOrCreateLocation(ItemBodyLocation.BELT);
        Object baseRig = group.getOrCreateLocation(ItemBodyLocation.WEBBING);
        Object first = group.getOrCreateLocation(custom);
        check(first == group.getOrCreateLocation(custom), "Native slot creation is idempotent");
        check(baseBelt == group.getLocation(ItemBodyLocation.BELT), "Existing belt slot remains intact");
        check(baseRig == group.getLocation(ItemBodyLocation.WEBBING), "Existing webbing slot remains intact");
        check(!group.isExclusive(custom, ItemBodyLocation.BELT), "Training slot does not exclude belt");
        check(!group.isExclusive(ItemBodyLocation.BELT, custom), "Belt does not exclude training slot");
        check(!group.isExclusive(custom, ItemBodyLocation.WEBBING), "Training slot does not exclude webbing");
        check(!group.isExclusive(ItemBodyLocation.WEBBING, custom), "Webbing does not exclude training slot");

        check(InventoryItem.class.getMethod("setActualWeight", float.class).getReturnType() == void.class,
            "Native actual-weight setter exists with float argument");
        check(InventoryItem.class.getMethod("setWeight", float.class).getReturnType() == void.class,
            "Native display-weight setter exists with float argument");
        check(InventoryItem.class.getMethod("setCustomWeight", boolean.class).getReturnType() == void.class,
            "Native custom-weight persistence flag setter exists");
        check(InventoryItem.class.getMethod("isCustomWeight").getReturnType() == boolean.class,
            "Native custom-weight persistence flag getter exists");
        check(InventoryItem.class.getMethod("getModData").getReturnType().getName()
            .equals("se.krka.kahlua.vm.KahluaTable"), "Native per-item persistent modData API");
        check(Clothing.class.getMethod("setActualWeight", float.class).getDeclaringClass() == InventoryItem.class,
            "Clothing inherits native actual-weight migration setter");
        check(Clothing.class.getMethod("setCustomWeight", boolean.class).getDeclaringClass() == InventoryItem.class,
            "Clothing inherits native persistence flag setter");
        check(InventoryContainer.class.getMethod("getInventory").getReturnType() == ItemContainer.class,
            "Native nested wearable/bag inventory traversal API");
        check(java.util.List.class.isAssignableFrom(ItemContainer.class.getMethod("getItems").getReturnType()),
            "Native ItemContainer items expose list size/get traversal");

        StringBuilder json = new StringBuilder("{\"result\":\"PASS\",\"nativeChecks\":");
        json.append(checks).append(",\"nativeParser\":\"zombie.scripting.ScriptParser\",")
            .append("\"recipeFullType\":\"SuQingWeightTraining.SuQingWeightTraining_MakeTrainingBelt\",")
            .append("\"bodyLocationId\":").append(quoted(locationId)).append(",\"materials\":{");
        boolean comma = false;
        for (Map.Entry<String, String> entry : materialTypes.entrySet()) {
            if (comma) json.append(',');
            comma = true;
            json.append(quoted(entry.getKey())).append(':').append(quoted(entry.getValue()));
        }
        json.append("},\"nativeSlotRegistryAndCoexistence\":\"PASS\",")
            .append("\"nativeSavedItemMigrationAPIs\":\"PASS: actual/display/custom-weight setters, item modData, nested inventory list\",")
            .append("\"itemWeight\":10.0,")
            .append("\"craftCategory\":\"SuQingTrainingBelt\",")
            .append("\"nativeCraftCategoryTranslationKey\":\"IGUI_CraftingCategories_SuQingTrainingBelt\",")
            .append("\"sandboxMultiplier\":{\"type\":\"double\",\"min\":0.1,\"max\":20,\"default\":1},")
            .append("\"nativeDoubleOptionParsing\":\"PASS: isolated CustomDoubleSandboxOption.parse and DoubleConfigOption saved strings 20, 5, 0.1, 0.35; no global SandboxOptions instance\",")
            .append("\"beltAppearance\":\"stock Belt.xml emptytexture; stock ground model\",")
            .append("\"scope\":\"Isolated native parser and body-slot APIs; no full ScriptManager, player, save, rendering or crafting action loaded\"}");
        System.out.println("METADATA_RESULT_JSON:" + json);
    }
}
