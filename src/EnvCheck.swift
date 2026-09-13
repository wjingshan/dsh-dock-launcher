// EnvCheck.swift — 运行环境自检
// 检查：芯片架构、macOS 版本、dsh 是否安装、zstd 是否可用、DEEPSEEK_API_KEY 是否存在。
// 目的：别人第一次使用本 App 时，缺什么就明确告诉他怎么补，而不是静默失败。
import Darwin
import Foundation

enum EnvSeverity { case critical, warning, info }

/// 一条检测结果（titleKey/detailArg 交给本地化与格式化）
struct EnvFinding {
    let severity: EnvSeverity
    let titleKey: String
    let detailArg: String
}

enum EnvCheck {

    /// 执行一次完整自检
    static func run() -> [EnvFinding] {
        var out: [EnvFinding] = []

        out.append(EnvFinding(severity: .info, titleKey: "env.arch", detailArg: cpuArch()))
        out.append(EnvFinding(severity: .info, titleKey: "env.os", detailArg: osVersion()))

        // DeepSeek Harness（必要条件：没有它本 App 无法启动服务）
        if let dsh = ServiceManager.findDsh() {
            out.append(EnvFinding(severity: .info, titleKey: "env.dsh.found", detailArg: dsh.path))
        } else {
            out.append(EnvFinding(severity: .critical, titleKey: "env.dsh.missing", detailArg: ""))
        }

        // zstd（任务状态监测依赖；缺失则降级为“只显示服务状态”）
        if let zstd = TaskMonitor.zstdExecutablePath() {
            out.append(EnvFinding(severity: .info, titleKey: "env.zstd.found", detailArg: zstd))
        } else {
            out.append(EnvFinding(severity: .warning, titleKey: "env.zstd.missing", detailArg: ""))
        }

        // DEEPSEEK_API_KEY（影响 dsh 能否调用模型）
        if apiKeyPresent() {
            out.append(EnvFinding(severity: .info, titleKey: "env.apikey.found", detailArg: ""))
        } else {
            out.append(EnvFinding(severity: .warning, titleKey: "env.apikey.missing", detailArg: ""))
        }

        // dock-bridge 宿主插件（可选增强：装了就直接拿到带 token 的地址，不必回退去读日志）
        if ServiceManager.tokenURLFromDockBridge() != nil {
            out.append(EnvFinding(severity: .info, titleKey: "env.bridge.found", detailArg: ""))
        } else {
            out.append(EnvFinding(severity: .info, titleKey: "env.bridge.absent", detailArg: ""))
        }

        return out
    }

    static func hasCritical(_ findings: [EnvFinding]) -> Bool {
        findings.contains { $0.severity == .critical }
    }

    static func hasWarning(_ findings: [EnvFinding]) -> Bool {
        findings.contains { $0.severity == .warning }
    }

    /// 当前芯片架构（arm64 / x86_64）
    static func cpuArch() -> String {
        var info = utsname()
        uname(&info)
        let machine = withUnsafePointer(to: &info.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) {
                String(cString: $0)
            }
        }
        return machine.isEmpty ? "unknown" : machine
    }

    /// 当前 macOS 版本
    static func osVersion() -> String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    /// 是否已有可用的 DEEPSEEK_API_KEY（进程环境或 shell 配置）
    static func apiKeyPresent() -> Bool {
        if let k = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"], !k.isEmpty { return true }
        return ServiceManager.deepseekApiKeyFromShell() != nil
    }
}
