import java.nio.channels.FileChannel;
import java.nio.channels.FileLock;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.nio.file.StandardOpenOption;
import java.time.Duration;
import java.lang.foreign.Arena;
import java.lang.foreign.FunctionDescriptor;
import java.lang.foreign.Linker;
import java.lang.foreign.MemoryLayout;
import java.lang.foreign.MemorySegment;
import java.lang.foreign.SymbolLookup;
import java.lang.foreign.ValueLayout;
import java.lang.invoke.MethodHandle;
import se.krka.kahlua.luaj.compiler.LuaCompiler;
import se.krka.kahlua.vm.JavaFunction;
import zombie.Lua.LuaEventManager;
import zombie.Lua.LuaManager;
import zombie.ZomboidFileSystem;
import zombie.core.Languages;
import zombie.core.znet.SteamUtils;
import zombie.core.znet.SteamWorkshop;
import zombie.core.znet.SteamWorkshopItem;

public final class SteamWorkshopBootstrap {
    private static String createdId;
    private static boolean updated;
    private static boolean legalRequired;
    private static String failure;

    private static void listen(String event, String kind) throws Exception {
        LuaEventManager.AddEvent(event).callbacks.add(LuaCompiler.loadstring(
            "onBootstrapEvent('" + kind + "', ...)", event, LuaManager.env));
    }

    private static void await(boolean creation) throws Exception {
        long deadline = System.nanoTime() + Duration.ofSeconds(120).toNanos();
        while (failure == null && (creation ? createdId == null : !updated)) {
            if (System.nanoTime() >= deadline) throw new IllegalStateException("Steam callback timed out; inspect the existing item before retrying creation");
            SteamUtils.runLoop();
            LuaEventManager.RunQueuedEvents();
            Thread.sleep(100);
        }
        if (failure != null) throw new IllegalStateException(failure);
    }

    private static void copy(Path from, Path to) throws Exception {
        try (var paths = Files.walk(from)) {
            for (Path path : paths.toList()) {
                if (Files.isSymbolicLink(path)) throw new IllegalArgumentException("Upload staging contains a symlink");
                Path target = to.resolve(from.relativize(path));
                if (Files.isDirectory(path)) Files.createDirectories(target);
                else Files.copy(path, target, StandardCopyOption.REPLACE_EXISTING);
            }
        }
    }

    private static boolean request(String method, Class<?> type, Object argument) throws Exception {
        var function = SteamWorkshop.class.getDeclaredMethod(method, type);
        function.setAccessible(true);
        return Boolean.TRUE.equals(function.invoke(SteamWorkshop.instance, argument));
    }

    private static boolean updateContents(SteamWorkshopItem item) throws Exception {
        return request("n_StartItemUpdate", long.class, SteamUtils.convertStringToSteamID(item.getID()))
            && request("n_SetItemContent", String.class, item.getContentFolder())
            && request("n_SetItemPreview", String.class, item.getPreviewImage())
            && request("n_SubmitItemUpdate", String.class, item.getChangeNote());
    }

    private static MethodHandle steamFunction(String name, FunctionDescriptor descriptor) {
        return Linker.nativeLinker().downcallHandle(SymbolLookup.loaderLookup().find(name).orElseThrow(), descriptor);
    }

    private static void addDependency(long parent, long child) throws Throwable {
        var pointer = ValueLayout.ADDRESS;
        var integer = ValueLayout.JAVA_INT;
        var number = ValueLayout.JAVA_LONG;
        var bool = ValueLayout.JAVA_BOOLEAN;
        var ugc = (MemorySegment) steamFunction("SteamAPI_SteamUGC_v021", FunctionDescriptor.of(pointer)).invokeExact();
        var utils = (MemorySegment) steamFunction("SteamAPI_SteamUtils_v010", FunctionDescriptor.of(pointer)).invokeExact();
        if (ugc.equals(MemorySegment.NULL) || utils.equals(MemorySegment.NULL)) throw new IllegalStateException("Steam interface unavailable");
        long call = (long) steamFunction("SteamAPI_ISteamUGC_AddDependency", FunctionDescriptor.of(number, pointer, number, number)).invokeExact(ugc, parent, child);
        if (call == 0) throw new IllegalStateException("Steam refused the required-item request");
        var completed = steamFunction("SteamAPI_ISteamUtils_IsAPICallCompleted", FunctionDescriptor.of(bool, pointer, number, pointer));
        var result = steamFunction("SteamAPI_ISteamUtils_GetAPICallResult", FunctionDescriptor.of(bool, pointer, number, pointer, integer, integer, pointer));
        try (Arena arena = Arena.ofConfined()) {
            var failed = arena.allocate(bool);
            long deadline = System.nanoTime() + Duration.ofSeconds(60).toNanos();
            while (!(boolean) completed.invokeExact(utils, call, failed)) {
                if (System.nanoTime() >= deadline) throw new IllegalStateException("Required-item update timed out");
                SteamUtils.runLoop();
                Thread.sleep(100);
            }
            // Steamworks packs POSIX callbacks to 4 bytes, including the two 64-bit IDs.
            var storedNumber = number.withByteAlignment(4);
            var layout = MemoryLayout.structLayout(integer, storedNumber, storedNumber);
            var response = arena.allocate(layout);
            boolean received = (boolean) result.invokeExact(utils, call, response, (int) layout.byteSize(), 3412, failed);
            if (!received || failed.get(bool, 0) || response.get(integer, 0) != 1
                    || response.get(storedNumber, 4) != parent || response.get(storedNumber, 12) != child) {
                throw new IllegalStateException("Steam did not confirm the required-item dependency");
            }
        }
    }

    public static void main(String[] args) throws Throwable {
        boolean update = args.length == 5 && args[0].equals("update");
        boolean listing = args.length == 5 && args[0].equals("publish-listing");
        if (!update && !listing && (args.length != 3 || !java.util.Set.of("probe", "create", "resume").contains(args[0]))) {
            throw new IllegalArgumentException("Usage: SteamWorkshopBootstrap probe|create|resume STAGE CACHE; update STAGE CACHE ITEM_ID NOTES_FILE; publish-listing STAGE CACHE ITEM_ID REQUIRED_ITEM_ID");
        }
        if ((update || listing) && !args[3].matches("[1-9][0-9]*")) throw new IllegalArgumentException("An existing positive Workshop item ID is required");
        if (listing && !args[4].matches("[1-9][0-9]*")) throw new IllegalArgumentException("A positive required item ID is required");
        Path source = Path.of(args[1]).toRealPath();
        Path cache = Path.of(args[2]).toAbsolutePath();
        Files.createDirectories(cache);
        Path stage = cache.resolve("Workshop/AutoMindful");
        Files.createDirectories(stage);
        copy(source.resolve("Contents"), stage.resolve("Contents"));
        for (String name : new String[]{"workshop.txt", "preview.png"}) {
            Files.copy(source.resolve(name), stage.resolve(name), StandardCopyOption.REPLACE_EXISTING);
        }
        ZomboidFileSystem.instance.setCacheDir(cache.toString());
        ZomboidFileSystem.instance.init();
        Languages.instance.init();
        zombie.core.random.RandStandard.INSTANCE.init();
        zombie.core.random.RandLua.INSTANCE.init();
        LuaManager.init();
        LuaManager.thread.debugOwnerThread = Thread.currentThread();
        LuaManager.env.rawset("onBootstrapEvent", (JavaFunction) (frame, count) -> {
            String kind = String.valueOf(frame.get(0));
            if (kind.equals("created")) {
                createdId = String.valueOf(frame.get(1));
                legalRequired = Boolean.TRUE.equals(frame.get(2));
            } else if (kind.equals("updated")) {
                updated = true;
                legalRequired = Boolean.TRUE.equals(frame.get(1));
            } else failure = "Steam " + kind + " failed with result " + frame.get(1);
            return 0;
        });
        listen("OnSteamWorkshopItemCreated", "created");
        listen("OnSteamWorkshopItemNotCreated", "creation");
        listen("OnSteamWorkshopItemUpdated", "updated");
        listen("OnSteamWorkshopItemNotUpdated", "update");
        Path lockPath = source.getParent().resolve("." + source.getFileName() + ".bootstrap.lock");
        Path marker = source.resolve(".creation-requested");
        try (FileChannel channel = FileChannel.open(lockPath, StandardOpenOption.CREATE, StandardOpenOption.WRITE);
                FileLock lock = channel.tryLock()) {
            if (lock == null) throw new IllegalStateException("Another bootstrap owns this staging folder");
            Files.copy(source.resolve("workshop.txt"), stage.resolve("workshop.txt"), StandardCopyOption.REPLACE_EXISTING);
            SteamWorkshopItem item = new SteamWorkshopItem(stage.toString());
            if (!item.readWorkshopTxt() || (!update && !listing && !"private".equals(item.getVisibility()))) {
                throw new IllegalArgumentException("Initial upload metadata must use visibility=private");
            }
            String error = item.validateContents();
            if (error != null) throw new IllegalArgumentException(error + ": " + item.getExtendedErrorInfo(error));
            if (args[0].equals("create") && item.getID() != null) {
                throw new IllegalStateException("An item ID already exists. Use resume only to finish this initial hidden upload.");
            }
            if (args[0].equals("resume") && item.getID() == null) {
                throw new IllegalStateException("Resume requires the existing item ID in workshop.txt");
            }
            if (update || listing) item.setID(args[3]);
            SteamUtils.init();
            if (!SteamUtils.isSteamModeEnabled()) throw new IllegalStateException("Sign in to the desktop Steam client first");
            SteamWorkshop.init();
            try {
                if (args[0].equals("probe")) {
                    LuaEventManager.triggerEvent("OnSteamWorkshopItemCreated", "1", Boolean.FALSE);
                    LuaEventManager.RunQueuedEvents();
                    if (!"1".equals(createdId)) throw new IllegalStateException("Workshop callback delivery is unavailable");
                    System.out.println("STEAM_WORKSHOP_READY");
                    return;
                }
                if (listing) {
                    long id = SteamUtils.convertStringToSteamID(item.getID());
                    addDependency(id, SteamUtils.convertStringToSteamID(args[4]));
                    if (!request("n_StartItemUpdate", long.class, id)
                            || !request("n_SetItemVisibility", int.class, 0)
                            || !request("n_SubmitItemUpdate", String.class, "Publish AutoMindful with its required Lifestyle item")) {
                        throw new IllegalStateException("Steam refused publication of the listing");
                    }
                    await(false);
                    if (legalRequired) throw new IllegalStateException("The Workshop agreement requires owner action");
                    System.out.println("WORKSHOP_LISTING_PUBLIC=https://steamcommunity.com/sharedfiles/filedetails/?id=" + item.getID());
                    return;
                }
                if (item.getID() == null) {
                    if (Files.exists(marker)) throw new IllegalStateException("Creation was already requested. Inspect your Workshop items before retrying.");
                    Files.writeString(marker, "Creation requested; preserve this record until a Workshop ID is recovered.\n", StandardOpenOption.CREATE_NEW);
                    if (!item.create()) {
                        Files.delete(marker);
                        throw new IllegalStateException("Steam refused the create request");
                    }
                    try {
                        await(true);
                    } catch (IllegalStateException rejected) {
                        if (failure != null) Files.deleteIfExists(marker);
                        throw rejected;
                    }
                    if (!createdId.matches("[1-9][0-9]*")) throw new IllegalStateException("Steam returned an invalid item ID");
                    item.setID(createdId);
                    if (!item.writeWorkshopTxt()) throw new IllegalStateException("Cannot save the created Workshop ID");
                    Files.copy(stage.resolve("workshop.txt"), source.resolve("workshop.txt"), StandardCopyOption.REPLACE_EXISTING);
                    Files.deleteIfExists(marker);
                    System.out.println("WORKSHOP_ITEM_ID=" + createdId);
                    if (legalRequired) throw new IllegalStateException("Owner must accept the Steam Workshop agreement at https://steamcommunity.com/sharedfiles/workshoplegalagreement");
                }
                item.setChangeNote(update ? Files.readString(Path.of(args[4])) : "Initial AutoMindful release");
                boolean accepted = update ? updateContents(item) : SteamWorkshop.instance.SubmitWorkshopItem(item);
                if (!accepted) throw new IllegalStateException("Steam refused the upload request");
                await(false);
                if (legalRequired) throw new IllegalStateException("Owner must accept the Steam Workshop agreement");
                System.out.println("WORKSHOP_UPLOAD_COMPLETE=https://steamcommunity.com/sharedfiles/filedetails/?id=" + item.getID());
            } finally {
                SteamUtils.shutdown();
            }
        }
    }
}
