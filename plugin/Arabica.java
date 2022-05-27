import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.ObjectInputStream;
import java.io.ObjectOutputStream;
import java.nio.file.FileVisitResult;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.SimpleFileVisitor;
import java.nio.file.attribute.BasicFileAttributes;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Enumeration;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.SortedSet;
import java.util.TreeSet;
import java.util.jar.JarEntry;
import java.util.jar.JarFile;
import java.util.zip.GZIPInputStream;
import java.util.zip.GZIPOutputStream;

public final class Arabica {

    static Map<String, SortedSet<String>> classes = new HashMap<>();

    static void indexJar(String path) throws IOException {
        JarFile jar = new JarFile(path);
        for (Enumeration<JarEntry> entries = jar.entries(); entries.hasMoreElements(); ) {
            JarEntry entry = entries.nextElement();
            String entryName = entry.getName();
            if (entryName.endsWith(".class")) {
                String fullName = entryName.substring(0, entryName.length() - 6).replace('/', '.');
                int sep = fullName.lastIndexOf('.');
                String shortName = (sep == -1) ? fullName : fullName.substring(sep + 1);
                SortedSet<String> old = classes.get(shortName);
                if (old == null) {
                    old = new TreeSet<String>();
                    classes.put(shortName, old);
                }
                old.add(fullName);
                // System.err.println(fullName + ": " + shortName);
            }
        }
        jar.close();
    }

    static List<String> findProjectJars() throws IOException {
        List<String> paths = new ArrayList<>();
        Files.walkFileTree(
                Paths.get(System.getProperty("user.dir")),
                new SimpleFileVisitor<Path>() {
                    @Override
                    public FileVisitResult visitFile(Path file, BasicFileAttributes attrs)
                            throws IOException {
                        if (!Files.isHidden(file)
                                && file.getFileName().toString().endsWith(".jar")) {
                            paths.add(file.toString());
                        }
                        return FileVisitResult.CONTINUE;
                    }

                    @Override
                    public FileVisitResult preVisitDirectory(Path dir, BasicFileAttributes attrs)
                            throws IOException {
                        if (Files.isHidden(dir)) {
                            return FileVisitResult.SKIP_SUBTREE;
                        }
                        return FileVisitResult.CONTINUE;
                    }
                });
        return paths;
    }

    static void indexClasses(List<String> paths) {
        System.out.println(paths.size());
        System.out.flush();
        for (int i = 0; i < paths.size(); ++i) {
            String path = paths.get(i);
            try {
                indexJar(path);
                System.out.printf("[%d/%d] index %s\n", i + 1, paths.size(), path);
            } catch (IOException ex) {
                System.out.printf(
                        "[%d/%d] index %s: %s\n", i + 1, paths.size(), path, ex.getMessage());
            }
            System.out.flush();
        }
        save();
        System.gc();
    }

    static void selectClasses(String name) {
        SortedSet<String> fullNames = classes.get(name);
        if (fullNames == null) {
            System.out.println();
            return;
        }
        System.out.println(String.join(" ", new ArrayList<String>(fullNames)));
    }

    static void save() {
        String filename = getDatabasePath();
        File file = new File(filename).getParentFile();
        if (file != null) {
            file.mkdirs();
        }
        try (ObjectOutputStream out =
                new ObjectOutputStream(new GZIPOutputStream(new FileOutputStream(filename)))) {
            out.writeObject(classes);
        } catch (IOException ex) {
            System.out.printf("error writing %s: %s\n", filename, ex.getMessage());
        }
    }

    @SuppressWarnings("unchecked")
    static void load() {
        String filename = getDatabasePath();
        try (ObjectInputStream in =
                new ObjectInputStream(new GZIPInputStream(new FileInputStream(filename)))) {
            classes = (Map<String, SortedSet<String>>) in.readObject();
        } catch (Exception ex) {
            System.out.printf("error reading %s: %s\n", filename, ex.getMessage());
        }
    }

    public static void main(String[] args) throws IOException {
        load();
        BufferedReader reader = new BufferedReader(new InputStreamReader(System.in));
        while (true) {
            String line = reader.readLine();
            if (line == null) {
                break;
            }
            line = line.trim();
            if (line.equals("exit")) {
                break;
            }
            if (line.isEmpty()) {
                continue;
            }
            String[] arguments = line.split("\\s+");
            if (arguments.length == 0) {
                break;
            }
            switch (arguments[0]) {
                case "index":
                    if (arguments.length < 2) {
                        continue;
                    }
                    List<String> paths = findProjectJars();
                    paths.addAll(Arrays.asList(Arrays.copyOfRange(arguments, 1, arguments.length)));
                    indexClasses(paths);
                    break;
                case "select":
                    if (arguments.length < 2) {
                        continue;
                    }
                    selectClasses(arguments[1]);
                    break;
            }
        }
    }

    static String getDatabasePath() {
        final String filename = "arabica.db";
        String path = null;
        try {
            List<String> lines = execute("git", "rev-parse", "--show-toplevel");
            if (!lines.isEmpty()) {
                path = Paths.get(lines.get(0), ".git", filename).toString();
            }
        } catch (Exception ex) {
            System.err.println(ex.getMessage());
        }
        if (path != null) {
            return path;
        }
        path = Paths.get(".git", filename).toString();
        return path;
    }

    static List<String> execute(String... args) throws IOException, InterruptedException {
        return execute(Arrays.asList(args));
    }

    static List<String> execute(List<String> args) throws IOException, InterruptedException {
        ProcessBuilder builder = new ProcessBuilder(args);
        Process process = builder.start();
        List<String> lines = new ArrayList<>();
        try (BufferedReader reader = new BufferedReader(new InputStreamReader(process.getInputStream()))) {
            String line;
            while ((line = reader.readLine()) != null) {
                lines.add(line);
            }
        }
        int exitValue = process.waitFor();
        if (exitValue != 0) {
            throw new RuntimeException(
                    "command " + builder.command() + " exited with status=" + exitValue);
        }
        return lines;
    }
}
