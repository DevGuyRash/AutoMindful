import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.luaj.compiler.LuaCompiler;
import se.krka.kahlua.vm.JavaFunction;
import se.krka.kahlua.vm.KahluaTable;
import se.krka.kahlua.vm.KahluaThread;
import se.krka.kahlua.vm.LuaClosure;

public final class KahluaCheck {
    public static void main(String[] args) throws Exception {
        Path root = Path.of(args[0]).toRealPath();
        Path modules = root.resolve("mods/AutoMindful/common/media/lua/client");
        Path references = args.length > 1 ? Path.of(args[1]).toRealPath() : null;
        J2SEPlatform platform = J2SEPlatform.getInstance();
        KahluaTable environment = platform.newEnvironment();
        KahluaThread thread = new KahluaThread(System.out, platform, environment);
        thread.debugOwnerThread = Thread.currentThread();
        KahluaTable packageTable = platform.newTable();
        KahluaTable loaded = platform.newTable();
        KahluaTable preload = platform.newTable();
        packageTable.rawset("path", "");
        packageTable.rawset("loaded", loaded);
        packageTable.rawset("preload", preload);
        environment.rawset("package", packageTable);
        environment.rawset("require", (JavaFunction) (frame, count) -> {
            String name = (String) frame.get(0);
            if (loaded.rawget(name) == null || Boolean.FALSE.equals(loaded.rawget(name))) {
                Object value;
                if (preload.rawget(name) != null) {
                    value = thread.call(preload.rawget(name), new Object[0]);
                } else {
                    value = evaluate(thread, environment, within(modules, name + ".lua"));
                }
                loaded.rawset(name, value == null ? Boolean.TRUE : value);
            }
            return frame.push(loaded.rawget(name));
        });
        environment.rawset("loadTest", (JavaFunction) (frame, count) -> frame.push(
                evaluate(thread, environment, within(root.resolve("tests"), (String) frame.get(0)))));
        if (references != null) {
            environment.rawset("readReference", (JavaFunction) (frame, count) -> {
                try {
                    return frame.push(Files.readString(within(references, (String) frame.get(0))));
                } catch (IOException failure) {
                    throw new IllegalArgumentException("Cannot read installed reference", failure);
                }
            });
            environment.rawset("loadUpstream", (JavaFunction) (frame, count) -> frame.push(
                    evaluate(thread, environment, within(references.resolve("lua"), (String) frame.get(0)))));
        }
        evaluate(thread, environment, root.resolve("tests/contracts.lua"));
        System.out.println("KAHLUA PASS; installed interpreter with explicit game-boundary doubles");
    }

    private static Path within(Path base, String name) {
        Path path = base.resolve(name).normalize();
        if (!path.startsWith(base)) throw new IllegalArgumentException("Path outside allowed source tree");
        return path;
    }

    private static Object evaluate(KahluaThread thread, KahluaTable environment, Path file) {
        try {
            LuaClosure closure = LuaCompiler.loadstring(Files.readString(file), file.toString(), environment);
            return thread.call(closure, new Object[0]);
        } catch (IOException failure) {
            throw new IllegalArgumentException("Cannot load " + file, failure);
        }
    }
}
