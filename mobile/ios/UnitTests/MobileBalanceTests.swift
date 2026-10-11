import XCTest

final class MobileBalanceTests: XCTestCase {
    func testCredentialSelectionAndCurrencyPrecision() {
        var funds = MobileBalanceSnapshot()
        funds.account = "¥-0.05"
        funds.providers["deepseek-official"] = "¥86.77"
        XCTAssertEqual(funds.available(provider: "deepseek-account"), "¥-0.05")
        XCTAssertEqual(funds.available(provider: "deepseek-official"), "¥86.77")
        XCTAssertNil(funds.available(provider: "unsupported"))
        XCTAssertEqual(MobileBalanceSnapshot.amounts([
            ["currency": "CNY", "amount": "0.1"], ["currency": "CNY", "amount": "0.2"],
            ["currency": "USD", "amount": "1.235"]], field: "amount"), "¥0.30 · $1.24")
        XCTAssertNil(MobileBalanceSnapshot.amounts([["currency": "CNY", "amount": "broken"]], field: "amount"))
        XCTAssertNil(MobileBalanceSnapshot.amounts([], field: "amount"))
    }

    @MainActor func testApiReadsContinueWhenAccountIsUnavailable() async {
        var routes: [String] = []
        let funds = await MobileBalanceSnapshot.load(provider: "unsupported") { method, args in
            if method == "account/getBalance" { throw NSError(domain: "fixture", code: 1) }
            routes.append(args["provider"] as! String)
            return args["provider"] as? String == "deepseek-official"
                ? [["currency": "CNY", "amount": "86.77"]] : NSNull()
        }
        XCTAssertNil(funds.account)
        XCTAssertEqual(funds.available(provider: "deepseek-official"), "¥86.77")
        XCTAssertNil(funds.available(provider: "unsupported"))
        XCTAssertEqual(routes, ["deepseek-official", "unsupported"])
    }
}
