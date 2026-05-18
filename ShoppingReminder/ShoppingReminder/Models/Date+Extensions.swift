import Foundation

extension Date {
    /// 日付を「M/d(E)」形式（例: 5/8(土)）の日本語でフォーマットします
    func japaneseFormatted() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M/d(E)"
        return formatter.string(from: self)
    }
    
    /// 日付を「yyyy/MM/dd(E) HH:mm」形式でフォーマットします
    func japaneseDateTimeFormatted() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy/MM/dd(E) HH:mm"
        return formatter.string(from: self)
    }
}
