import AppKit

/// File and folder icons from the free Flow Icons pack ("Flow Deep"), read
/// from the VS Code icon theme that scripts/fetch-flow-icons.sh installs.
/// Resolution follows VS Code: file name, then compound and simple
/// extensions, then the language the extension belongs to.
final class FlowIcons {
    static let shared = FlowIcons()

    private struct Theme {
        var file = "file"
        var folder = "folder_gray"
        var folderExpanded = "folder_gray_open"
        var fileNames: [String: String] = [:]
        var fileExtensions: [String: String] = [:]
        var folderNames: [String: String] = [:]
        var folderNamesExpanded: [String: String] = [:]
        var languageIds: [String: String] = [:]
    }

    private let base = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support/rexmod/flow-icons")
    private var defs: [String: String] = [:]
    private var dark: Theme?
    private var light: Theme?
    private var images: [String: NSImage] = [:]

    var available: Bool { dark != nil }

    private init() { load() }

    private func load() {
        guard let data = try? Data(contentsOf: base.appendingPathComponent("deep.json")),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let d = j["iconDefinitions"] as? [String: [String: Any]]
        else {
            RM.log("flow icons not found in \(base.path); run scripts/fetch-flow-icons.sh")
            return
        }
        for (name, v) in d {
            if let p = v["iconPath"] as? String { defs[name] = p }
        }
        func apply(_ src: [String: Any], to t: inout Theme) {
            if let s = src["file"] as? String { t.file = s }
            if let s = src["folder"] as? String { t.folder = s }
            if let s = src["folderExpanded"] as? String { t.folderExpanded = s }
            func lower(_ m: [String: String]) -> [String: String] {
                Dictionary(m.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { a, _ in a })
            }
            if let m = src["fileNames"] as? [String: String] { t.fileNames.merge(lower(m)) { $1 } }
            if let m = src["fileExtensions"] as? [String: String] { t.fileExtensions.merge(lower(m)) { $1 } }
            if let m = src["folderNames"] as? [String: String] { t.folderNames.merge(lower(m)) { $1 } }
            if let m = src["folderNamesExpanded"] as? [String: String] { t.folderNamesExpanded.merge(lower(m)) { $1 } }
            if let m = src["languageIds"] as? [String: String] { t.languageIds.merge(m) { $1 } }
        }
        var dk = Theme()
        apply(j, to: &dk)
        var lt = dk
        if let l = j["light"] as? [String: Any] { apply(l, to: &lt) }
        dark = dk
        light = lt
    }

    private func image(_ def: String) -> NSImage? {
        if let img = images[def] { return img }
        guard let rel = defs[def] else { return nil }
        let url = base.appendingPathComponent(rel.hasPrefix("./") ? String(rel.dropFirst(2)) : rel)
        guard let img = NSImage(contentsOf: url) else { return nil }
        images[def] = img
        return img
    }

    func file(_ name: String, dark isDark: Bool) -> NSImage? {
        guard let t = isDark ? dark : light else { return nil }
        let lower = name.lowercased()
        if let d = t.fileNames[lower], let img = image(d) { return img }
        // "foo.test.ts" tries "test.ts", then "ts".
        var parts = lower.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        if parts.count > 1 {
            parts.removeFirst()
            while !parts.isEmpty {
                let ext = parts.joined(separator: ".")
                if let d = t.fileExtensions[ext], let img = image(d) { return img }
                if parts.count == 1, let lang = Self.languageByExtension[ext], let d = t.languageIds[lang], let img = image(d) {
                    return img
                }
                parts.removeFirst()
            }
        }
        if let lang = Self.languageByName[lower], let d = t.languageIds[lang], let img = image(d) { return img }
        return image(t.file)
    }

    func folder(_ name: String, open: Bool, dark isDark: Bool) -> NSImage? {
        guard let t = isDark ? dark : light else { return nil }
        // A compressed row like "cmd/ryui" takes the icon of its last folder.
        let leaf = (name.split(separator: "/").last.map(String.init) ?? name).lowercased()
        if open, let d = t.folderNamesExpanded[leaf], let img = image(d) { return img }
        if !open, let d = t.folderNames[leaf], let img = image(d) { return img }
        return image(open ? t.folderExpanded : t.folder)
    }

    /// VS Code assigns most extensions through languages; this mirrors the
    /// built-in language contributions for the common ones.
    static let languageByExtension: [String: String] = [
        "ts": "typescript", "mts": "typescript", "cts": "typescript", "tsx": "typescriptreact",
        "js": "javascript", "mjs": "javascript", "cjs": "javascript", "jsx": "javascriptreact",
        "go": "go", "py": "python", "pyi": "python", "rs": "rust", "swift": "swift", "rb": "ruby",
        "java": "java", "kt": "kotlin", "kts": "kotlin", "c": "c", "h": "c", "cpp": "cpp", "cc": "cpp",
        "cxx": "cpp", "hpp": "cpp", "hh": "cpp", "m": "objective-c", "mm": "objective-c", "cs": "csharp",
        "fs": "fsharp", "php": "php", "lua": "lua", "luau": "luau", "sh": "shellscript", "bash": "shellscript",
        "zsh": "shellscript", "fish": "shellscript", "json": "json", "jsonc": "jsonc", "json5": "json5",
        "jsonl": "jsonl", "md": "markdown", "markdown": "markdown", "yaml": "yaml", "yml": "yaml",
        "toml": "toml", "html": "html", "htm": "html", "css": "css", "scss": "scss", "sass": "sass",
        "less": "less", "styl": "stylus", "xml": "xml", "plist": "xml", "svg": "svg", "vue": "vue",
        "svelte": "svelte", "astro": "astro", "dart": "dart", "ex": "elixir", "exs": "elixir", "erl": "erlang",
        "hs": "haskell", "ml": "ocaml", "mli": "ocaml", "scala": "scala", "r": "r", "pl": "perl",
        "graphql": "graphql", "gql": "graphql", "proto": "proto", "tf": "terraform", "nix": "nix",
        "zig": "zig", "clj": "clojure", "cljs": "clojurescript", "groovy": "groovy", "gradle": "gradle",
        "ps1": "powershell", "ini": "ini", "cfg": "ini", "conf": "ini", "properties": "properties",
        "txt": "plaintext", "diff": "diff", "patch": "diff", "csv": "csv", "tsv": "tsv", "sql": "sql",
        "tex": "latex", "typ": "typst", "gleam": "gleam", "jl": "julia", "nim": "nim", "elm": "elm",
        "sol": "solidity", "vim": "viml", "pdf": "pdf", "ipynb": "jupyter", "env": "dotenv",
        "liquid": "liquid", "hbs": "handlebars", "pug": "pug", "twig": "twig", "v": "v", "vala": "vala",
    ]

    static let languageByName: [String: String] = [
        "dockerfile": "dockerfile", "makefile": "makefile", "gnumakefile": "makefile",
        ".env": "dotenv", ".editorconfig": "editorconfig", ".gitignore": "git", ".gitattributes": "git",
        "cmakelists.txt": "cmake", "requirements.txt": "pip-requirements",
    ]
}
