// ServiceManager.swift — dsh web 服务的启动 / 停止 / 探测
import Darwin
import Foundation

enum ServiceManager {

    static let host = "127.0.0.1"
    static let port: UInt16 = 3080

    // 保活：Process/FileHandle 全局持有，避免对象被提前释放
    private static var keepAlive: [AnyObject] = []

    /// 本次启动是否注入了从 shell 配置解析出的 DEEPSEEK_API_KEY（供日志展示）
    static var keyProvisioned = false

    /// 从常见 shell 配置文件解析 DEEPSEEK_API_KEY（GUI 启动不读 .zshrc，需手动补齐）
    static func deepseekApiKeyFromShell() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let files = [".zshenv", ".zprofile", ".zshrc", ".bash_profile", ".bashrc", ".profile"]
            .map { home + "/" + $0 }
        for file in files {
            guard let text = try? String(contentsOfFile: file, encoding: .utf8) else { continue }
            for rawLine in text.split(separator: "\n") {
                var line = rawLine.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("export ") {
                    line = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces)
                }
                guard line.hasPrefix("DEEPSEEK_API_KEY=") else { continue }
                var value = String(line.dropFirst("DEEPSEEK_API_KEY=".count))
                if value.hasPrefix("'") {
                    value.removeFirst()
                    if let end = value.firstIndex(of: "'") { value = String(value[..<end]) }
                } else if value.hasPrefix("\"") {
                    value.removeFirst()
                    if let end = value.firstIndex(of: "\"") { value = String(value[..<end]) }
                } else if let end = value.firstIndex(where: { $0 == " " || $0 == "\t" || $0 == "#" }) {
                    value = String(value[..<end])
                }
                if !value.isEmpty { return value }
            }
        }
        return nil
    }

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
        // GUI 启动的进程环境精简、不读 .zshrc：自动补上 DEEPSEEK_API_KEY，否则 llm 报 no API key
        if env["DEEPSEEK_API_KEY"] == nil, let key = deepseekApiKeyFromShell() {
            env["DEEPSEEK_API_KEY"] = key
            keyProvisioned = true
        }
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
