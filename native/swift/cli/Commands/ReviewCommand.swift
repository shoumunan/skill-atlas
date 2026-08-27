import Foundation
#if SWIFT_PACKAGE
import AtlasCore
#endif

// MARK: - atlas review list [--json]
//
// 批准只能在 GUI（skillatlas://review/<token>）。CLI 只列待审。

enum ReviewCommand {
    static func run(_ args: Args) -> Int32 {
        let sub = args.positionals.first ?? "list"
        guard sub == "list" else {
            return fail(op: "review", json: args.json, code: .usage,
                        message: L("用法：atlas review list"))
        }
        let reviews = PendingReviews.list()
        let data: [String: Any] = [
            "reviews": reviews.map { review -> [String: Any] in
                [
                    "token": review.token,
                    "createdAt": review.createdAt,
                    "url": review.source.url,
                    "commit": review.source.commit,
                    "reviewURL": "skillatlas://review/\(review.token)",
                    "candidates": review.candidates.map(\.dir),
                    "findings": review.findings.count,
                ]
            },
            "count": reviews.count,
        ]
        return succeed(op: "review", json: args.json, data: data) {
            if reviews.isEmpty {
                say(L("没有待审安装。"))
                return
            }
            for review in reviews {
                say("\(review.token)\t\(review.source.url)\t\(review.candidates.map(\.dir).joined(separator: ","))")
            }
        }
    }
}
