// ServiceManager.swift — dsh web 服务的启动 / 停止 / 探测
import Darwin
import Foundation

enum ServiceManager {

    static let host = "127.0.0.1"
    static let port: UInt16 = 3080

    // 保活：Process/FileHandle 全局持有，避免对象被提前释放
    private static var keepAlive: [AnyObject] = []

    // MARK: - 凭据（API key）通用管线
    //
    // 设计原则：本 App 不枚举任何具体的 key 名。
    // 权威来源是 dsh 自己的用户级环境文件 `$DSH_HOME/.env` —— dsh 启动时由
    // dsh-app-boot 的 loadLayeredEnv 读取并注入进程环境，因此：
    //   · 对所有 profile、所有启动方式（本 App / 终端 / IDE）都生效；
    //   · 未来接入任何新 API，只需往该文件加一行，不必改本 App。
    // shell rc 扫描只作兜底（老用户已在 .zshrc 里 export 的 key），同样不认具体名字。

    /// 本次启动从 shell 配置兜底注入的凭据变量名（只记名字，绝不记录值；供日志展示）
    static private(set) var injectedCredentialNames: [String] = []

    /// dsh 的 home（尊重 DSH_HOME，缺省 ~/.dsh）
    static func dshHomeURL() -> URL {
        if let raw = ProcessInfo.processInfo.environment["DSH_HOME"], !raw.isEmpty {
            return URL(fileURLWithPath: (raw as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".dsh", isDirectory: true)
    }

    /// dsh 原生支持的“用户级环境文件”：对所有 profile 生效，且不随仓库分发
    static func envFileURL() -> URL {
        dshHomeURL().appendingPathComponent(".env")
    }

    static func shellConfigFiles() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [".zshenv", ".zprofile", ".zshrc", ".bash_profile", ".bashrc", ".profile"]
            .map { home + "/" + $0 }
    }

    /// 变量名是否“像凭据”——用于从 shell 配置里兜底捞取，不依赖具体 provider
    static func looksLikeCredential(_ name: String) -> Bool {
        guard looksLikeEnvName(name) else { return false }
        let parts = name.uppercased().split(separator: "_").map(String.init)
        let markers: Set<String> = [
            "KEY", "KEYS", "TOKEN", "TOKENS", "SECRET", "SECRETS",
            "PASSWORD", "PASSWD", "CREDENTIAL", "CREDENTIALS",
        ]
        guard parts.contains(where: { markers.contains($0) }) else { return false }
        // 排除“名字里有 KEY 但其实是路径”的变量
        if let last = parts.last, ["PATH", "FILE", "DIR", "URL", "URI"].contains(last) { return false }
        return true
    }

    private static func looksLikeEnvName(_ name: String) -> Bool {
        name.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil
    }

    /// 解析 KEY=VALUE 形式的环境文件：支持 `export ` 前缀、单双引号、行尾注释。
    /// 无法静态求值（含 $VAR / $(cmd) / 反引号）的值一律丢弃：宁可漏，也不注入错值。
    static func parseEnvFile(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("export ") { line = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let name = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            guard looksLikeEnvName(name) else { continue }
            let value = unquote(String(line[line.index(after: eq)...]))
            guard !value.isEmpty, isStaticallyResolvable(value) else { continue }
            if out[name] == nil { out[name] = value }
        }
        return out
    }

    private static func unquote(_ raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("'"), let end = s.dropFirst().firstIndex(of: "'") {
            return String(s[s.index(after: s.startIndex)..<end])
        }
        if s.hasPrefix("\""), let end = s.dropFirst().firstIndex(of: "\"") {
            return String(s[s.index(after: s.startIndex)..<end])
        }
        if let end = s.firstIndex(where: { $0 == " " || $0 == "\t" || $0 == "#" }) {
            return String(s[..<end])
        }
        return s
    }

    /// 值为字面量（不是需要 shell 求值的引用/替换）
    private static func isStaticallyResolvable(_ value: String) -> Bool {
        !value.contains("$") && !value.contains("`")
    }

    /// 从 shell 配置文件兜底收集凭据（先出现的文件优先；同名只取第一个）
    static func credentialsFromShell() -> [String: String] {
        var out: [String: String] = [:]
        for file in shellConfigFiles() {
            guard let text = try? String(contentsOfFile: file, encoding: .utf8) else { continue }
            for (name, value) in parseEnvFile(text) where looksLikeCredential(name) {
                if out[name] == nil { out[name] = value }
            }
        }
        return out
    }

    /// 把 shell 里兜底找到的凭据补进子进程环境：只补还没有的（进程环境优先级最高，
    /// 与 dsh 自己对 .env 的规则一致）。`$DSH_HOME/.env` 交给 dsh 自己读取，这里不重复注入，
    /// 避免两套解析器对同一个值产生分歧。
    static func applyCredentialFallback(to env: inout [String: String]) {
        injectedCredentialNames = []
        for (name, value) in credentialsFromShell() where env[name] == nil {
            env[name] = value
            injectedCredentialNames.append(name)
        }
        injectedCredentialNames.sort()
    }

    /// 凭据一览（只给名字，绝不带值），供环境自检展示
    struct CredentialReport {
        var envFilePath: String
        var envFileNames: [String]
        var shellNames: [String]
        var processNames: [String]
        /// 去重后的全部名字（同一个 key 来自多处也只出现一次）
        var allNames: [String] {
            var seen = Set<String>()
            return (processNames + envFileNames + shellNames).filter { seen.insert($0).inserted }.sorted()
        }
    }

    static func credentialReport() -> CredentialReport {
        let processNames = ProcessInfo.processInfo.environment
            .filter { looksLikeCredential($0.key) && !$0.value.isEmpty }
            .map { $0.key }
            .sorted()
        let fileText = (try? String(contentsOf: envFileURL(), encoding: .utf8)) ?? ""
        let fileNames = parseEnvFile(fileText).keys
            .filter { looksLikeCredential($0) }
            .sorted()
        let shellNames = credentialsFromShell().keys.sorted()
        return CredentialReport(
            envFilePath: envFileURL().path,
            envFileNames: fileNames,
            shellNames: shellNames,
            processNames: processNames
        )
    }

    /// 确保 `$DSH_HOME/.env` 存在（不存在则写入带注释的模板，权限 0600）。
    /// 返回该文件 URL；写入失败返回 nil。
    static func ensureEnvFileTemplate() -> URL? {
        let url = envFileURL()
        let fm = FileManager.default
        try? fm.createDirectory(at: dshHomeURL(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: url.path) {
            do { try envFileTemplate.write(to: url, atomically: true, encoding: .utf8) }
            catch { return nil }
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        return url
    }

    /// 模板注释：新增任何 API 只需按 KEY=VALUE 加一行，本 App 不需要跟着改。
    private static let envFileTemplate = """
    # DeepSeek Harness · 用户级环境变量（仅本机，请勿提交到 Git）
    # dsh 启动时会自动读取本文件并注入到插件与工具进程，对所有 profile 生效。
    # 用法：每行 KEY=VALUE；以 # 开头为注释；不要写 export，也不要写 $VAR 引用。
    #
    # Local environment variables for DeepSeek Harness. dsh loads this file at
    # startup and injects it into every plugin/tool process, for all profiles.
    # One KEY=VALUE per line; comments start with #.
    #
    # ── 示例（去掉行首的 # 并填入真实值即可）────────────────────
    #
    # 鲸鱼娘 Galgame 升级 CG（阿里云百炼 DashScope / 通义万相）
    # DASHSCOPE_API_KEY=sk-xxxxxxxxxxxxxxxx
    # （新加坡/国际站账号还需把 dashscopeBaseUrl 指向 dashscope-intl.aliyuncs.com）
    #
    # 即梦 AI（火山引擎，经 MCP 接入）
    # JIMENG_ACCESS_KEY_ID=
    # JIMENG_SECRET_ACCESS_KEY=
    #
    # DeepSeek 官方模型
    # DEEPSEEK_API_KEY=

    """

    /// 非阻塞 TCP 探测端口是否可连（服务是否在运行）
    static func isRunning(host: String = host, port: UInt16 = port, timeout: TimeInterval = 0.6) -> Bool {
        isPortOpen(host, port, timeout: timeout)
    }

    static func isPortOpen(_ host: String, _ port: UInt16, timeout: TimeInterval) -> Bool {
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &addr.sin_addr) == 1 else { return false }
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        let rc = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                connect(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if rc == 0 { return true }
        guard errno == EINPROGRESS else { return false }
        var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        let r = poll(&pfd, 1, Int32(timeout * 1000))
        if r <= 0 { return false }
        var err: Int32 = 0
        var len = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &len)
        return err == 0
    }

    /// 从 dsh 启动日志中提取最近一次「带 token 的访问 URL」。
    /// dsh web 启动时会把形如 http://127.0.0.1:3080/?token=… 的地址打印到 stdout（我们重定向到 dsh-web.log）。
    /// 不带 token 直接访问会得到 401，因此打开页面时应优先用带 token 的地址。
    /// dock-bridge 插件写出的运行时文件（可用 DSH_DOCK_RUNTIME 覆盖）
    static var dockRuntimePath: URL {
        if let env = ProcessInfo.processInfo.environment["DSH_DOCK_RUNTIME"], !env.isEmpty {
            return URL(fileURLWithPath: env)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/dsh-dock-launcher/runtime.json")
    }

    /// 进程是否仍存活（kill(pid, 0) 只做存在性探测，不发送信号）
    static func processIsAlive(pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }

    /// 从 dock-bridge 插件的运行时文件读取带 token 的地址。
    /// 只有「上报端口 == 当前端口」「PID 仍存活」「端口可连」三条同时成立才采信，
    /// 否则说明文件是崩溃残留，继续回退到日志解析。
    static func tokenURLFromDockBridge(port: UInt16 = port) -> URL? {
        guard let data = try? Data(contentsOf: dockRuntimePath),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = obj["url"] as? String,
              let url = URL(string: raw),
              url.scheme == "http",
              let filePort = obj["port"] as? Int, filePort > 0, UInt16(filePort) == port,
              let filePid = obj["pid"] as? Int, processIsAlive(pid: Int32(filePid)),
              isPortOpen(host, port, timeout: 0.2)
        else { return nil }
        return url
    }

    /// 从 dsh 启动日志里解析带 token 的地址（插件未安装时的回退路径）
    static func tokenURLFromLog(port: UInt16 = port) -> URL? {
        let log = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/dsh-web.log")
        guard let text = try? String(contentsOf: log, encoding: .utf8) else { return nil }
        for host in ["127.0.0.1", "localhost"] {
            let needle = "http://\(host):\(port)/?token="
            guard let range = text.range(of: needle, options: .backwards) else { continue }
            let token = text[range.upperBound...].prefix { ch in
                ch.isLetter || ch.isNumber || ch == "_" || ch == "-"
            }
            if !token.isEmpty, let url = URL(string: needle + token) { return url }
        }
        return nil
    }

    /// 带 token 的完整地址：优先用 dock-bridge 插件写的运行时文件，回退到启动日志
    static func webURLWithToken(port: UInt16 = port) -> URL? {
        if let url = tokenURLFromDockBridge(port: port) { return url }
        return tokenURLFromLog(port: port)
    }

    /// 脱敏后的地址（用于日志，避免把 token 写进日志）
    static func redactedWebURL(port: UInt16 = port) -> String {
        "http://127.0.0.1:\(port)/?token=***"
    }

    /// 定位 dsh 可执行文件
    static func findDsh() -> URL? {
        let candidates = [
            "/opt/homebrew/bin/dsh",
            "/usr/local/bin/dsh",
            "/usr/bin/dsh",
        ]
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) {
            return URL(fileURLWithPath: c)
        }
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for dir in path.split(separator: ":") where !dir.isEmpty {
                let u = URL(fileURLWithPath: String(dir)).appendingPathComponent("dsh")
                if FileManager.default.isExecutableFile(atPath: u.path) { return u }
            }
        }
        return nil
    }

    /// 后台启动 dsh web，stdout/stderr 写 ~/Library/Logs/dsh-web.log
    static func start(host: String = host, port: UInt16 = port) -> Bool {
        guard let bin = findDsh() else { return false }
        let logsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs")
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        let outURL = logsDir.appendingPathComponent("dsh-web.log")
        FileManager.default.createFile(atPath: outURL.path, contents: nil)
        guard let fh = try? FileHandle(forWritingTo: outURL) else { return false }
        fh.seekToEndOfFile()

        let p = Process()
        p.executableURL = bin
        p.arguments = ["web"]
        var env = ProcessInfo.processInfo.environment
        let core = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(core)"  // env node 脚本需要 node
        // GUI 启动的进程环境精简、不读 .zshrc：兜底补上 shell 里已有的凭据（不限具体 key 名）。
        // 权威来源仍是 $DSH_HOME/.env —— 那份由 dsh 自己读取，这里不重复注入。
        applyCredentialFallback(to: &env)
        p.environment = env
        p.standardOutput = fh
        p.standardError = fh
        do {
            try p.run()
            keepAlive.append(p)
            keepAlive.append(fh)
            return true
        } catch {
            return false
        }
    }

    /// 停止端口上的 dsh web 进程（以监听进程为准，杀进程树）
    static func stop(port: UInt16 = port) -> Bool {
        let pids = pidOnPort(port)
        guard !pids.isEmpty else { return false }
        for pid in pids { kill(pid, SIGTERM) }
        // 稍候强制兜底
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) {
            for pid in pidOnPort(port) { kill(pid, SIGKILL) }
        }
        return true
    }

    /// 查找监听某端口的进程 PID（/usr/sbin/lsof）
    static func pidOnPort(_ port: UInt16) -> [pid_t] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        p.arguments = ["-ti", "tcp:\(port)"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            p.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            return text.split(whereSeparator: { $0.isNewline || $0 == " " })
                .compactMap { pid_t($0) }
        } catch {
            return []
        }
    }

    /// 端口开放等待：轮询直到服务在 port 上可连
    static func waitUntilRunning(host: String = host, port: UInt16 = port, timeout: TimeInterval = 120) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isRunning(host: host, port: port, timeout: 0.4) { return true }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return false
    }
}
