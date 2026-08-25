// TapgoTests/AgentCapabilitiesTests.swift
import Foundation
import TapgoCore

@MainActor
func runAgentCapabilities(_ t: TestRunner) {
    let skills = AgentCapabilities.skills
    t.expect(!skills.isEmpty, "skills: non-empty")
    // Unique ids.
    let ids = Set(skills.map { $0.id })
    t.expectEqual(ids.count, skills.count, "skills: ids unique")
    // Every skill has a non-empty name/icon/detail.
    t.expect(skills.allSatisfy { !$0.name.isEmpty }, "skills: names non-empty")
    t.expect(skills.allSatisfy { !$0.icon.isEmpty }, "skills: icons non-empty")
    t.expect(skills.allSatisfy { !$0.detail.isEmpty }, "skills: details non-empty")
    // Includes the core categories.
    t.expect(skills.contains { $0.name == "终端执行" }, "skills: has shell")
    t.expect(skills.contains { $0.name == "文件读写" }, "skills: has files")
}
