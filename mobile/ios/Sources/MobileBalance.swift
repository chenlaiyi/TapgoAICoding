import Foundation

/// Funds belong to the Host credential for one provider, never to a similarly named model.
struct MobileBalanceSnapshot {
    var account: String?
    var accountDetails: [String] = []
    var providers: [String: String] = [:]

    func available(provider: String?) -> String? {
        guard let provider else { return nil }
        return provider == "deepseek-account" ? account : providers[provider]
    }

    static func amounts(_ rows: [[String: Any]], field: String) -> String? {
        var totals: [String: Decimal] = [:]
        for row in rows {
            guard let currency = row["currency"] as? String,
                  let raw = row[field] as? String,
                  raw.range(of: #"^[+-]?(?:[0-9]+(?:\.[0-9]+)?|\.[0-9]+)$"#, options: .regularExpression) != nil,
                  let amount = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")),
                  !amount.isNaN else { return nil }
            totals[currency, default: .zero] += amount
        }
        return totals.keys.sorted().map { currency in
            let symbol = ["CNY": "¥", "USD": "$", "EUR": "€"][currency] ?? "\(currency) "
            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.numberStyle = .decimal
            formatter.roundingMode = .halfUp
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 2
            return symbol + (formatter.string(from: NSDecimalNumber(decimal: totals[currency]!)) ?? "—")
        }.joined(separator: " · ").nilIfEmpty
    }

    @MainActor
    static func load(provider: String?, read: (String, [String: Any]) async throws -> Any) async -> Self {
        var result = Self()
        let metadata: [String: Any] = ["version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
                                      "locale": Locale.current.identifier,
                                      "timezoneOffsetSeconds": TimeZone.current.secondsFromGMT()]
        if let account = try? await read("account/getBalance", ["client": metadata]) as? [String: Any],
           account["status"] as? String == "ready" {
            let recharge = account["value"] as? [[String: Any]] ?? []
            let bonus = account["bonusWallets"] as? [[String: Any]] ?? []
            result.account = amounts(recharge + bonus, field: "balance")
            if let value = amounts(recharge, field: "balance") { result.accountDetails.append("充值余额 \(value)") }
            if let value = amounts(bonus, field: "balance") { result.accountDetails.append("赠金余额 \(value)") }
        }
        var routes = Set(["deepseek-official"])
        if let provider, provider != "deepseek-account" { routes.insert(provider) }
        for route in routes.sorted() {
            if let rows = try? await read("llm/getBalance", ["provider": route]) as? [[String: Any]],
               let value = amounts(rows, field: "amount") { result.providers[route] = value }
        }
        return result
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
