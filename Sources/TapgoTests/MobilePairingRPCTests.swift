// TapgoTests/MobilePairingRPCTests.swift
// v1.0.2 Phase 3: 原生配对长链接响应构造纯函数回归。
import Foundation
@testable import TapgoCore

func runMobilePairingRPC(_ t: TestRunner) {
    // MARK: errorParams 约定

    let err = MobilePairingRPC.errorParams("boom")
    t.expectEqual(err["error"]?.stringValue, "boom", "errorParams: error 字段带回消息")
    t.expectEqual(err["ok"]?.boolValue, false, "errorParams: ok=false")
    t.expect(err["sessions"] == nil, "errorParams: 不带业务字段")

    // MARK: listSessionsResponse

    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let older = now.addingTimeInterval(-3600)
    let auxiliary = MobilePairingRPC.SessionSeed(
        id: "aux", title: "工作台", projectId: "p1", projectName: "项目一",
        updatedAt: now, isAuxiliary: true)
    let s1 = MobilePairingRPC.SessionSeed(
        id: "t1", title: "会话一", projectId: "p1", projectName: "项目一",
        updatedAt: now, isAuxiliary: false)
    let s2 = MobilePairingRPC.SessionSeed(
        id: "t2", title: "会话二", projectId: "p2", projectName: nil,
        updatedAt: older, isAuxiliary: false)
    let s3 = MobilePairingRPC.SessionSeed(
        id: "t3", title: "无项目", projectId: nil, projectName: nil,
        updatedAt: older.addingTimeInterval(-60), isAuxiliary: false)

    let list = MobilePairingRPC.listSessionsResponse(
        sessions: [auxiliary, s2, s1, s3], activeThreadId: "t1")
    guard case .array(let arr)? = list["sessions"] else {
        t.expect(false, "list: sessions 是数组")
        return
    }
    t.expectEqual(arr.count, 3, "list: 辅助会话被过滤 (3 条非辅助)")
    let ids = arr.compactMap { v -> String? in
        guard case .object(let o) = v else { return nil }
        return o["id"]?.stringValue
    }
    t.expectEqual(ids, ["t1", "t2", "t3"], "list: 按 updatedAt 降序")

    guard case .object(let first)? = arr.first else {
        t.expect(false, "list: 首条是 object")
        return
    }
    t.expectEqual(first["title"]?.stringValue, "会话一", "list: title 字段")
    t.expectEqual(first["projectId"]?.stringValue, "p1", "list: projectId 字段")
    t.expectEqual(first["project"]?.stringValue, "项目一", "list: project 用 Seed 名")
    t.expect(first["updatedAt"]?.stringValue?.contains("T") == true,
             "list: updatedAt 为 ISO8601")
    t.expectEqual(list["activeSessionId"]?.stringValue, "t1", "list: activeSessionId 透传")

    guard case .object(let noProject)? = arr.last else {
        t.expect(false, "list: 末条是 object")
        return
    }
    t.expect(noProject["projectId"] == nil, "list: 无 projectId 时不带该字段")

    let empty = MobilePairingRPC.listSessionsResponse(sessions: [], activeThreadId: nil)
    if case .array(let a)? = empty["sessions"] {
        t.expectEqual(a.count, 0, "list: 空输入返回空数组")
    } else {
        t.expect(false, "list: 空输入仍有 sessions 键")
    }

    // MARK: switchProjectResponse

    let projects = [
        MobilePairingRPC.ProjectSeed(id: "p1", name: "TapgoAICoding"),
        MobilePairingRPC.ProjectSeed(id: "p2", name: "Other"),
    ]
    var applied: String?
    let ok = MobilePairingRPC.switchProjectResponse(id: "p1", projects: projects) {
        applied = "p1"
    }
    t.expectEqual(applied, "p1", "switch: 命中时 action 执行")
    t.expectEqual(ok["ok"]?.boolValue, true, "switch: ok=true")
    t.expectEqual(ok["projectId"]?.stringValue, "p1", "switch: projectId 回显")
    t.expectEqual(ok["projectName"]?.stringValue, "TapgoAICoding", "switch: projectName 回显")
    t.expect(ok["error"] == nil, "switch: 成功不带 error")

    var notApplied = false
    let miss = MobilePairingRPC.switchProjectResponse(id: "nope", projects: projects) {
        notApplied = true
    }
    t.expect(!notApplied, "switch: 未命中时 action 不执行")
    t.expectEqual(miss["ok"]?.boolValue, false, "switch: 未命中 ok=false")
    t.expectEqual(miss["error"]?.stringValue, "project not found: nope",
                  "switch: 未命中 error 消息")
}
