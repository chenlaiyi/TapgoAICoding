import XCTest
import Foundation

final class MobileModelCatalogTests: XCTestCase {
    func testCatalogKeepsReasoningLevelsAndDescriptions() {
        let catalog: [String: Any] = [
            "default": ["provider": "deepseek-account", "model": "deepseek-v41-flash"],
            "groups": [[
                "id": "deepseek-account",
                "models": [[
                    "id": "deepseek-v41-flash",
                    "name": "DeepSeek V41 Flash",
                    "description": "日常任务",
                    "reasoning": [
                        "efforts": [["id": "low", "name": "低"], ["id": "high", "name": "高"]],
                        "defaultEffort": "high",
                    ],
                ]],
            ]],
        ]
        let models = MobileModelCatalog.models(from: catalog)
        XCTAssertEqual(models.count, 1)
        XCTAssertEqual(models.first?.id, "deepseek-account/deepseek-v41-flash")
        XCTAssertEqual(models.first?.detail, "日常任务")
        XCTAssertEqual(models.first?.efforts.map(\.id), ["low", "high"])
        XCTAssertEqual(models.first?.efforts.map(\.name), ["低", "高"])
        XCTAssertEqual(models.first?.defaultEffort, "high")
        XCTAssertEqual(MobileModelCatalog.defaultRoute(from: catalog), "deepseek-account/deepseek-v41-flash")
    }

    func testCatalogSkipsIncompleteRoutes() {
        let catalog: [String: Any] = [
            "groups": [
                ["models": [["id": "orphan"]]],
                ["id": "provider", "models": [["name": "无 id"], ["id": "model", "reasoning": ["efforts": [["name": "无 id"]]]]]],
            ],
        ]
        let models = MobileModelCatalog.models(from: catalog)
        XCTAssertEqual(models.map(\.id), ["provider/model"])
        XCTAssertTrue(models.first?.efforts.isEmpty == true)
        XCTAssertNil(MobileModelCatalog.defaultRoute(from: catalog))
    }

    func testSelectionNeedsARequestOnlyForRealChanges() {
        let model = MobileModel(provider: "p", model: "m", name: "M",
                                efforts: [MobileModelReasoning(id: "low", name: "低"),
                                          MobileModelReasoning(id: "high", name: "高")],
                                defaultEffort: "high")
        XCTAssertTrue(MobileModelCatalog.requiresSelection(currentModel: "p/other", currentEffort: nil,
                                                           model: model, effort: nil))
        XCTAssertFalse(MobileModelCatalog.requiresSelection(currentModel: "p/m", currentEffort: nil,
                                                            model: model, effort: nil))
        XCTAssertFalse(MobileModelCatalog.requiresSelection(currentModel: "p/m", currentEffort: "high",
                                                            model: model, effort: "high"))
        XCTAssertTrue(MobileModelCatalog.requiresSelection(currentModel: "p/m", currentEffort: "high",
                                                           model: model, effort: "low"))
        XCTAssertTrue(MobileModelCatalog.requiresSelection(currentModel: "p/m", currentEffort: nil,
                                                           model: model, effort: "low"))
    }

    func testRouteWithoutReasoningIgnoresLevels() {
        let model = MobileModel(provider: "p", model: "m", name: "M")
        XCTAssertFalse(MobileModelCatalog.requiresSelection(currentModel: "p/m", currentEffort: nil,
                                                            model: model, effort: nil))
    }

    func testEffortNameRequiresADeclaredLevel() {
        let model = MobileModel(provider: "p", model: "m", name: "M",
                                efforts: [MobileModelReasoning(id: "low", name: "低")])
        XCTAssertEqual(MobileModelCatalog.effortName("low", in: model), "低")
        XCTAssertNil(MobileModelCatalog.effortName("high", in: model))
        XCTAssertNil(MobileModelCatalog.effortName(nil, in: model))
        XCTAssertNil(MobileModelCatalog.effortName("low", in: nil))
    }
}
